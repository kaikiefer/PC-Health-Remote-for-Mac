import Foundation
import Darwin
import IOKit.ps
import IOKit

final class MetricsCollector {
    private var previous: [UInt32]?
    private var topCPU = "", topRAM = ""
    private var cpuPercent = 0, ramPercent = 0, samples = 0
    private lazy var hardware = phr_hardware_create()

    deinit { phr_hardware_destroy(hardware) }

    func sample() -> Metrics {
        var m = Metrics()
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let now = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
            if let old = previous {
                let d = zip(now, old).map { UInt64($0 &- $1) }
                let total = d.reduce(0, +)
                if total > 0 { m.cpu = Int(Double(total - d[2]) / Double(total) * 100) }
            }
            previous = now
        }
        let physical = ProcessInfo.processInfo.physicalMemory
        m.ramGB = Double(physical) / 1_000_000_000
        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
            }
        }
        if vmResult == KERN_SUCCESS {
            // Internal resident pages exclude file-backed cache, which can be reclaimed.
            let pages = UInt64(vm.internal_page_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
            let used = pages > UInt64(vm.purgeable_count) ? pages - UInt64(vm.purgeable_count) : 0
            m.ram = min(100, Int(Double(used) * Double(vm_kernel_page_size) / Double(physical) * 100))
        }
        // The writable Data volume shares APFS container space with the system volume.
        if let fs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let total = fs[.systemSize] as? NSNumber, let free = fs[.systemFreeSize] as? NSNumber,
           total.doubleValue > 0 {
            m.disk = Int((1 - free.doubleValue / total.doubleValue) * 100)
        }
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let d = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                      d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                      let current = d[kIOPSCurrentCapacityKey] as? Int,
                      let maximum = d[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
                m.battery = max(0, min(100, current * 100 / maximum))
                m.onBattery = d[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
                m.charging = d[kIOPSIsChargingKey] as? Bool ?? false
                break
            }
        }
        if samples % 5 == 0 { processes() }; samples += 1
        m.topCPU = topCPU; m.topRAM = topRAM
        m.topCPUPercent = cpuPercent; m.topRAMPercent = ramPercent
        m.uptimeHours = Int(ProcessInfo.processInfo.systemUptime / 3600)
        let sensors = phr_hardware_sample(hardware)
        if sensors.cpuTemperature.isFinite { m.cpuTemperature = Int(sensors.cpuTemperature.rounded()) }
        if sensors.gpuTemperature.isFinite { m.gpuTemperature = Int(sensors.gpuTemperature.rounded()) }
        if sensors.fanRPM >= 0 { m.fanRPM = Int(sensors.fanRPM) }
        m.cpuMHz = Int(sensors.cpuMHz)
        gpuMetrics(&m, physicalMemory: physical)
        return m
    }

    private func gpuMetrics(_ m: inout Metrics, physicalMemory: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
                  let load = stats["Device Utilization %"] as? NSNumber else { continue }
            m.gpu = max(0, min(100, load.intValue))
            if let bytes = stats["In use system memory"] as? NSNumber, physicalMemory > 0 {
                // Apple silicon has no dedicated VRAM. Report actual GPU-resident shared
                // memory as a fraction of physical unified memory, not all system RAM use.
                m.gpuMemoryGB = bytes.doubleValue / 1_000_000_000
                m.vramGB = Double(physicalMemory) / 1_000_000_000
                m.vram = max(0, min(100, Int(bytes.doubleValue / Double(physicalMemory) * 100)))
            }
            return
        }
    }

    private func processes() {
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-A", "-o", "%cpu=,%mem=,comm="]
        task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
        guard task.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return }
        var maxCPU = -1.0, maxRAM = -1.0
        for line in text.split(separator: "\n") {
            let fields = line.split(maxSplits: 2, whereSeparator: { $0.isWhitespace })
            guard fields.count == 3, let cpu = Double(fields[0]), let ram = Double(fields[1]) else { continue }
            let name = URL(fileURLWithPath: String(fields[2])).lastPathComponent
            if cpu > maxCPU { maxCPU = cpu; topCPU = name }
            if ram > maxRAM { maxRAM = ram; topRAM = name }
        }
        // macOS ps reports per-core CPU as a decaying recent average,
        // rather than the latest host sampling interval.
        cpuPercent = max(0, min(100, Int(maxCPU / Double(ProcessInfo.processInfo.activeProcessorCount))))
        ramPercent = max(0, min(100, Int(maxRAM)))
    }
}

import Foundation

struct Metrics {
    var cpu = 0, ram = 0, disk = 0
    var ramGB: Double = 0
    var battery: Int? = nil
    var onBattery = false, charging = false
    var topCPU = "", topRAM = ""
    var topCPUPercent = 0, topRAMPercent = 0
    var uptimeHours = 0
    var cpuTemperature: Int?, gpuTemperature: Int?, gpu: Int?, fanRPM: Int?
    var cpuMHz = 0, vram = 0
    var vramGB: Double = 0, gpuMemoryGB: Double = 0
}

enum Wire {
    static func crc(_ bytes: [UInt8]) -> UInt16 {
        var value: UInt16 = 0xffff
        for byte in bytes {
            value ^= UInt16(byte) << 8
            for _ in 0..<8 {
                value = value & 0x8000 != 0 ? (value &<< 1) ^ 0x1021 : value &<< 1
            }
        }
        return value
    }

    static func telemetry(_ m: Metrics, sequence: UInt8) -> Data {
        var bytes = [UInt8](repeating: 0, count: 48)
        func byte(_ n: Int) -> UInt8 { UInt8(clamping: max(0, min(100, n))) }
        func word(_ offset: Int, _ n: Int) {
            let v = UInt16(clamping: n)
            bytes[offset] = UInt8(v & 255); bytes[offset + 1] = UInt8(v >> 8)
        }
        func name(_ offset: Int, _ size: Int, _ text: String) {
            let ascii = text.unicodeScalars.map { $0.value < 128 ? UInt8($0.value) : 63 }
            for (i, c) in ascii.prefix(size).enumerated() { bytes[offset + i] = c }
        }
        bytes[0...4] = [0x50, 0x48, 1, 1, sequence][...]
        bytes[5] = (m.onBattery ? 1 : 0) | (m.charging ? 2 : 0) | (m.battery != nil ? 32 : 0)
        if m.cpuTemperature != nil { bytes[5] |= 4 }
        if m.gpu != nil { bytes[5] |= 8 }
        if m.gpuTemperature != nil && m.gpu != nil { bytes[5] |= 16 }
        if m.fanRPM != nil { bytes[5] |= 64 }
        bytes[6] = byte(m.cpu); bytes[10] = byte(m.ram); bytes[12] = byte(m.disk)
        bytes[7] = UInt8(clamping: max(0, m.cpuTemperature ?? 0))
        bytes[8] = byte(m.gpu ?? 0); bytes[9] = UInt8(clamping: max(0, m.gpuTemperature ?? 0))
        bytes[11] = byte(m.vram)
        bytes[13] = byte(m.battery ?? 0)
        word(14, Int(m.ramGB * 10)); word(44, m.uptimeHours)
        word(16, Int(m.vramGB * 10)); word(18, m.cpuMHz); word(20, m.fanRPM ?? 0)
        bytes[22] = byte(m.topCPUPercent); bytes[23] = byte(m.topRAMPercent)
        name(24, 12, m.topCPU); name(36, 8, m.topRAM)
        word(46, Int(crc(Array(bytes.prefix(46)))))
        return Data(bytes)
    }
}

struct HelloParser {
    private var buffer: [UInt8] = []
    mutating func feed(_ data: Data, transport: UInt8) -> [Int] {
        buffer.append(contentsOf: data)
        var intervals: [Int] = []
        while buffer.count >= 12 {
            if buffer[0] == 0x50, buffer[1] == 0x48, buffer[2] == 1, buffer[3] == 0x81,
               buffer[7] == transport, (1...10).contains(buffer[8]), buffer[9] == 0,
               Wire.crc(Array(buffer.prefix(10))) == UInt16(buffer[10]) | UInt16(buffer[11]) << 8 {
                intervals.append(Int(buffer[8])); buffer.removeFirst(12)
            } else { buffer.removeFirst() }
        }
        return intervals
    }
}

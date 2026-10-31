import Foundation
import Darwin

@main
struct Tests {
    static func main() {
        precondition(Wire.crc(Array("123456789".utf8)) == 0x29b1, "CRC standard vector")
        var m = Metrics()
        m.cpu = 77; m.ram = 42; m.disk = 63; m.ramGB = 16
        m.battery = 85; m.onBattery = true; m.topCPU = "LongProcessName"; m.topRAM = "Mémoire"
        m.uptimeHours = 432; m.topCPUPercent = 14; m.topRAMPercent = 22
        let frame = Wire.telemetry(m, sequence: 255), b = Array(frame)
        precondition(b.count == 48 && b[4] == 255 && b[5] == 33)
        precondition(b[6] == 77 && b[10] == 42 && b[12] == 63 && b[13] == 85)
        precondition(b[14] == 160 && b[15] == 0 && b[44] == 176 && b[45] == 1)
        precondition(String(bytes: b[24..<36], encoding: .ascii) == "LongProcessN")
        precondition(b[37] == 63 && b[43] == 0, "ASCII replacement and NUL padding")
        precondition(Wire.crc(Array(b.prefix(46))) == UInt16(b[46]) | UInt16(b[47]) << 8)
        precondition(b[5] & 0x5c == 0, "Unavailable sensor flags must be clear")
        m.cpu = 999; m.ram = -5; m.uptimeHours = 999999
        let clamped = Array(Wire.telemetry(m, sequence: 0))
        precondition(clamped[6] == 100 && clamped[10] == 0 && clamped[44] == 255 && clamped[45] == 255)
        let hello = makeHello(1, 2)
        var parser = HelloParser()
        precondition(parser.feed(Data([1, 2, 3]) + hello.prefix(7), transport: 1).isEmpty)
        precondition(parser.feed(hello.suffix(5), transport: 1) == [2], "Fragment reassembly")
        var corrupt = hello; corrupt[10] ^= 1
        precondition(parser.feed(corrupt + hello + hello, transport: 1) == [2, 2], "CRC recovery and coalescing")
        precondition(parser.feed(makeHello(0, 1), transport: 1).isEmpty, "Wrong transport")
        precondition(parser.feed(makeHello(1, 0), transport: 1).isEmpty, "Invalid interval")
        precondition(parser.feed(makeHello(1, 10), transport: 1) == [10])
        try! frame.write(to: URL(fileURLWithPath: "build/test-telemetry.bin"))
        m.cpuTemperature = 107; m.gpuTemperature = 102; m.gpu = 58
        m.vram = 12; m.vramGB = 17.2; m.cpuMHz = 2400; m.fanRPM = 1750
        let sensors = Wire.telemetry(m, sequence: 7), sb = Array(sensors)
        precondition(sb[5] == 125 && sb[7] == 107 && sb[8] == 58 && sb[9] == 102 && sb[11] == 12)
        precondition(sb[16] == 172 && sb[18] == 96 && sb[19] == 9 && sb[20] == 214 && sb[21] == 6)
        try! sensors.write(to: URL(fileURLWithPath: "build/test-sensors.bin"))
        m.fanRPM = 0
        precondition(Array(Wire.telemetry(m, sequence: 0))[5] & 64 != 0, "Stopped fan is valid; absent fan is nil")
        let collector = MetricsCollector()
        _ = collector.sample(); usleep(100_000)
        let live = collector.sample()
        precondition((0...100).contains(live.cpu) && (0...100).contains(live.ram) && (0...100).contains(live.disk))
        precondition(live.ramGB > 0 && !live.topCPU.isEmpty && !live.topRAM.isEmpty)
        print("Live metrics: CPU \(live.cpu)%, RAM \(live.ram)%, disk \(live.disk)%, \(live.ramGB) GB")
        print("Hardware: CPU temp \(String(describing: live.cpuTemperature)), GPU temp \(String(describing: live.gpuTemperature)), GPU \(String(describing: live.gpu))%, shared GPU memory \(live.gpuMemoryGB)/\(live.vramGB) GB, clock \(live.cpuMHz) MHz, fan \(String(describing: live.fanRPM))")
        testUSB()
        print("PASS: protocol vectors, parser, bounds, live metrics, USB handshake and timeout")
    }
    static func makeHello(_ transport: UInt8, _ interval: UInt8) -> Data {
        var b: [UInt8] = [0x50, 0x48, 1, 0x81, 0, 100, 0, transport, interval, 0]
        let crc = Wire.crc(b); b += [UInt8(crc & 255), UInt8(crc >> 8)]
        return Data(b)
    }
    static func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
    static func testUSB() {
        var master: Int32 = -1, slave: Int32 = -1
        var name = [CChar](repeating: 0, count: 1024)
        precondition(openpty(&master, &slave, &name, nil, nil) == 0)
        defer { close(master); close(slave) }
        _ = fcntl(master, F_SETFL, O_NONBLOCK)
        let path = String(cString: name)
        // Pseudo-terminals have no modem control lines. Only DTR is stubbed;
        // termios setup, nonblocking I/O, parser, timers and writes are production code.
        let usb = USBLink(candidates: { [path] }, enableDTR: { _ in true })
        usb.frame = { Wire.telemetry(Metrics(), sequence: 0) }
        var statuses: [String] = [], sent = 0
        usb.onStatus = { statuses.append($0) }; usb.onSent = { sent += 1 }
        usb.start(); spin(0.3)
        var buffer = [UInt8](repeating: 0, count: 512)
        precondition(read(master, &buffer, buffer.count) < 0, "No write before HELLO")
        let invalid = Data("normal CLI text\r\n".utf8)
        invalid.withUnsafeBytes { _ = write(master, $0.baseAddress, $0.count) }
        spin(0.2)
        precondition(read(master, &buffer, buffer.count) < 0, "No write to normal CLI")
        let hello = makeHello(1, 1)
        hello.withUnsafeBytes { _ = write(master, $0.baseAddress, $0.count) }
        spin(0.3)
        precondition(usb.ready, "USB HELLO accepted: \(statuses)")
        precondition(read(master, &buffer, buffer.count) == 48 && sent == 1)
        usb.stop()
        precondition(!usb.ready)
        usb.start(); spin(3.3)
        precondition(!usb.ready && statuses.contains(where: { $0.contains("No USB HELLO") }), "Handshake timeout releases port")
        precondition(read(master, &buffer, buffer.count) < 0, "No telemetry after reconnect without HELLO")
        usb.stop()
    }
}

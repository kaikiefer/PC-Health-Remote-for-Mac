import Foundation
import Darwin
import IOKit
import IOKit.serial

final class USBLink {
    var onStatus: (String) -> Void = { _ in }
    var onSent: () -> Void = {}
    var frame: () -> Data = { Data() }
    private var fd: Int32 = -1
    private var parser = HelloParser()
    private var timer: Timer?
    private var opened = Date.distantPast, lastHello = Date.distantPast
    private var nextProbe = Date.distantPast, nextSend = Date.distantPast
    private var interval: TimeInterval = 1
    private var pending = Data()
    private var path = ""
    private(set) var ready = false
    private let candidates: () -> [String]
    private let enableDTR: (Int32) -> Bool

    init(candidates: @escaping () -> [String] = USBLink.ports,
         enableDTR: @escaping (Int32) -> Bool = { fd in
             var dtr = TIOCM_DTR
             return ioctl(fd, TIOCMBIS, &dtr) == 0
         }) {
        self.candidates = candidates; self.enableDTR = enableDTR
    }

    static func ports() -> [String] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOSerialBSDServiceValue), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var paths: [String] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            func property(_ name: String) -> Any? {
                IORegistryEntrySearchCFProperty(service, kIOServicePlane, name as CFString, kCFAllocatorDefault, options)
            }
            if (property("idVendor") as? NSNumber)?.intValue == 0x0483,
               (property("idProduct") as? NSNumber)?.intValue == 0x5740,
               let path = property(kIOCalloutDeviceKey) as? String { paths.append(path) }
        }
        return paths.sorted()
    }

    func start() {
        stop(); nextProbe = .distantPast
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }
    func stop() {
        timer?.invalidate(); timer = nil; closePort()
    }
    private func closePort() {
        if fd >= 0 { Darwin.close(fd) }; fd = -1; ready = false
        pending.removeAll(); parser = HelloParser()
    }
    private func fail(_ message: String) {
        closePort(); nextProbe = Date().addingTimeInterval(3); onStatus(message)
    }
    private func tick() {
        let now = Date()
        if fd < 0 {
            guard now >= nextProbe else { return }
            nextProbe = now.addingTimeInterval(3)
            let ports = candidates()
            guard !ports.isEmpty else { onStatus("Waiting for a Flipper USB cable"); return }
            // Rotate across attached Flippers on each probe.
            let index = ports.firstIndex(of: path).map { ($0 + 1) % ports.count } ?? 0
            path = ports[index]
            fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
            guard fd >= 0 else {
                let message = String(cString: strerror(errno))
                onStatus("Cannot open \(path): \(message). Close qFlipper or other serial apps and retry.")
                return
            }
            var settings = termios()
            guard tcgetattr(fd, &settings) == 0 else { fail("Cannot configure USB port"); return }
            cfmakeraw(&settings); cfsetspeed(&settings, speed_t(B115200))
            settings.c_cflag |= tcflag_t(CLOCAL | CREAD)
            guard tcsetattr(fd, TCSANOW, &settings) == 0 else { fail("Cannot configure USB port"); return }
            guard enableDTR(fd) else { fail("Cannot enable USB DTR: \(String(cString: strerror(errno)))"); return }
            opened = now; lastHello = .distantPast; nextSend = .distantPast
            onStatus("USB: waiting for PC Health Remote HELLO…")
        }
        for _ in 0..<16 {
            var bytes = [UInt8](repeating: 0, count: 512)
            let n = Darwin.read(fd, &bytes, bytes.count)
            if n < 0 {
                if errno != EAGAIN && errno != EWOULDBLOCK { fail("USB disconnected") }
                break
            }
            if n == 0 { break }
            for seconds in parser.feed(Data(bytes.prefix(n)), transport: 1) {
                interval = Double(seconds); lastHello = now
                if !ready { ready = true; onStatus("Connected over USB · \(path)") }
            }
        }
        guard fd >= 0 else { return }
        if !ready && now.timeIntervalSince(opened) >= 3 {
            fail("No USB HELLO. Open PC Health Remote on Flipper and select USB."); return
        }
        if ready && now.timeIntervalSince(lastHello) > 30 { fail("USB link timed out; reconnecting…"); return }
        // Never send to the normal CLI: a CRC-validated USB HELLO is mandatory.
        if ready && now >= nextSend && pending.isEmpty {
            pending = frame(); nextSend = now.addingTimeInterval(interval)
        }
        if !pending.isEmpty {
            let n = pending.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if n > 0 { pending.removeFirst(n); if pending.isEmpty { onSent() } }
            else if n < 0 && errno != EAGAIN && errno != EWOULDBLOCK { fail("USB write failed") }
        }
    }
}

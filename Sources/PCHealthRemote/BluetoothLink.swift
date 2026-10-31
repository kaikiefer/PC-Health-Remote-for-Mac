import Foundation
import CoreBluetooth

final class BluetoothLink: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    struct Device: Identifiable { let id: UUID; let name: String; let rssi: Int }
    static let service = CBUUID(string: "8fe5b3d5-2e7f-4a98-2a48-7acc60fe0000")
    static let rxID = CBUUID(string: "19ed82ae-ed21-4c9d-4145-228e62fe0000")
    static let txID = CBUUID(string: "19ed82ae-ed21-4c9d-4145-228e61fe0000")
    var onStatus: (String) -> Void = { _ in }
    var onDevices: ([Device]) -> Void = { _ in }
    var onSent: () -> Void = {}
    var frame: () -> Data = { Data() }
    private var central: CBCentralManager!
    private var enabled = false
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var devices: [UUID: Device] = [:]
    private var peripheral: CBPeripheral?
    private var rx: CBCharacteristic?
    private var parser = HelloParser()
    private var timer: Timer?
    private var deadline = Date.distantFuture, lastHello = Date.distantPast, nextSend = Date.distantPast
    private var interval: TimeInterval = 1
    private var pending = Data()
    private var awaitingWrite = false
    private(set) var ready = false
    private var savedID: UUID? {
        get { UserDefaults.standard.string(forKey: "deviceID").flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "deviceID") }
    }

    func start() {
        enabled = true
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else if central.state == .poweredOn { scan() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
    }
    func stop() {
        enabled = false; timer?.invalidate(); timer = nil
        central?.stopScan()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        clear()
    }
    func forget() {
        let wasEnabled = enabled
        stop(); savedID = nil; devices = [:]; peripherals = [:]; onDevices([])
        if wasEnabled { start() }
    }
    func connect(_ id: UUID) {
        guard enabled, peripheral == nil, let p = peripherals[id] else { return }
        peripheral = p; p.delegate = self; central.stopScan()
        deadline = Date().addingTimeInterval(60)
        onStatus("Connecting to \(p.name ?? "Flipper") — confirm pairing on both devices")
        central.connect(p)
    }
    private func scan() {
        guard enabled, central.state == .poweredOn, peripheral == nil else { return }
        onStatus("Looking for PCHealth devices…")
        // Flipper advertises a short service ID, so filter by advertised name after discovery.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    private func clear() {
        peripheral = nil; rx = nil; ready = false; parser = HelloParser()
        pending = Data(); awaitingWrite = false; lastHello = .distantPast; nextSend = .distantPast
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard enabled else { return }
        switch central.state {
        case .poweredOn: scan()
        case .unauthorized: onStatus("Allow Bluetooth in System Settings → Privacy & Security → Bluetooth")
        case .poweredOff: onStatus("Turn on Bluetooth in System Settings")
        case .unsupported: onStatus("Bluetooth LE is unavailable on this Mac")
        default: onStatus("Bluetooth is starting…")
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard enabled else { return }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? p.name ?? ""
        guard name.hasPrefix("PCHealth") else { return }
        peripherals[p.identifier] = p
        devices[p.identifier] = Device(id: p.identifier, name: name, rssi: RSSI.intValue)
        onDevices(devices.values.sorted { $0.rssi > $1.rssi })
        if p.identifier == savedID && peripheral == nil { connect(p.identifier) }
    }
    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        guard enabled, peripheral === p else { central.cancelPeripheralConnection(p); return }
        p.discoverServices([Self.service])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        disconnected(p, error)
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        disconnected(p, error)
    }
    private func disconnected(_ p: CBPeripheral, _ error: Error?) {
        guard peripheral === p else { return }
        clear(); onStatus(error?.localizedDescription ?? "Bluetooth disconnected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.scan() }
    }
    private func fail(_ message: String) {
        onStatus(message)
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === p else { return }
        guard error == nil, let service = p.services?.first(where: { $0.uuid == Self.service }) else {
            fail(error?.localizedDescription ?? "Flipper serial service missing"); return
        }
        p.discoverCharacteristics([Self.rxID, Self.txID], for: service)
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === p else { return }
        guard error == nil, let rx = service.characteristics?.first(where: { $0.uuid == Self.rxID }),
              let tx = service.characteristics?.first(where: { $0.uuid == Self.txID }) else {
            fail(error?.localizedDescription ?? "Flipper serial characteristics missing"); return
        }
        self.rx = rx; p.setNotifyValue(true, for: tx)
    }
    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === p else { return }
        if let error { fail("Pairing/subscription failed: \(error.localizedDescription)") }
        else { onStatus("Bluetooth: waiting for HELLO — confirm any pairing request") }
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === p, characteristic.uuid == Self.txID else { return }
        if let error { fail(error.localizedDescription); return }
        guard let data = characteristic.value else { return }
        for seconds in parser.feed(data, transport: 0) {
            interval = Double(seconds); lastHello = Date()
            if !ready {
                ready = true; savedID = p.identifier
                onStatus("Connected over Bluetooth · \(p.name ?? "Flipper")")
            }
        }
    }
    private func tick() {
        if peripheral != nil && !ready && Date() > deadline { fail("Bluetooth handshake timed out"); return }
        guard ready else { return }
        if Date().timeIntervalSince(lastHello) > 30 { fail("Bluetooth HELLO timed out"); return }
        if pending.isEmpty && !awaitingWrite && Date() >= nextSend {
            pending = frame(); nextSend = Date().addingTimeInterval(interval)
        }
        drain()
    }
    private func drain() {
        guard let p = peripheral, let rx, !awaitingWrite, !pending.isEmpty else { return }
        let type: CBCharacteristicWriteType = rx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        while !pending.isEmpty {
            if type == .withoutResponse && !p.canSendWriteWithoutResponse { return }
            let size = p.maximumWriteValueLength(for: type)
            guard size > 0 else { fail("Bluetooth write size unavailable"); return }
            let chunk = Data(pending.prefix(size)); pending.removeFirst(chunk.count)
            if type == .withResponse { awaitingWrite = true }
            p.writeValue(chunk, for: rx, type: type)
            if type == .withResponse { return }
        }
        onSent()
    }
    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) { if peripheral === p { drain() } }
    func peripheral(_ p: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === p else { return }
        awaitingWrite = false
        if let error { fail(error.localizedDescription) }
        else if pending.isEmpty { onSent() } else { drain() }
    }
}

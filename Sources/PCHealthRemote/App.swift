import SwiftUI
import AppKit
import ServiceManagement

final class AppModel: ObservableObject {
    @Published var metrics = Metrics()
    @Published var cpuHistory: [Double] = []
    @Published var gpuHistory: [Double] = []
    @Published var status = "Ready to connect"
    @Published var devices: [BluetoothLink.Device] = []
    @Published var running = false
    @Published var sent = 0
    @Published var lastSent: Date?
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?
    @Published var mode: String = UserDefaults.standard.string(forKey: "transport") ?? "Bluetooth" {
        didSet { UserDefaults.standard.set(mode, forKey: "transport"); if running { stop(); start() } }
    }
    let bluetooth = BluetoothLink()
    let usb = USBLink()
    private let collector = MetricsCollector()
    private let metricsQueue = DispatchQueue(label: "health.metrics", qos: .utility)
    private var timer: Timer?
    private var sampling = false
    private var sequence: UInt8 = 0

    init() {
        bluetooth.onStatus = { [weak self] in self?.status = $0 }
        usb.onStatus = { [weak self] in self?.status = $0 }
        bluetooth.onDevices = { [weak self] in self?.devices = $0 }
        bluetooth.frame = { [weak self] in self?.packet() ?? Data() }
        usb.frame = { [weak self] in self?.packet() ?? Data() }
        bluetooth.onSent = { [weak self] in self?.didSend() }
        usb.onSent = { [weak self] in self?.didSend() }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
        // Start USB immediately when it was selected previously. Bluetooth waits for Connect
        // on a fresh installation so the first permission prompt has context.
        if UserDefaults.standard.bool(forKey: "hasConnected") { start() }
    }
    private func sample() {
        guard !sampling else { return }; sampling = true
        metricsQueue.async { [self] in
            let m = collector.sample()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.metrics = m
                self.cpuHistory = Array((self.cpuHistory + [Double(m.cpu)]).suffix(60))
                self.gpuHistory = Array((self.gpuHistory + [Double(m.gpu ?? 0)]).suffix(60))
                self.sampling = false
            }
        }
    }
    private func packet() -> Data {
        defer { sequence &+= 1 }
        return Wire.telemetry(metrics, sequence: sequence)
    }
    private func didSend() { sent += 1; lastSent = Date() }
    func start() {
        guard !running else { return }
        running = true; sent = 0; lastSent = nil
        UserDefaults.standard.set(true, forKey: "hasConnected")
        if mode == "USB" { usb.start() } else { bluetooth.start() }
    }
    func stop() {
        running = false; bluetooth.stop(); usb.stop(); status = "Disconnected"; lastSent = nil
        UserDefaults.standard.set(false, forKey: "hasConnected")
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginError = SMAppService.mainApp.status == .requiresApproval ? "Approve PC Health Remote in System Settings → General → Login Items." : nil
        } catch { loginError = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
    }
    var isSending: Bool { lastSent.map { Date().timeIntervalSince($0) < 12 } ?? false }
}

final class DesktopAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: url) else { return }
        // Set the running Dock icon as well as the Finder bundle icon. Launch
        // Services can retain an old icon when local builds replace the bundle.
        NSApp.applicationIconImage = icon
    }
}

@main
struct PCHealthRemoteApp: App {
    @NSApplicationDelegateAdaptor(DesktopAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("PC Health Remote", id: "dashboard") {
            Dashboard(model: model)
                .preferredColorScheme(.dark)
        }.windowResizability(.contentSize).windowStyle(.hiddenTitleBar)
        MenuBarExtra("PC Health Remote", systemImage: "waveform.path.ecg") {
            MenuContent(model: model)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("CPU \(model.metrics.cpu)% · RAM \(model.metrics.ram)%")
        Text(model.status)
        Divider()
        Button("Show dashboard") { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }
        Button(model.running ? "Disconnect" : "Connect") { if model.running { model.stop() } else { model.start() } }
        Divider()
        Button("Quit PC Health Remote") { model.stop(); NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

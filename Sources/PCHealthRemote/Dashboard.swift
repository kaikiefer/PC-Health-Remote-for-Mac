import SwiftUI
import AppKit

private enum HUD {
    static let logo = Bundle.main.url(forResource: "LogoMark", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    static let background = Color(red: 0.025, green: 0.043, blue: 0.065)
    static let panel = Color(red: 0.045, green: 0.075, blue: 0.103)
    static let cyan = Color(red: 0.23, green: 0.87, blue: 0.96)
    static let orange = Color(red: 1, green: 0.49, blue: 0.18)
    static let muted = Color(red: 0.48, green: 0.62, blue: 0.69)
    static let white = Color(red: 0.86, green: 0.94, blue: 0.96)
    static let green = Color(red: 0.40, green: 0.94, blue: 0.69)
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

private struct HUDPanel: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16)
            .background(HUD.panel.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(HUD.cyan.opacity(0.14)))
    }
}

private struct Trace: Shape {
    let samples: [Double]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard samples.count > 1 else { return path }
        for (i, value) in samples.enumerated() {
            let point = CGPoint(x: rect.width * CGFloat(i) / CGFloat(max(59, samples.count - 1)),
                                y: rect.height * (1 - CGFloat(max(0, min(100, value))) / 100))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

private struct LoadTrace: View {
    let samples: [Double]
    let color: Color
    var body: some View {
        ZStack {
            Canvas { context, size in
                var grid = Path()
                for i in 0...3 {
                    let y = size.height * CGFloat(i) / 3
                    grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(HUD.cyan.opacity(0.10)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
            }
            Trace(samples: samples).stroke(color.opacity(0.16), lineWidth: 7).blur(radius: 4)
            Trace(samples: samples).stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }.frame(height: 46).accessibilityLabel("Last 60 seconds of usage")
    }
}

private struct SegmentedMeter: View {
    let value: Int
    let color: Color
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 3) {
                ForEach(0..<24, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Double(i) < Double(value) / 100 * 24 ? color : color.opacity(0.10))
                }
            }.frame(width: geometry.size.width)
        }.frame(height: 6)
    }
}

private struct Reactor: View {
    let connected: Bool
    let frameCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [HUD.cyan.opacity(0.13), HUD.cyan.opacity(0.015), .clear], center: .center, startRadius: 10, endRadius: 135))
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<72 {
                    let angle = Double(i) * .pi / 36
                    let outer: CGFloat = 111, inner: CGFloat = i % 6 == 0 ? 101 : 107
                    var line = Path()
                    line.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                    line.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                    context.stroke(line, with: .color(HUD.cyan.opacity(i % 6 == 0 ? 0.65 : 0.22)), lineWidth: 1)
                }
            }
            Circle().stroke(HUD.cyan.opacity(0.15), lineWidth: 1).frame(width: 191, height: 191)
            Circle().trim(from: 0.04, to: 0.31).stroke(HUD.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .square))
                .rotationEffect(.degrees(-90)).frame(width: 191, height: 191)
            Circle().trim(from: 0.38, to: 0.72).stroke(HUD.cyan.opacity(0.5), lineWidth: 3)
                .rotationEffect(.degrees(-90)).frame(width: 191, height: 191)
            Circle().trim(from: 0.78, to: 0.96).stroke(HUD.orange, lineWidth: 3)
                .rotationEffect(.degrees(-90)).frame(width: 191, height: 191)
            Circle().stroke(HUD.cyan.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2, 7])).frame(width: 169, height: 169)
            Circle().stroke(HUD.cyan.opacity(0.09), lineWidth: 12).frame(width: 148, height: 148)
            VStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 28, weight: .light)).foregroundStyle(HUD.orange)
                    .shadow(color: HUD.orange.opacity(0.5), radius: 10)
                Text(connected ? "LINK ACTIVE" : "STANDBY")
                    .font(HUD.mono(15, .bold)).tracking(2).foregroundStyle(connected ? HUD.cyan : HUD.muted)
                Text(connected ? String(format: "%06d FRAMES", frameCount) : "AWAITING FLIPPER")
                    .font(HUD.mono(9)).tracking(1).foregroundStyle(HUD.muted).monospacedDigit()
            }
        }.frame(width: 256, height: 224)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: connected)
    }
}

struct Dashboard: View {
    @ObservedObject var model: AppModel
    @AppStorage("displayFahrenheit") private var displayFahrenheit = false

    private func temperature(_ celsius: Int?) -> String {
        guard let celsius else { return "—" }
        let value = displayFahrenheit ? Int((Double(celsius) * 9 / 5 + 32).rounded()) : celsius
        return "\(value)°\(displayFahrenheit ? "F" : "C")"
    }
    private func label(_ text: String, color: Color = HUD.muted) -> some View {
        Text(text).font(HUD.mono(10)).tracking(1.7).foregroundStyle(color)
    }
    private var background: some View {
        ZStack {
            HUD.background
            RadialGradient(colors: [HUD.cyan.opacity(0.055), .clear], center: .top, startRadius: 0, endRadius: 580)
            Canvas { context, size in
                var grid = Path()
                for x in stride(from: 0.0, to: size.width, by: 32) {
                    grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: 0.0, to: size.height, by: 32) {
                    grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(HUD.cyan.opacity(0.025)), lineWidth: 0.5)
            }.accessibilityHidden(true)
        }.ignoresSafeArea()
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if let image = HUD.logo {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 28)).foregroundStyle(HUD.orange)
                }
            }.frame(width: 54, height: 54)
                .accessibilityLabel("PC Health Remote logo")
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 0) {
                    Text("PC HEALTH").foregroundStyle(HUD.orange)
                    Text(" / REMOTE").foregroundStyle(HUD.white)
                }.font(HUD.mono(22, .bold)).tracking(2)
                label("FLIPPER COMPANION   //   SYSTEM TELEMETRY")
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(model.isSending ? HUD.green : HUD.muted).frame(width: 5, height: 5)
                    label(model.isSending ? "TELEMETRY ONLINE" : "LOCAL MONITOR", color: model.isSending ? HUD.green : HUD.muted)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
                        .font(HUD.mono(13)).foregroundStyle(HUD.muted).monospacedDigit()
                }
            }
        }
    }

    private func processor(_ name: String, code: String, value: Int?, temp: Int?, history: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                label(code, color: color)
                Spacer()
                Image(systemName: name == "CPU" ? "cpu" : "square.stack.3d.up").font(.system(size: 16)).foregroundStyle(color.opacity(0.8))
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.map(String.init) ?? "—").font(HUD.mono(47, .light)).foregroundStyle(HUD.white).monospacedDigit()
                Text("%").font(HUD.mono(17)).foregroundStyle(color)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(temperature(temp)).font(HUD.mono(19)).foregroundStyle(color).monospacedDigit()
                    label("THERMAL", color: HUD.muted)
                }
            }
            LoadTrace(samples: history, color: color)
            HStack { label("\(name) LOAD"); Spacer(); label("60s TRACE") }
        }.modifier(HUDPanel()).frame(maxWidth: .infinity)
    }
    private func metric(_ title: String, value: String, detail: String, percent: Int?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label(title)
            Text(value).font(HUD.mono(25, .light)).foregroundStyle(HUD.white).monospacedDigit()
            SegmentedMeter(value: percent ?? 0, color: color)
            Text(detail).font(HUD.mono(10)).foregroundStyle(HUD.muted).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading).modifier(HUDPanel())
    }

    private var unitPicker: some View {
        HStack(spacing: 1) {
            ForEach([false, true], id: \.self) { fahrenheit in
                Button { displayFahrenheit = fahrenheit } label: {
                    Text(fahrenheit ? "°F" : "°C").font(HUD.mono(11, .bold))
                        .foregroundStyle(displayFahrenheit == fahrenheit ? HUD.background : HUD.muted)
                        .frame(width: 36, height: 25)
                        .background(displayFahrenheit == fahrenheit ? HUD.cyan : .clear, in: RoundedRectangle(cornerRadius: 4))
                }.buttonStyle(.plain).accessibilityLabel(fahrenheit ? "Fahrenheit" : "Celsius")
                    .accessibilityAddTraits(displayFahrenheit == fahrenheit ? .isSelected : [])
            }
        }.padding(3).background(HUD.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .help("Dashboard temperature units. Flipper telemetry stays in Celsius.")
    }

    private var transportPicker: some View {
        HStack(spacing: 4) {
            ForEach(["USB", "Bluetooth"], id: \.self) { transport in
                Button { model.mode = transport } label: {
                    HStack(spacing: 5) {
                        Image(systemName: transport == "USB" ? "cable.connector" : "antenna.radiowaves.left.and.right")
                        Text(transport == "USB" ? "USB" : "BLE")
                    }.font(HUD.mono(11, .bold)).foregroundStyle(model.mode == transport ? HUD.cyan : HUD.muted)
                        .padding(.horizontal, 11).padding(.vertical, 9)
                        .background(model.mode == transport ? HUD.cyan.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain).accessibilityLabel(transport)
                    .accessibilityAddTraits(model.mode == transport ? .isSelected : [])
            }
        }.padding(3).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(HUD.cyan.opacity(0.15)))
    }
    private var connection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                Rectangle().fill(model.isSending ? HUD.green : HUD.orange).frame(width: 3, height: 41)
                VStack(alignment: .leading, spacing: 7) {
                    label("FLIPPER UPLINK", color: HUD.cyan)
                    Text(model.status).font(HUD.mono(11)).foregroundStyle(HUD.white)
                        .lineLimit(2).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading)
                transportPicker
                Button { if model.running { model.stop() } else { model.start() } } label: {
                    HStack(spacing: 7) {
                        Image(systemName: model.running ? "stop.circle" : "power")
                        Text(model.running ? "DISCONNECT" : "CONNECT")
                    }.font(HUD.mono(11, .bold)).foregroundStyle(HUD.background)
                        .frame(width: 132, height: 39).background(HUD.orange, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)
            }
            if model.mode == "Bluetooth" && model.running && !model.bluetooth.ready {
                ForEach(model.devices) { device in
                    HStack {
                        Text(device.name).font(HUD.mono(12)).foregroundStyle(HUD.white)
                        Spacer()
                        label("\(device.rssi) dBm")
                        Button("Use this Flipper") { model.bluetooth.connect(device.id) }.tint(HUD.cyan)
                    }
                }
                Text("Open PC Health Remote on Flipper. Compare and confirm any pairing code on both devices.")
                    .font(HUD.mono(10)).foregroundStyle(HUD.muted)
            }
        }.modifier(HUDPanel())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Rectangle().fill(LinearGradient(colors: [HUD.orange.opacity(0.75), HUD.cyan.opacity(0.2), .clear], startPoint: .leading, endPoint: .trailing)).frame(height: 1)
                HStack(spacing: 15) {
                    label("01 / LIVE SYSTEMS", color: HUD.cyan)
                    Spacer()
                    label("TEMP DISPLAY")
                    unitPicker
                }
                HStack(spacing: 8) {
                    processor("CPU", code: "COMPUTE // CPU", value: model.metrics.cpu, temp: model.metrics.cpuTemperature, history: model.cpuHistory, color: HUD.cyan)
                    Reactor(connected: model.isSending, frameCount: model.sent)
                    processor("GPU", code: "GRAPHICS // GPU", value: model.metrics.gpu, temp: model.metrics.gpuTemperature, history: model.gpuHistory, color: HUD.orange)
                }
                HStack(spacing: 12) {
                    metric("UNIFIED MEMORY", value: "\(model.metrics.ram)%", detail: String(format: "%.1f GB PHYSICAL", model.metrics.ramGB), percent: model.metrics.ram, color: HUD.cyan)
                    metric("GPU SHARED / VRAM", value: model.metrics.vramGB > 0 ? "\(model.metrics.vram)%" : "—", detail: String(format: "%.1f / %.1f GB SHARED", model.metrics.gpuMemoryGB, model.metrics.vramGB), percent: model.metrics.vram, color: HUD.orange)
                    metric("STORAGE USED", value: "\(model.metrics.disk)%", detail: "STARTUP DATA VOLUME", percent: model.metrics.disk, color: HUD.cyan)
                    metric("POWER CELL", value: model.metrics.battery.map { "\($0)%" } ?? "AC", detail: model.metrics.battery == nil ? "NO INTERNAL BATTERY" : model.metrics.charging ? "CHARGING" : model.metrics.onBattery ? "ON BATTERY" : "EXTERNAL POWER", percent: model.metrics.battery, color: HUD.green)
                }
                HStack(spacing: 0) {
                    detail("CPU CLOCK", model.metrics.cpuMHz > 0 ? String(format: "%.2f GHz", Double(model.metrics.cpuMHz) / 1000) : "SAMPLING")
                    detail("FAN", model.metrics.fanRPM.map { "\($0) RPM" } ?? "NO SENSOR")
                    detail("UPTIME", "\(model.metrics.uptimeHours) HOURS")
                    detail("TOP CPU PROCESS", model.metrics.topCPU.isEmpty ? "READING…" : model.metrics.topCPU)
                    detail("TOP RAM PROCESS", model.metrics.topRAM.isEmpty ? "READING…" : model.metrics.topRAM)
                }.padding(.vertical, 14).padding(.horizontal, 18)
                    .background(HUD.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                connection
                footer
            }.padding(24)
        }.frame(width: 1000, height: 850).background(background).foregroundStyle(HUD.white)
            .tint(HUD.cyan)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(HUD.mono(9)).tracking(0.8).foregroundStyle(HUD.muted)
            Text(value).font(HUD.mono(11)).foregroundStyle(HUD.white).lineLimit(1).truncationMode(.middle)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("Open at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                    .toggleStyle(.checkbox).font(HUD.mono(10)).foregroundStyle(HUD.muted)
                if model.mode == "Bluetooth" {
                    Button("Forget Flipper") { model.bluetooth.forget() }.buttonStyle(.plain).font(HUD.mono(10)).foregroundStyle(HUD.orange)
                }
                Spacer()
                label("LOCAL METRICS  /  DIRECT TO DEVICE", color: HUD.cyan.opacity(0.65))
            }
            if let error = model.loginError { Text(error).font(HUD.mono(10)).foregroundStyle(HUD.orange) }
            Text("VRAM shares system memory. Clock averages active cores. Fanless Macs have no RPM. Close this window to keep the menu bar monitor running.")
                .font(HUD.mono(9)).foregroundStyle(HUD.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

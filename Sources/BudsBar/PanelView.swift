import AppKit
import BudsKit
import CoreAudio
import SwiftUI

/// The panel under the menu-bar icon.
struct PanelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            header
            if model.bluetoothDenied {
                notice("Bluetooth access is off", "BudsBar needs it to read the earbuds.",
                       button: "Open Privacy settings", action: openPrivacy)
            } else if model.name != nil {
                batteries
                if model.isStuck {
                    notice("Battery levels unavailable",
                           "Another app left its connection to the earbuds open. Disconnect and reconnect them in Bluetooth once.")
                }
                if model.isLinked { noiseControl }
            }
            audio
            restore
            footer
        }
        .padding(12)
        .frame(width: 320)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 10) {
            EarbudsGlyph(body: model.name == nil ? Color.secondary : Color.white,
                         tips: model.name == nil ? Color.primary.opacity(0.25) : Color.accentColor.opacity(0.8))
                .frame(width: 22, height: 22)
                .frame(width: 34, height: 34)
                .background(Circle().fill(model.name == nil ? Color.primary.opacity(0.08) : Color.accentColor))
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name ?? "No Galaxy Buds").font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private var subtitle: String {
        guard model.name != nil else { return "Connect them in Bluetooth settings" }
        guard model.isLinked else { return model.isStuck ? "Connected · audio only" : "Connecting…" }
        switch model.status.isWorn {
        case true?: return "Connected · in your ears"
        case false?: return "Connected · not worn"
        case nil: return "Connected"
        }
    }

    // MARK: batteries

    private var batteries: some View {
        HStack(spacing: 0) {
            BatteryGauge(symbol: "earbud.left", title: "Left", level: model.status.left,
                         placement: model.status.placementLeft)
            BatteryGauge(symbol: "earbud.right", title: "Right", level: model.status.right,
                         placement: model.status.placementRight)
            BatteryGauge(symbol: "earbuds.case", title: "Case", level: model.status.caseLevel, placement: nil)
        }
        .padding(.vertical, 12)
        .card()
    }

    // MARK: noise control

    private var noiseControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Noise control").sectionTitle()
            HStack(spacing: 6) {
                ForEach(NoiseControl.allCases, id: \.rawValue) { mode in
                    NoiseButton(mode: mode, isOn: model.status.noiseControl == mode) {
                        model.setNoiseControl(mode)
                    }
                }
            }
        }
        .padding(10)
        .card()
    }

    // MARK: audio devices

    private var audio: some View {
        VStack(spacing: 0) {
            DeviceRow(symbol: "speaker.wave.2.fill", title: "Output", devices: model.outputs,
                      selected: model.outputID) { model.select($0, .output) }
            Divider().padding(.leading, 38)
            DeviceRow(symbol: "mic.fill", title: "Microphone", devices: model.inputs,
                      selected: model.inputID) { model.select($0, .input) }
        }
        .card()
    }

    // MARK: restore sound

    private var restore: some View {
        VStack(spacing: 0) {
            SwitchRow(symbol: "arrow.triangle.2.circlepath", title: "Restore sound",
                      caption: restoreCaption, isOn: $model.recoveryEnabled)
            Divider().padding(.leading, 38)
            SwitchRow(symbol: "play.fill", title: "Resume playback",
                      caption: "If taking them out paused it", isOn: $model.resumeEnabled)
        }
        .card()
    }

    private var restoreCaption: String {
        guard let last = model.lastRecovery else { return "When you put the earbuds back in" }
        return "Last restored at " + DateFormatter.localizedString(from: last, dateStyle: .none, timeStyle: .short)
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            Menu {
                Picker("Menu bar shows", selection: $model.barStyle) {
                    ForEach(AppModel.BarStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Launch at login", isOn: Binding(get: { model.launchesAtLogin },
                                                        set: { model.setLaunchAtLogin($0) }))
                Button("Show log") { NSWorkspace.shared.open(Log.url) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    // MARK: pieces

    private func notice(_ title: String, _ text: String, button: String? = nil,
                        action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let button, let action {
                    Button(button, action: action).controlSize(.small).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .card()
    }

    private func openPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The app icon's pair of earbuds (see scripts/make-icon.swift), so the panel and the icon match.
private struct EarbudsGlyph: View {
    let body_: Color
    let tips: Color

    init(body: Color, tips: Color) {
        body_ = body
        self.tips = tips
    }

    /// The drawing lives in a 464-point square: heads at the top, stems hanging from their inner
    /// halves, a tinted ear tip on the outer side of each head.
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 464
            context.translateBy(x: (size.width - 464 * scale) / 2, y: (size.height - 464 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            for side in [-1.0, 1.0] {
                let x = 232 + side * 128
                var bud = Path(ellipseIn: CGRect(x: x - 104, y: 26, width: 208, height: 208))
                bud.addRoundedRect(in: CGRect(x: x - side * 34 - 40, y: 108, width: 80, height: 330),
                                   cornerSize: CGSize(width: 40, height: 40))
                context.fill(bud, with: .color(body_))
                var tip = context
                tip.translateBy(x: x + side * 50, y: 126)
                tip.rotate(by: .radians(-side * 0.12))
                tip.fill(Path(ellipseIn: CGRect(x: -34, y: -58, width: 68, height: 116)), with: .color(tips))
            }
        }
    }
}

/// A ring that fills with the charge, the part's icon in the middle.
private struct BatteryGauge: View {
    let symbol: String
    let title: String
    let level: Int?
    let placement: Placement?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.10), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(level ?? 0) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: level)
                Image(systemName: symbol)
                    .font(.system(size: 21))
                    .foregroundStyle(level == nil ? Color.secondary : Color.primary)
            }
            .frame(width: 56, height: 56)
            Text(level.map { "\($0)%" } ?? "–")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
            VStack(spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 2) {
                    if placement?.isInCase == true {
                        Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundStyle(.green)
                    }
                    Text(caption).font(.caption2).foregroundStyle(captionColor)
                }
                .frame(height: 12)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var color: Color {
        guard let level else { return .clear }
        return level <= 15 ? .red : level <= 35 ? .orange : .green
    }

    private var caption: String {
        switch placement {
        case .wearing?: return "In ear"
        case .notWearing?: return "Out"
        case .inCase?, .inClosedCase?: return "Charging"
        case .unknown?, nil: return ""
        }
    }

    private var captionColor: Color {
        placement == .wearing ? Color.accentColor : Color.secondary
    }
}

private struct NoiseButton: View {
    let mode: NoiseControl
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 16, weight: .medium)).frame(height: 18)
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isOn ? Color.accentColor : Color.primary.opacity(hovering ? 0.12 : 0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var symbol: String {
        switch mode {
        case .off: return "circle.slash"
        case .noiseCancelling: return "ear.badge.waveform"
        case .ambient: return "person.wave.2"
        }
    }

    private var label: String {
        switch mode {
        case .off: return "Off"
        case .noiseCancelling: return "ANC"
        case .ambient: return "Ambient"
        }
    }
}

private struct SwitchRow: View {
    let symbol: String
    let title: String
    let caption: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13))
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Toggle("", isOn: $isOn).toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct DeviceRow: View {
    let symbol: String
    let title: String
    let devices: [AudioDevices.Device]
    let selected: AudioDeviceID
    let pick: (AudioDeviceID) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title).font(.system(size: 13))
            Spacer(minLength: 8)
            Menu {
                ForEach(devices, id: \.id) { device in
                    Button {
                        pick(device.id)
                    } label: {
                        if device.id == selected {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            } label: {
                Text(devices.first { $0.id == selected }?.name ?? "—")
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(maxWidth: 170, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private extension View {
    func card() -> some View {
        background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

private extension Text {
    func sectionTitle() -> some View {
        font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }
}

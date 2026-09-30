import AppKit
import BudsKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let link = BudsLink()
    private let recovery = CallLinkRecovery { Log.write($0) }
    private let resume = PlaybackResume { Log.write($0) }
    private var bluetoothLog: BluetoothLog?
    private var status: StatusController?
    private var observer: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel(link: link, recovery: recovery, resume: resume)
        let status = StatusController(model: model)
        self.status = status
        // The menu-bar text depends on a setting as well as on the earbuds.
        observer = model.$barStyle.sink { _ in DispatchQueue.main.async { status.refresh() } }
        let bluetoothLog = BluetoothLog { [recovery, resume] line in
            recovery.logLine(line)
            resume.logLine(line)
        }
        self.bluetoothLog = bluetoothLog
        bluetoothLog.start()
        link.onChange = { [unowned self] in
            model.syncLink()
            status.refresh()
            self.recovery.setDevice(address: self.link.peer?.address)
            self.recovery.setWorn(self.link.isLinked ? self.link.status.isWorn : nil)
            self.resume.setDevice(address: self.link.peer?.address)
            self.resume.setWornCount(self.link.isLinked ? self.link.status.wornCount : nil)
        }
        Log.write("BudsBar started")
        link.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        link.stop()
        bluetoothLog?.stop()
    }
}

// `BudsBar --icon icon.png` writes the 1024-pixel app icon, `--glyph glyph.png` the menu-bar
// drawing enlarged on grey: see scripts/make-icon.sh.
if let flag = CommandLine.arguments.firstIndex(of: "--icon"), CommandLine.arguments.count > flag + 1 {
    let data = Artwork.appIcon()?.representation(using: .png, properties: [:])
    try? data?.write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
    exit(data == nil ? 1 : 0)
}
if let flag = CommandLine.arguments.firstIndex(of: "--glyph"), CommandLine.arguments.count > flag + 1 {
    let side: CGFloat = 288
    let preview = NSImage(size: NSSize(width: side * 2, height: side), flipped: true) { rect in
        NSColor(white: 0.2, alpha: 1).setFill()
        rect.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        Artwork.draw(in: context, rect: CGRect(x: 0, y: 0, width: side, height: side),
                     body: NSColor.white.cgColor, tip: NSColor.white.cgColor, gap: 5)
        context.endTransparencyLayer()
        // The same drawing at the size of the menu bar, twice over for a Retina screen.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        Artwork.draw(in: context, rect: CGRect(x: side + 60, y: 120, width: 36, height: 36),
                     body: NSColor.white.cgColor, tip: NSColor.white.cgColor, gap: 5)
        context.endTransparencyLayer()
        return true
    }
    let data = preview.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?
        .representation(using: .png, properties: [:])
    try? data?.write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
    exit(0)
}

// `BudsBar --snapshot panel.png [dark|light]` draws the panel with sample data into a PNG: the
// way to look at a design change (and to make the README screenshot) without earbuds.
if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > flag + 1 {
    let dark = !CommandLine.arguments.contains("light")
    let model = AppModel(link: BudsLink(), recovery: CallLinkRecovery { _ in },
                         resume: PlaybackResume { _ in })
    model.loadSample()
    let host = NSHostingView(rootView: PanelView(model: model)
        .background(dark ? Color(white: 0.16) : Color(white: 0.93))
        .ignoresSafeArea()
        .environment(\.colorScheme, dark ? .dark : .light))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.wantsLayer = true
    host.layer?.backgroundColor = NSColor(white: dark ? 0.16 : 0.93, alpha: 1).cgColor
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let url = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
    try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    exit(0)
}

// A second copy would fight the first one for the earbuds' single control channel.
let bundleID = Bundle.main.bundleIdentifier ?? ""
if !bundleID.isEmpty, NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
    exit(0)
}

// `kill` and logout send SIGTERM: leave through the normal path so the channel gets closed.
signal(SIGTERM, SIG_IGN)
let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigterm.setEventHandler { NSApplication.shared.terminate(nil) }
sigterm.resume()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

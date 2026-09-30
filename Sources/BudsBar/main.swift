import AppKit
import BudsKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let link = BudsLink()
    private let recovery = CallLinkRecovery { Log.write($0) }
    private var status: StatusController?
    private var observer: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel(link: link, recovery: recovery)
        let status = StatusController(model: model)
        self.status = status
        // The menu-bar text depends on a setting as well as on the earbuds.
        observer = model.$barStyle.sink { _ in DispatchQueue.main.async { status.refresh() } }
        recovery.start()
        link.onChange = { [unowned self] in
            model.syncLink()
            status.refresh()
            self.recovery.setDevice(address: self.link.peer?.address)
            self.recovery.setWorn(self.link.isLinked ? self.link.status.isWorn : nil)
        }
        Log.write("BudsBar started")
        link.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        link.stop()
        recovery.stop()
    }
}

// `BudsBar --snapshot panel.png [dark|light]` draws the panel with sample data into a PNG: the
// way to look at a design change (and to make the README screenshot) without earbuds.
if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > flag + 1 {
    let dark = !CommandLine.arguments.contains("light")
    let model = AppModel(link: BudsLink(), recovery: CallLinkRecovery { _ in })
    model.loadSample()
    let host = NSHostingView(rootView: PanelView(model: model)
        .background(dark ? Color(white: 0.16) : Color(white: 0.93))
        .ignoresSafeArea()
        .environment(\.colorScheme, dark ? .dark : .light))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
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

import AppKit
import SwiftUI

/// The menu-bar item (earbuds icon + battery levels) and the panel it opens.
final class StatusController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: PanelView(model: model))
        // The panel grows and shrinks with what the earbuds report; without this the popover
        // keeps its first size and cuts the top off.
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        if let button = item.button {
            let symbol = NSImage(systemSymbolName: "earbuds", accessibilityDescription: "Earbuds")
            symbol?.isTemplate = true
            button.image = symbol
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(toggle)
        }
        refresh()
    }

    /// Redraws the menu-bar item from the model.
    func refresh() {
        guard let button = item.button else { return }
        button.appearsDisabled = model.name == nil
        let levels = model.barLevels
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small) + 1, weight: .regular)
        let title = NSMutableAttributedString(string: levels.earbuds.map { " \($0)%" } ?? "", attributes: [.font: font])
        if let caseLevel = levels.caseLevel {
            // The case gets its own small icon, so the two numbers cannot be mistaken.
            let icon = NSTextAttachment()
            icon.image = NSImage(systemSymbolName: "earbuds.case", accessibilityDescription: "Case")?
                .withSymbolConfiguration(.init(pointSize: font.pointSize, weight: .regular))
            title.append(NSAttributedString(string: "  ", attributes: [.font: font]))
            title.append(NSAttributedString(attachment: icon))
            title.append(NSAttributedString(string: " \(caseLevel)%", attributes: [.font: font]))
        }
        button.attributedTitle = title
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = item.button else { return }
        model.syncSystem()
        if let view = popover.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            popover.contentSize = view.fittingSize
        }
        // A menu-bar app is never active on its own; without this a click elsewhere would not
        // dismiss the panel.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

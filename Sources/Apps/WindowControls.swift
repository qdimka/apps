import AppKit
import SwiftUI

// Keep window actions reachable when macOS screen-sharing chrome covers the
// titlebar controls. Resolve the owning window from the clicked native button.
struct WindowControls: NSViewRepresentable {
    func makeCoordinator() -> Actions { Actions() }

    func makeNSView(context: Context) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        let buttons: [(String, String, NSColor, Selector)] = [
            ("xmark.circle.fill", "Закрыть окно", .systemRed, #selector(Actions.close(_:))),
            ("minus.circle.fill", "Свернуть окно", .systemYellow, #selector(Actions.minimize(_:))),
            ("plus.circle.fill", "Развернуть окно", .systemGreen, #selector(Actions.zoom(_:)))
        ]
        for (symbol, label, color, action) in buttons {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)!
            let button = NSButton(image: image, target: context.coordinator, action: action)
            button.symbolConfiguration = .init(pointSize: 15, weight: .regular)
            button.isBordered = false
            button.contentTintColor = color
            button.toolTip = label
            button.setAccessibilityLabel(label)
            stack.addArrangedSubview(button)
        }
        return stack
    }

    func updateNSView(_ view: NSStackView, context: Context) {}

    @MainActor final class Actions: NSObject {
        @objc func close(_ sender: NSButton) { sender.window?.performClose(sender) }
        @objc func minimize(_ sender: NSButton) { sender.window?.miniaturize(sender) }
        @objc func zoom(_ sender: NSButton) { sender.window?.zoom(sender) }
    }
}

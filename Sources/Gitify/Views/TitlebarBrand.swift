import SwiftUI
import AppKit

/// Pins a static "Gitify" wordmark into the window titlebar, immediately to the right of
/// the traffic-light buttons, using an AppKit leading titlebar accessory. SwiftUI's
/// `NavigationSplitView` title handling can't place a static label there cleanly, so we
/// reach the `NSWindow` directly once the host view is attached to a window.
struct TitlebarBrand: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { BrandProbeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private static let identifier = NSUserInterfaceItemIdentifier("gitify-brand")

    static func install(in window: NSWindow) {
        guard !window.titlebarAccessoryViewControllers.contains(where: { $0.identifier == identifier })
        else { return }

        let label = NSTextField(labelWithString: "Gitify")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.sizeToFit()

        let height: CGFloat = 28
        let container = NSView(frame: NSRect(x: 0, y: 0, width: label.frame.width + 14, height: height))
        label.frame.origin = NSPoint(x: 8, y: (height - label.frame.height) / 2)
        label.autoresizingMask = [.minYMargin, .maxYMargin]
        container.addSubview(label)

        let accessory = NSTitlebarAccessoryViewController()
        accessory.identifier = identifier
        accessory.layoutAttribute = .leading
        accessory.view = container
        window.addTitlebarAccessoryViewController(accessory)
    }
}

/// Installs the brand once it's attached to a window (reliable timing vs. probing in
/// `makeNSView`, where the window is often still nil).
private final class BrandProbeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { TitlebarBrand.install(in: window) }
    }
}

import AppKit

/// Lightweight native prompts built on `NSAlert`, used for quick name entry and
/// destructive confirmations instead of bespoke SwiftUI sheets.
enum Prompt {
    /// Asks for a single line of text. Returns nil if cancelled. When `allowEmpty` is false
    /// (the default), an empty entry is also treated as nil; when true, it returns "".
    @MainActor
    static func text(title: String, message: String = "", defaultValue: String = "",
                     confirm: String = "OK", allowEmpty: Bool = false) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        if !message.isEmpty { alert.informativeText = message }
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let response = alert.runModal()

        // Unhook the accessory field from the alert window's key view loop before
        // teardown. `initialFirstResponder` and `nextKeyView` are unretained (assign)
        // references, and the alert's internal accessory hosting view is destroyed
        // lazily via autorelease -- if the loop still points at the freed field when
        // that happens, `-[NSView _removeFromKeyViewLoop]` crashes on a dangling
        // pointer (EXC_BAD_ACCESS in objc_msgSend).
        alert.window.makeFirstResponder(nil)
        alert.window.initialFirstResponder = nil
        field.nextKeyView = nil
        alert.accessoryView = nil
        field.removeFromSuperview()
        alert.window.recalculateKeyViewLoop()

        guard response == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return allowEmpty ? "" : nil }
        return value
    }

    /// Confirms a destructive action. Returns true if the user proceeds.
    @MainActor
    static func confirmDestructive(title: String, message: String, confirm: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Prompts for a directory using an open panel.
    @MainActor
    static func chooseDirectory(prompt: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }
}

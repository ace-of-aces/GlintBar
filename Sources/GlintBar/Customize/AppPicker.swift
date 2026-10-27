import AppKit
import UniformTypeIdentifiers

/// The open panel for choosing apps to launch from the GlintBar, shown as a sheet
/// on the customization window.
@MainActor
enum AppPicker {
    /// Asks for one or more apps to add.
    static func chooseApps(completion: @escaping @MainActor ([URL]) -> Void) {
        let panel = makePanel(prompt: "Add")
        panel.message = "Choose apps to launch from the GlintBar."
        panel.allowsMultipleSelection = true
        present(panel) { completion(panel.urls) }
    }

    /// Asks for the app that replaces `current`.
    static func chooseReplacement(for current: URL, completion: @escaping @MainActor (URL) -> Void) {
        let panel = makePanel(prompt: "Choose")
        panel.message =
            "Choose the app this button launches instead of \(FileManager.default.displayName(atPath: current.path))."
        panel.directoryURL = current.deletingLastPathComponent()
        present(panel) { panel.url.map(completion) }
    }

    private static func makePanel(prompt: String) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.prompt = prompt
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        return panel
    }

    private static func present(_ panel: NSOpenPanel, onChoose: @escaping @MainActor () -> Void) {
        guard let window = CustomizeWindowController.shared.window, window.isVisible else {
            if panel.runModal() == .OK { onChoose() }
            return
        }
        panel.beginSheetModal(for: window) { response in
            if response == .OK { onChoose() }
        }
    }
}

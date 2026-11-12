import AppKit
import SwiftUI

/// Simple Note Buffer: ten slots of text that are still there next week.
///
/// A place to put a piece of text that is not worth a file and must not be
/// lost when the app is closed. One window, ten numbered slots, a text
/// editor in each. Nothing to name, nothing to file, no history.
@main
struct SimpleNoteBufferApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage(AppearanceSetting.key) private var appearanceRaw = AppearanceSetting.system.rawValue
    @AppStorage(Preferences.labelsKey) private var showsLabels = true
    @AppStorage(Preferences.clipboardKey) private var showsClipboard = true

    var body: some Scene {
        Window("Simple Note Buffer", id: "main") {
            ContentView(store: delegate.store, controller: delegate.controller, clipboard: delegate.clipboard)
        }
        // No title bar: the glass columns run to the window's top, and a
        // bar of another colour over them read as a white strip.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 920, height: 560)
        .commands {
            // No documents here: nothing to make new or to open.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {
                Button("Save Slot to File…") { delegate.controller.save() }
                    .keyboardShortcut("s")
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Paste as Plain Text") { delegate.controller.pastePlain() }
                    .keyboardShortcut("v", modifiers: [.command, .option, .shift])
                Button("Copy Slot") { delegate.controller.copy() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Copy as Plain Text") { delegate.controller.copyPlain() }
                    .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                Divider()
                Button("Clear Slot") { delegate.controller.clear() }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
            }
            CommandMenu("Slot") {
                ForEach(0..<SlotStore.count, id: \.self) { index in
                    Button(delegate.store.isFilled(index) ? "Slot \(index + 1)" : "Slot \(index + 1) (empty)") {
                        delegate.store.selected = index
                        delegate.controller.focus()
                    }
                    .keyboardShortcut(KeyEquivalent(Character(index == 9 ? "0" : "\(index + 1)")))
                }
                Divider()
                Button("Next Slot") { step(1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Slot") { step(-1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
            }
            CommandGroup(before: .toolbar) {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppearanceSetting.allCases, id: \.rawValue) { setting in
                        Text(setting.title).tag(setting.rawValue)
                    }
                }
                Divider()
                Toggle("Show Button Labels", isOn: $showsLabels)
                Toggle("Show Clipboard", isOn: $showsClipboard)
                    .keyboardShortcut("b", modifiers: [.command, .option])
                Divider()
            }
        }
        .onChange(of: appearanceRaw) { _, raw in
            (AppearanceSetting(rawValue: raw) ?? .system).apply()
        }
    }

    private func step(_ by: Int) {
        let store = delegate.store
        store.selected = (store.selected + by + SlotStore.count) % SlotStore.count
        delegate.controller.focus()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SlotStore()
    private(set) lazy var controller = EditorController(store: store)
    let clipboard = ClipboardPeek()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceSetting.current.apply()
    }

    /// One window: closing it is leaving. The slots are on disk either way.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidResignActive(_ notification: Notification) { store.flush() }

    func applicationWillTerminate(_ notification: Notification) { store.flush() }
}

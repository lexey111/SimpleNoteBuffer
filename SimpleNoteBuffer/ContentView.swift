import AppKit
import SwiftUI

/// The window: the slots in a glass column at one side, the clipboard in a
/// glass column at the other, and between them a row of verbs, the page
/// and a status line. The window has no title bar of its own — the columns
/// run up under the traffic lights.
struct ContentView: View {
    let store: SlotStore
    let controller: EditorController
    let clipboard: ClipboardPeek
    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppearanceSetting.key) private var appearanceRaw = AppearanceSetting.system.rawValue
    @AppStorage(Preferences.labelsKey) private var showsLabels = true
    @AppStorage(Preferences.clipboardKey) private var showsClipboard = true
    @AppStorage(Preferences.slotsWidthKey) private var slotsWidth = 184.0
    @AppStorage(Preferences.clipboardWidthKey) private var clipboardWidth = 224.0

    /// Room for the traffic lights over the slots.
    private static let lightsRoom: CGFloat = 30

    var body: some View {
        let theme = Theme.of(scheme)
        // One sheet of glass under the whole window; the page floats on it
        // as a card, the slots and the clipboard lie on the glass itself.
        HStack(spacing: 0) {
            tabs(theme)
                .frame(width: slotsWidth)

            ColumnGrip(width: $slotsWidth, range: 120...340, grows: .trailing)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    verbs(theme)
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 10)
                .padding(.top, 7)
                .padding(.bottom, showsLabels ? 6 : 7)
                .background(theme.bar.gesture(WindowDragGesture()))

                Rectangle().fill(theme.stroke).frame(height: 1)

                EditorView(controller: controller, slot: store.selected)
                    .background(theme.page)

                Rectangle().fill(theme.stroke).frame(height: 1)

                HStack(spacing: 10) {
                    Text(status)
                    Spacer()
                    appearanceSwitch(theme)
                }
                .font(.system(size: 11))
                .foregroundStyle(theme.ink.opacity(0.5))
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
                .background(theme.bar)
            }
            .frame(minWidth: 380)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.stroke, lineWidth: 1))
            .padding(.vertical, 8)
            .padding(.trailing, showsClipboard ? 0 : 8)

            if showsClipboard {
                ColumnGrip(width: $clipboardWidth, range: 160...460, grows: .leading)
                ClipboardColumn(clipboard: clipboard, theme: theme)
                    .frame(width: clipboardWidth)
            }
        }
        .frame(minHeight: 400)
        .background(GlassBacking().ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            controller.focus()
            clipboard.start()
        }
    }

    private var status: String {
        let count = store.lengths[store.selected]
        let slot = "Slot \(store.selected + 1)"
        if count == 0 { return "\(slot) · empty" }
        return "\(slot) · " + (count == 1 ? "1 character" : "\(count.formatted()) characters")
    }

    /// The slots, top to bottom: a filled one wears a number in the system's
    /// accent and shows its first line, the chosen one stands on a plate.
    private func tabs(_ theme: Theme) -> some View {
        VStack(spacing: 3) {
            Color.clear.frame(height: Self.lightsRoom).contentShape(Rectangle()).gesture(WindowDragGesture())
            ForEach(0..<SlotStore.count, id: \.self) { index in
                SlotRow(index: index, chosen: index == store.selected, filled: store.isFilled(index),
                        hasWords: store.hasWords[index], preview: store.previews[index], theme: theme,
                        verb: { verb in on(index, verb) }) {
                    store.selected = index
                    controller.focus()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    /// A verb from a slot's own menu: the slot is put on the page first —
    /// a verb acts on what is seen — and then it is done.
    private func on(_ index: Int, _ verb: SlotVerb) {
        let wasShown = store.selected == index
        store.selected = index
        controller.show(index)
        switch verb {
        case .paste, .pastePlain: controller.aim(atEnd: !wasShown)
        case .copy, .copyPlain: controller.aim(atEnd: false)
        case .save, .clear: break
        }
        switch verb {
        case .paste: controller.paste()
        case .pastePlain: controller.pastePlain()
        case .copy: controller.copy() as Void   // not NSObject's copy()
        case .copyPlain: controller.copyPlain()
        case .save: controller.save()
        case .clear: controller.clear()
        }
    }

    private func verbs(_ theme: Theme) -> some View {
        let empty = !store.isFilled(store.selected)
        let wordless = !store.hasWords[store.selected]
        return HStack(spacing: 2) {
            verb("doc.on.clipboard", "Paste", "Paste — ⌘V", theme) { controller.paste() }
            verb("text.badge.plus", "Paste Plain", "Paste as Plain Text — ⌥⇧⌘V", theme) { controller.pastePlain() }
            divider(theme)
            verb("doc.on.doc", "Copy", "Copy the selection, or the whole slot — ⇧⌘C", theme, off: empty) { controller.copy() }
            verb("text.alignleft", "Copy Plain", "Copy as Plain Text — ⌥⇧⌘C", theme, off: wordless) { controller.copyPlain() }
            divider(theme)
            verb("square.and.arrow.down", "Save", "Save to File… — ⌘S", theme, off: empty) { controller.save() }
            divider(theme)
            verb("trash", "Clear", "Clear Slot — ⇧⌘⌫", theme, off: empty) { controller.clear() }
        }
    }

    private func divider(_ theme: Theme) -> some View {
        Rectangle().fill(theme.stroke).frame(width: 1, height: showsLabels ? 26 : 16).padding(.horizontal, 4)
    }

    private func verb(_ symbol: String, _ label: String, _ help: String, _ theme: Theme, off: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .frame(height: 16)
                if showsLabels {
                    Text(label)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, showsLabels ? 7 : 6)
            .padding(.vertical, 4)
            .frame(minWidth: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(VerbStyle(theme: theme))
        .disabled(off)
        .help(help)
    }

    /// Auto · Day · Night, in the status line.
    private func appearanceSwitch(_ theme: Theme) -> some View {
        HStack(spacing: 1) {
            ForEach(AppearanceSetting.allCases, id: \.rawValue) { setting in
                let chosen = setting.rawValue == appearanceRaw
                Button {
                    appearanceRaw = setting.rawValue
                    setting.apply()
                } label: {
                    Image(systemName: setting.symbol)
                        .font(.system(size: 10, weight: chosen ? .semibold : .regular))
                        .frame(width: 24, height: 16)
                        .foregroundStyle(theme.ink.opacity(chosen ? 0.9 : 0.45))
                        .background(RoundedRectangle(cornerRadius: 4).fill(theme.ink.opacity(chosen ? 0.12 : 0)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(setting.title)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(theme.ink.opacity(0.05)))
    }
}

/// What the user can switch off; the menus and the window read the same keys.
enum Preferences {
    static let labelsKey = "showsButtonLabels"
    static let clipboardKey = "showsClipboard"
    static let slotsWidthKey = "slotsWidth"
    static let clipboardWidthKey = "clipboardWidth"
}

/// The gap between a side column and the page: drag it to size the column.
/// A double click puts the width back.
private struct ColumnGrip: View {
    enum Side { case leading, trailing }
    @Binding var width: Double
    let range: ClosedRange<Double>
    /// The side the column grows toward as the grip moves.
    let grows: Side
    @State private var start: Double?
    @State private var hovered = false

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(hovered || start != nil ? 0.10 : 0))
            .frame(width: 3)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 3)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let from = start ?? width
                        start = from
                        let moved = grows == .trailing ? drag.translation.width : -drag.translation.width
                        width = min(max(from + moved, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in start = nil }
            )
            .onTapGesture(count: 2) { width = grows == .trailing ? 184 : 224 }
    }
}

/// What the bar's buttons do — the same six in a slot's menu.
enum SlotVerb { case paste, pastePlain, copy, copyPlain, save, clear }

/// One slot in the column.
private struct SlotRow: View {
    let index: Int
    let chosen: Bool
    let filled: Bool
    let hasWords: Bool
    let preview: String
    let theme: Theme
    let verb: (SlotVerb) -> Void
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(index == 9 ? "0" : "\(index + 1)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 20, height: 18)
                    .foregroundStyle(filled ? Theme.onAccent : theme.ink.opacity(0.45))
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(filled ? Theme.accent : theme.ink.opacity(0.07)))
                Text(filled ? preview : "Empty")
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(theme.ink.opacity(filled ? (chosen ? 0.95 : 0.75) : 0.3))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.ink.opacity(chosen ? 0.13 : hovered ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Slot \(index + 1) — ⌘\(index == 9 ? 0 : index + 1)")
        // Everything the bar does, for this slot, under the right button.
        .contextMenu {
            Button("Paste", systemImage: "doc.on.clipboard") { verb(.paste) }
            Button("Paste as Plain Text", systemImage: "text.badge.plus") { verb(.pastePlain) }
            Divider()
            Button("Copy", systemImage: "doc.on.doc") { verb(.copy) }.disabled(!filled)
            Button("Copy as Plain Text", systemImage: "text.alignleft") { verb(.copyPlain) }.disabled(!hasWords)
            Divider()
            Button("Save to File…", systemImage: "square.and.arrow.down") { verb(.save) }.disabled(!filled)
            Divider()
            Button("Clear", systemImage: "trash") { verb(.clear) }.disabled(!filled)
        }
    }
}

/// The clipboard as it stands: a look, nothing to edit.
private struct ClipboardColumn: View {
    let clipboard: ClipboardPeek
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CLIPBOARD")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(theme.ink.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 30, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder private var content: some View {
        switch clipboard.content {
        case .empty:
            note("Empty")
        case .concealed:
            note("Concealed", "A password manager marked it; it is not read.")
        case .other:
            note("Not text or a picture")
        case .text(let head, let characters):
            caption(characters == 1 ? "1 character" : "\(characters.formatted()) characters")
            Text(head)
                .font(.system(size: 11))
                .foregroundStyle(theme.ink.opacity(0.8))
                .lineSpacing(1.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        case .image(let image, let width, let height):
            caption(width > 0 ? "Picture · \(width) × \(height)" : "Picture")
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.stroke, lineWidth: 1))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .mixed(let head, let characters, let pictures):
            caption((characters == 1 ? "1 character" : "\(characters.formatted()) characters")
                    + " · " + (pictures.count == 1 ? "1 picture" : "\(pictures.count) pictures"))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    if !head.isEmpty {
                        Text(head)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.ink.opacity(0.8))
                            .lineLimit(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(pictures.enumerated()), id: \.offset) { _, picture in
                        Image(nsImage: picture)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.stroke, lineWidth: 1))
                    }
                }
            }
        case .files(let names):
            caption(names.count == 1 ? "1 file" : "\(names.count) files")
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(names.prefix(12).enumerated()), id: \.offset) { _, name in
                    Text(name).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(theme.ink.opacity(0.8))
                }
            }
        case .withheld(let kind):
            note(kind, "macOS asks before this app reads the clipboard. Allow it once in Settings to see the preview.")
            Button("Clipboard Privacy Settings…") { NSWorkspace.shared.open(ClipboardPeek.privacySettings) }
                .buttonStyle(.link)
                .font(.system(size: 11))
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(theme.ink.opacity(0.45))
    }

    private func note(_ title: String, _ detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12)).foregroundStyle(theme.ink.opacity(0.55))
            if let detail {
                Text(detail).font(.system(size: 11)).foregroundStyle(theme.ink.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The system's sidebar glass: what is behind the window shows through.
private struct GlassBacking: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// A toolbar verb that answers the pointer and the press.
private struct VerbStyle: ButtonStyle {
    let theme: Theme
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(theme.ink.opacity(enabled ? 0.8 : 0.25))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.ink.opacity(configuration.isPressed ? 0.16 : hovered && enabled ? 0.08 : 0))
            )
            .onHover { hovered = $0 }
    }
}

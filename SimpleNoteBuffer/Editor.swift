import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The one text view and what the toolbar and the menus do to it.
///
/// A single `NSTextView` shows whichever slot is chosen; its text goes to
/// the store on every change. Rich text and pictures are AppKit's own —
/// the view is a rich one that imports graphics — so the work here is the
/// plain-text doors beside them and keeping the page readable in the dark.
final class EditorController: NSObject, NSTextViewDelegate {
    let store: SlotStore
    private weak var textView: NSTextView?
    private var shown = -1

    init(store: SlotStore) { self.store = store }

    func attach(_ view: NSTextView) {
        textView = view
        view.delegate = self
        // The page's width changes with the window and the columns; the
        // pictures on it are fitted again.
        view.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
            self?.fitPictures()
        }
    }

    /// A picture wider than the page is drawn at the page's width — the
    /// page has no sideways scroll, and a screenshot ran off its edge. Only
    /// how it is drawn changes: the picture in the slot keeps every pixel.
    private func fitPictures() {
        guard let textView, let storage = textView.textStorage, storage.length > 0,
              let container = textView.textContainer else { return }
        let room = container.size.width - container.lineFragmentPadding * 2
        guard room > 40 else { return }
        var changed: [NSRange] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            let natural = Self.naturalSize(attachment)
            guard natural.width > 0 else { return }
            let wanted: CGRect = natural.width > room
                ? CGRect(x: 0, y: 0, width: room, height: (natural.height * room / natural.width).rounded())
                : .zero
            if attachment.bounds != wanted {
                attachment.bounds = wanted
                changed.append(range)
            }
        }
        guard !changed.isEmpty else { return }
        storage.beginEditing()
        for range in changed { storage.edited(.editedAttributes, range: range, changeInLength: 0) }
        storage.endEditing()
    }

    private static var sizes = NSMapTable<NSTextAttachment, NSValue>.weakToStrongObjects()

    /// The picture's own size, read once per attachment.
    private static func naturalSize(_ attachment: NSTextAttachment) -> CGSize {
        if let known = sizes.object(forKey: attachment) { return known.sizeValue }
        var size = CGSize.zero
        if let image = attachment.image {
            size = image.size
        } else if let data = attachment.fileWrapper?.regularFileContents, let image = NSImage(data: data) {
            size = image.size
        }
        sizes.setObject(NSValue(size: size), forKey: attachment)
        return size
    }

    /// Puts a slot's text on the page. The undo stack belongs to the slot
    /// that was there, so it is dropped.
    func show(_ index: Int) {
        guard let textView, shown != index else { return }
        shown = index
        textView.undoManager?.removeAllActions()
        textView.textStorage?.setAttributedString(store.text(index))
        textView.typingAttributes = SlotStore.baseAttributes
        fitPictures()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollToBeginningOfDocument(nil)
    }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    func textDidChange(_ notification: Notification) {
        guard let textView, shown >= 0, let storage = textView.textStorage else { return }
        fitPictures()
        store.update(shown, NSAttributedString(attributedString: storage))
    }

    // MARK: - Toolbar

    /// The clipboard as it is: styles and pictures come along.
    func paste() {
        focus()
        textView?.paste(nil)
    }

    /// The clipboard's words only, in the slot's own type.
    func pastePlain() {
        guard let textView else { return }
        focus()
        textView.typingAttributes = SlotStore.baseAttributes
        textView.pasteAsPlainText(nil)
    }

    /// The selection, or the whole slot when nothing is selected.
    private var copyRange: NSRange? {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return nil }
        let selection = textView.selectedRange()
        return selection.length > 0 ? selection : NSRange(location: 0, length: storage.length)
    }

    func copy() {
        guard let range = copyRange, let storage = textView?.textStorage,
              let item = Self.pasteboardItem(for: storage.attributedSubstring(from: range)) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    /// A piece of a slot as the clipboard takes it, richest form first —
    /// the order is what a receiver goes by. Written out by hand: an
    /// attributed string handed over as it is lost a slot of pictures alone.
    static func pasteboardItem(for piece: NSAttributedString) -> NSPasteboardItem? {
        let whole = NSRange(location: 0, length: piece.length)
        let item = NSPasteboardItem()
        let words = SlotStore.hasWords(piece)
        // A picture by itself goes as the picture and nothing else. With
        // styled text beside it the system makes up a plain-text form too —
        // one invisible character — and that is what some receivers paste.
        if !words, let image = onlyPicture(piece), let tiff = image.tiffRepresentation {
            if let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                item.setData(png, forType: .png)
            }
            item.setData(tiff, forType: .tiff)
            return item
        }
        if let rtfd = piece.rtfd(from: whole, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) {
            item.setData(rtfd, forType: .rtfd)
        }
        if let rtf = piece.rtf(from: whole, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            item.setData(rtf, forType: .rtf)
        }
        if words { item.setString(plain(piece), forType: .string) }
        return item.types.isEmpty ? nil : item
    }

    /// The words only. A piece with no words leaves the clipboard as it was.
    func copyPlain() {
        guard let range = copyRange, let storage = textView?.textStorage else { return }
        let piece = storage.attributedSubstring(from: range)
        guard SlotStore.hasWords(piece) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.plain(piece), forType: .string)
    }

    /// Empties the slot. Undo brings the text back, so nothing is asked.
    func clear() {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return }
        let whole = NSRange(location: 0, length: storage.length)
        guard textView.shouldChangeText(in: whole, replacementString: "") else { return }
        storage.replaceCharacters(in: whole, with: "")
        textView.didChangeText()
        textView.typingAttributes = SlotStore.baseAttributes
        textView.undoManager?.setActionName("Clear Slot")
        focus()
    }

    /// The slot as a file: plain text, RTF, or RTFD where it holds pictures.
    func save() {
        guard let textView, let storage = textView.textStorage, storage.length > 0,
              let window = textView.window else { return }
        let text = NSAttributedString(attributedString: storage)
        let panel = NSSavePanel()
        panel.allowedContentTypes = Self.hasPictures(text) ? [.rtfd, .rtf, .plainText] : [.plainText, .rtf]
        panel.showsContentTypes = true
        panel.nameFieldStringValue = "Slot \(shown + 1)"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            // No type from the panel means the name was typed with its own
            // extension: go by that, plain text where it says nothing.
            let type = panel.currentContentType ?? UTType(filenameExtension: url.pathExtension) ?? .plainText
            let whole = NSRange(location: 0, length: text.length)
            do {
                if type.conforms(to: .rtfd) {
                    let wrapper = try text.fileWrapper(
                        from: whole, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
                    try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
                } else if type.conforms(to: .rtf) {
                    let data = try text.data(
                        from: whole, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
                    try data.write(to: url, options: .atomic)
                } else {
                    try Self.plain(text).write(to: url, atomically: true, encoding: .utf8)
                }
            } catch {
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
    }

    // MARK: - Helpers

    /// The words without the object-replacement characters pictures stand on.
    static func plain(_ text: NSAttributedString) -> String {
        text.string.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    /// The picture of a piece that holds exactly one.
    static func onlyPicture(_ text: NSAttributedString) -> NSImage? {
        var attachments: [NSTextAttachment] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment { attachments.append(attachment) }
        }
        guard attachments.count == 1, let attachment = attachments.first else { return nil }
        if let image = attachment.image { return image }
        if let data = attachment.fileWrapper?.regularFileContents { return NSImage(data: data) }
        return nil
    }

    static func hasPictures(_ text: NSAttributedString) -> Bool {
        var found = false
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if value != nil { found = true; stop.pointee = true }
        }
        return found
    }
}

/// The text view in a scroll view, set up once; `slot` says what it shows.
struct EditorView: NSViewRepresentable {
    let controller: EditorController
    let slot: Int

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.isRichText = true
        view.importsGraphics = true
        view.allowsUndo = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 18, height: 16)
        // Text pasted from a light page stays readable on a dark one.
        view.usesAdaptiveColorMappingForDarkAppearance = true
        // A buffer keeps what it was given: nothing is corrected or replaced.
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        controller.attach(view)
        controller.show(slot)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        controller.show(slot)
    }
}

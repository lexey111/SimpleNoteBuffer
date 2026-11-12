import AppKit
import Observation

/// Ten slots of text that outlive the app.
///
/// A slot is an attributed string — plain text, styled text or text with
/// pictures, whatever was put there. Each one is written to its own file in
/// Application Support a moment after it changes, and read back at launch.
/// There are no names, no history and no folders: a slot is a number.
@Observable
final class SlotStore {
    static let count = 10

    /// Characters in each slot; zero is an empty slot. The tabs and the
    /// status line read this, so they follow the text as it is typed.
    private(set) var lengths: [Int]

    /// The first line of each slot, for the tab — not a name, only a look
    /// at what is inside.
    private(set) var previews: [String]

    /// Whether a slot holds any words — a slot of pictures alone has
    /// nothing to give as plain text.
    private(set) var hasWords: [Bool]

    var selected: Int {
        didSet { UserDefaults.standard.set(selected, forKey: Self.selectedKey) }
    }

    @ObservationIgnored private var texts: [NSAttributedString]
    @ObservationIgnored private var pending: [Int: DispatchWorkItem] = [:]
    @ObservationIgnored private let directory: URL

    private static let selectedKey = "selectedSlot"

    /// What a slot's text looks like until something says otherwise.
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph]
    }

    /// Monaco, the Mac's old programmer's face: even, quiet, every
    /// character told from its neighbour.
    static let font = NSFont(name: "Monaco", size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .regular)

    private static let paragraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        return style
    }()

    /// The slots' own ink: a soft light grey on the dark page, a soft black
    /// on the light one — never pure white or pure black. One object, so a
    /// run in it can be told from a colour the text was given.
    static let ink = NSColor(name: "SlotInk") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.72, alpha: 1) : NSColor(white: 0.17, alpha: 1)
    }

    /// `directory` is where the slots are kept; the app's own Application
    /// Support folder unless a test names another.
    init(directory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var directory = directory
        #if DEBUG
        // `-storeFolder <name>`: another set of slots beside the real one,
        // for screenshots that show no one's own text.
        if directory == nil, let name = UserDefaults.standard.string(forKey: "storeFolder"), !name.isEmpty {
            directory = support.appendingPathComponent(name, isDirectory: true)
        }
        #endif
        self.directory = directory ?? support.appendingPathComponent("SimpleNoteBuffer", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)

        var loaded: [NSAttributedString] = []
        for index in 0..<Self.count {
            loaded.append(Self.read(self.directory.appendingPathComponent(Self.fileName(index))))
        }
        // Once, for slots filled before the type was Monaco: their plain
        // runs take the new face. Only in the app's own store, and only
        // the first time — later, a slot's type is whatever it was given.
        var migrated: [Int] = []
        if directory == nil, !UserDefaults.standard.bool(forKey: Self.typeMigratedKey) {
            for index in loaded.indices where loaded[index].length > 0 {
                if let changed = Self.takingBaseType(loaded[index]) {
                    loaded[index] = changed
                    migrated.append(index)
                }
            }
            UserDefaults.standard.set(true, forKey: Self.typeMigratedKey)
        }
        texts = loaded
        lengths = loaded.map(\.length)
        previews = loaded.map(Self.preview)
        hasWords = loaded.map(Self.hasWords)
        let saved = UserDefaults.standard.integer(forKey: Self.selectedKey)
        selected = (0..<Self.count).contains(saved) ? saved : 0
        migrated.forEach(write)
    }

    private static let typeMigratedKey = "typeMigratedToMonaco"

    /// The text with its plain runs — the old default: 14 pt, neither bold
    /// nor italic — set in the base type; nil where there are none.
    static func takingBaseType(_ text: NSAttributedString) -> NSAttributedString? {
        let result = NSMutableAttributedString(attributedString: text)
        var changed = false
        result.enumerateAttribute(.font, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            guard let face = value as? NSFont, face.pointSize == 14 else { return }
            let traits = face.fontDescriptor.symbolicTraits
            guard !traits.contains(.bold), !traits.contains(.italic), !traits.contains(.monoSpace) else { return }
            result.addAttributes([.font: font, .paragraphStyle: paragraph], range: range)
            changed = true
        }
        return changed ? result : nil
    }

    func text(_ index: Int) -> NSAttributedString { texts[index] }

    func isFilled(_ index: Int) -> Bool { lengths[index] > 0 }

    /// The editor's text, taken as it stands; written to disk half a second
    /// after the last change.
    func update(_ index: Int, _ text: NSAttributedString) {
        texts[index] = text
        if lengths[index] != text.length { lengths[index] = text.length }
        let preview = Self.preview(text)
        if previews[index] != preview { previews[index] = preview }
        let words = Self.hasWords(text)
        if hasWords[index] != words { hasWords[index] = words }
        pending[index]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.write(index) }
        pending[index] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Everything not yet on disk goes there now — the app is being put
    /// aside or quit.
    func flush() {
        for (index, work) in pending {
            work.cancel()
            write(index)
        }
        pending.removeAll()
    }

    /// The first line that says something, cut short; a picture where the
    /// slot holds pictures alone.
    private static func preview(_ text: NSAttributedString) -> String {
        guard text.length > 0 else { return "" }
        let head = text.string.prefix(400).replacingOccurrences(of: "\u{FFFC}", with: "")
        let line = head.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line else { return "Picture" }
        return String(line.prefix(48))
    }

    static func hasWords(_ text: NSAttributedString) -> Bool {
        text.string.unicodeScalars.contains { $0 != "\u{FFFC}" && !CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    // MARK: - Files

    private static func fileName(_ index: Int) -> String { "slot-\(index + 1).rtfd-data" }

    private func write(_ index: Int) {
        pending[index] = nil
        let url = directory.appendingPathComponent(Self.fileName(index))
        let text = texts[index]
        guard text.length > 0 else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        // The default ink is not written: a dynamic colour is flattened to
        // the appearance it was saved under, and text saved in the dark
        // would come back white on a light page. It is put back on reading.
        let stored = NSMutableAttributedString(attributedString: text)
        stored.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: stored.length)) { value, range, _ in
            if let colour = value as? NSColor, colour === Self.ink || colour == NSColor.textColor {
                stored.removeAttribute(.foregroundColor, range: range)
            }
        }
        let range = NSRange(location: 0, length: stored.length)
        if let data = try? stored.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func read(_ url: URL) -> NSAttributedString {
        guard let data = try? Data(contentsOf: url),
              let text = try? NSMutableAttributedString(
                data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
        else { return NSAttributedString() }
        let whole = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in
            if value == nil { text.addAttribute(.foregroundColor, value: ink, range: range) }
        }
        return text
    }
}

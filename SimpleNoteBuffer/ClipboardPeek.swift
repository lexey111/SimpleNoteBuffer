import AppKit
import ImageIO
import Observation
import UniformTypeIdentifiers

/// What is on the clipboard now, for the column at the window's side.
///
/// macOS has no notification for the clipboard, so its change count — one
/// integer — is looked at twice a second, and only while this app is in
/// front; the data is read once per change, off the main thread. Where the
/// system is set to ask before every read, nothing is read: the column says
/// so instead of raising a dialog on each copy.
@Observable
final class ClipboardPeek {
    enum Content: Equatable {
        case empty
        /// A password manager marked it; it is never read.
        case concealed
        case text(head: String, characters: Int)
        case image(NSImage, width: Int, height: Int)
        /// Styled text with pictures in it: the words and the pictures.
        case mixed(head: String, characters: Int, pictures: [NSImage])
        case files([String])
        /// Something that is neither words, a picture nor files.
        case other
        /// macOS asks before each read, or refuses; `kind` is what the
        /// type list alone tells.
        case withheld(kind: String)
    }

    private(set) var content: Content = .empty

    @ObservationIgnored private let pasteboard = NSPasteboard.general
    @ObservationIgnored private var seen = -1
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private static let concealedMarker = "org.nspasteboard.ConcealedType"
    private static let textTypes: Set<String> = [
        "public.utf8-plain-text", "public.utf16-plain-text", "public.plain-text",
        "public.utf16-external-plain-text", "NSStringPboardType", "public.rtf", "public.html", "public.url",
        "com.apple.flat-rtfd",
    ]

    /// The settings page where reading the clipboard is allowed.
    static let privacySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")!

    func start() {
        guard observers.isEmpty else { return }
        let centre = NotificationCenter.default
        observers.append(centre.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.check()
            self?.run()
        })
        observers.append(centre.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.timer?.invalidate()
            self?.timer = nil
        })
        check()
        if NSApp.isActive { run() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private func run() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.check() }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func check() {
        let count = pasteboard.changeCount
        guard count != seen else { return }
        seen = count
        refresh()
    }

    private enum Plan { case done(Content), image(String), text, files }

    private func refresh() {
        generation += 1
        let generation = generation
        let types = pasteboard.types?.map(\.rawValue) ?? []
        let plan = Self.plan(types)

        if case .done(let content) = plan {
            self.content = content
            return
        }
        // Reading data is what the system may ask about; the type list is not.
        let access = pasteboard.accessBehavior
        if access == .ask || access == .alwaysDeny {
            switch plan {
            case .image: content = .withheld(kind: "A picture")
            case .text: content = .withheld(kind: "Text")
            case .files: content = .withheld(kind: "Files")
            case .done: break
            }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let read = Self.read(plan)
            DispatchQueue.main.async {
                guard let self, generation == self.generation else { return }
                self.content = read
            }
        }
    }

    private static func plan(_ types: [String]) -> Plan {
        if types.isEmpty { return .done(.empty) }
        if types.contains(concealedMarker) { return .done(.concealed) }
        if types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) { return .files }
        // The sender lists its richest form first, so the first type known
        // decides: a screenshot leads with images, styled text with text.
        let decodable = Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
        for type in types {
            if decodable.contains(type) { return .image(type) }
            if textTypes.contains(type) { return .text }
        }
        return .done(.other)
    }

    private static func read(_ plan: Plan) -> Content {
        let pasteboard = NSPasteboard.general
        switch plan {
        case .done(let content):
            return content
        case .text:
            // Text with pictures in it travels as RTFD. Its plain form
            // names the words only — «2 characters» for two letters and a
            // screenshot — so the pictures are looked for first.
            if let data = pasteboard.data(forType: .rtfd), let rich = NSAttributedString(rtfd: data, documentAttributes: nil) {
                var pictures: [NSImage] = []
                var count = 0
                rich.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rich.length)) { value, _, _ in
                    guard let attachment = value as? NSTextAttachment else { return }
                    count += 1
                    guard pictures.count < 4, let bytes = attachment.fileWrapper?.regularFileContents,
                          let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                          let shown = thumbnail(source) else { return }
                    pictures.append(shown.image)
                }
                if count > 0 {
                    let words = rich.string.replacingOccurrences(of: "\u{FFFC}", with: "")
                    let head = words.trimmingCharacters(in: .whitespacesAndNewlines)
                    if head.isEmpty, count == 1, let only = pictures.first {
                        return .image(only, width: 0, height: 0)
                    }
                    return .mixed(head: String(head.prefix(600)), characters: words.count, pictures: pictures)
                }
            }
            if let string = pasteboard.string(forType: .string), !string.isEmpty {
                return .text(head: String(string.prefix(1200)), characters: string.count)
            }
            // Styled text with no words is a picture in a text's wrapping:
            // shown as the picture, where one is sent beside it.
            let decodable = Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
            for type in pasteboard.types ?? [] where decodable.contains(type.rawValue) {
                if let data = pasteboard.data(forType: type), let source = CGImageSourceCreateWithData(data as CFData, nil),
                   let shown = picture(source) { return shown }
            }
            return .other
        case .files:
            let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            guard !urls.isEmpty else { return .other }
            // One picture file is shown as the picture: a photo copied in a
            // messenger arrives as a file, and its name says nothing. The
            // file itself first (reading its URL off the pasteboard lets a
            // sandboxed app open it), then any picture sent beside it —
            // never for other files, where that picture is only the icon.
            if urls.count == 1, let url = urls.first,
               UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true {
                if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let shown = picture(source) { return shown }
                let decodable = Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
                for type in pasteboard.types ?? [] where decodable.contains(type.rawValue) {
                    if let data = pasteboard.data(forType: type), let source = CGImageSourceCreateWithData(data as CFData, nil),
                       let shown = picture(source) { return shown }
                }
            }
            return .files(urls.map(\.lastPathComponent))
        case .image(let type):
            guard let data = pasteboard.data(forType: NSPasteboard.PasteboardType(type)),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let shown = picture(source) else { return .other }
            return shown
        }
    }

    /// The picture at the column's size, with the size it really has.
    private static func picture(_ source: CGImageSource) -> Content? {
        thumbnail(source).map { .image($0.image, width: $0.width, height: $0.height) }
    }

    private static func thumbnail(_ source: CGImageSource) -> (image: NSImage, width: Int, height: Int)? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 920,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return (NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height)), width, height)
    }
}

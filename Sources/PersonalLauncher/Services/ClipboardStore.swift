import AppKit
import Foundation

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let persistenceURL: URL
    private let imageDirectory: URL

    init() {
        lastChangeCount = pasteboard.changeCount
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PersonalLauncher", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        persistenceURL = directory.appendingPathComponent("clipboard.json")
        imageDirectory = directory.appendingPathComponent("clipboard-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        restore()
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.captureIfNeeded() }
        }
    }

    deinit { timer?.invalidate() }

    func filtered(by query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return items }
        return items.compactMap { item in
            FuzzyMatcher.score(query: query, candidate: item.summary).map { (item, $0) }
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }

    func copy(_ item: ClipboardItem) {
        pasteboard.clearContents()
        switch item.kind {
        case .file:
            pasteboard.writeObjects([URL(fileURLWithPath: item.text) as NSURL])
        case .image:
            if let image = NSImage(contentsOfFile: item.text) { pasteboard.writeObjects([image]) }
        default:
            pasteboard.setString(item.text, forType: .string)
        }
        lastChangeCount = pasteboard.changeCount
    }

    func remove(_ item: ClipboardItem) {
        if item.kind == .image { try? FileManager.default.removeItem(atPath: item.text) }
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        for item in items where item.kind == .image { try? FileManager.default.removeItem(atPath: item.text) }
        items.removeAll()
        persist()
    }

    func ignoreCurrentPasteboardChange() {
        lastChangeCount = pasteboard.changeCount
    }

    private func captureIfNeeded() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let captured: ClipboardItem?
        if let fileURL = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL,
           fileURL.isFileURL {
            captured = ClipboardItem(kind: .file, text: fileURL.path)
        } else if let image = NSImage(pasteboard: pasteboard),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) {
            if let existing = items.first(where: {
                $0.kind == .image && (try? Data(contentsOf: URL(fileURLWithPath: $0.text))) == png
            }) {
                captured = ClipboardItem(kind: .image, text: existing.text)
            } else {
                let id = UUID()
                let file = imageDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("png")
                try? png.write(to: file, options: .atomic)
                captured = ClipboardItem(id: id, kind: .image, text: file.path)
            }
        } else if let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty {
            let kind: ClipboardKind = URL(string: text)?.scheme != nil ? .link : .text
            captured = ClipboardItem(kind: kind, text: text)
        } else {
            captured = nil
        }

        guard let captured else { return }
        items.removeAll { $0.kind == captured.kind && $0.text == captured.text }
        items.insert(captured, at: 0)
        if items.count > 120 {
            let removed = items.suffix(items.count - 120)
            for item in removed where item.kind == .image { try? FileManager.default.removeItem(atPath: item.text) }
            items.removeLast(items.count - 120)
        }
        persist()
    }

    private func restore() {
        guard let data = try? Data(contentsOf: persistenceURL),
              let restored = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }
        items = restored
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: persistenceURL, options: .atomic)
    }
}

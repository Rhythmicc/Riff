import AppKit
import SwiftUI

struct UnicodeSymbolTile: View {
    let item: UnicodeSymbol
    let selected: Bool

    var body: some View {
        VStack(spacing: 5) {
            Text(item.displayGlyph).font(.system(size: 30)).frame(height: 38)
            Text(item.name.capitalized)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(LauncherTheme.primary)
                .lineLimit(1)
            Text(item.codePointLabel)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(LauncherTheme.secondary)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .background(
            selected ? Color.clear : LauncherTheme.tileSurface,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .riffSelectedSurface(selected, cornerRadius: 12)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? .clear : LauncherTheme.hairline, lineWidth: 0.5)
        }
        .contentShape(Rectangle())
    }
}

struct LauncherCommandRow: View {
    let title: String
    let symbol: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(LauncherTheme.secondary)
                .frame(width: 34, height: 34)
            Text(title)
                .font(.system(size: 16.5, weight: .medium))
                .lineLimit(1)
            Spacer()
            if selected {
                Image(systemName: "return")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LauncherTheme.secondary)
            }
        }
        .foregroundStyle(LauncherTheme.primary)
        .padding(.horizontal, 18)
        .frame(height: LauncherView.candidateRowDesignHeight)
        .riffSelectedSurface(selected, cornerRadius: 11)
        .contentShape(Rectangle())
    }
}

struct ComponentResultRow: View {
    let item: ComponentResultItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: item.icon?.systemName ?? "square.grid.2x2")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(LauncherTheme.secondary)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 16.5, weight: .medium))
                    .lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "return")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LauncherTheme.secondary)
            }
        }
        .foregroundStyle(LauncherTheme.primary)
        .padding(.horizontal, 18)
        .frame(minHeight: LauncherView.candidateRowDesignHeight)
        .riffSelectedSurface(selected, cornerRadius: 11)
        .contentShape(Rectangle())
    }
}

struct LauncherSearchRow: View {
    let item: LauncherSearchItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 16) {
            iconView
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 16.5, weight: .medium))
                    .lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(item.category.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(LauncherTheme.secondary)
            if selected {
                Image(systemName: "return")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LauncherTheme.secondary)
            }
        }
        .foregroundStyle(LauncherTheme.primary)
        .padding(.horizontal, 18)
        .frame(minHeight: LauncherView.candidateRowDesignHeight)
        .riffSelectedSurface(selected, cornerRadius: 11)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var iconView: some View {
        if case .application(let application) = item.payload {
            Image(nsImage: LauncherImageCache.shared.applicationIcon(for: application.url))
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
        } else {
            Image(systemName: item.symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(LauncherTheme.secondary)
                .frame(width: 34, height: 34)
        }
    }
}

@MainActor
final class LauncherImageCache {
    static let shared = LauncherImageCache()
    private let applications = NSCache<NSString, NSImage>()
    private let previews = NSCache<NSString, NSImage>()

    private init() {
        applications.countLimit = 256
        previews.countLimit = 64
    }

    func applicationIcon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let cached = applications.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        applications.setObject(icon, forKey: key)
        return icon
    }

    func preview(for url: URL) -> NSImage? {
        image(for: url, cache: previews) { NSImage(contentsOf: url) }
    }

    private func image(
        for url: URL,
        cache: NSCache<NSString, NSImage>,
        load: () -> NSImage?
    ) -> NSImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = load() else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

struct ClipboardRow: View {
    let item: ClipboardItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 14) {
            if let url = item.imagePreviewURL,
               let image = LauncherImageCache.shared.preview(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(LauncherTheme.hairline, lineWidth: 0.5)
                    }
            } else {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(LauncherTheme.secondary)
                    .frame(width: 42)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(item.summary.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(LauncherTheme.primary)
                    .lineLimit(2)
                Text(item.createdAt, style: .relative)
                    .font(.system(size: 11.5))
                    .foregroundStyle(LauncherTheme.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 67)
        .riffSelectedSurface(selected, cornerRadius: 10)
        .contentShape(Rectangle())
    }
}

struct ClipboardPreview: View {
    let item: ClipboardItem?

    var body: some View {
        Group {
            if let item {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(item.previewTitle, systemImage: item.imagePreviewURL == nil ? item.kind.symbol : "photo")
                        Spacer()
                        Text(item.createdAt, style: .time)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LauncherTheme.secondary)
                    if let url = item.imagePreviewURL,
                       LauncherImageCache.shared.preview(for: url) != nil {
                        AnimatedClipboardImageView(url: url)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(LauncherTheme.tileSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(LauncherTheme.hairline, lineWidth: 0.5)
                            }
                    } else {
                        RichSelectableTextView(
                            source: item.text,
                            syntax: .plain,
                            fontSize: 15,
                            textColor: .labelColor
                        )
                    }
                }
                .padding(24)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 28, weight: .light))
                    Text("复制一些内容后会出现在这里")
                }
                .foregroundStyle(LauncherTheme.secondary)
            }
        }
    }
}

struct AnimatedClipboardImageView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> ClipboardNSImageView {
        let imageView = ClipboardNSImageView()
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageFrameStyle = .none
        imageView.animates = true
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        update(imageView)
        return imageView
    }

    func updateNSView(_ imageView: ClipboardNSImageView, context: Context) { update(imageView) }

    private func update(_ imageView: ClipboardNSImageView) {
        guard imageView.representedURL != url else { return }
        imageView.representedURL = url
        imageView.image = LauncherImageCache.shared.preview(for: url)
        imageView.animates = true
    }
}

final class ClipboardNSImageView: NSImageView {
    var representedURL: URL?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

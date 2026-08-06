import AppKit
import SwiftUI
import XCTest
@testable import Riff

final class LauncherVisualSnapshotTests: XCTestCase {
    @MainActor
    func testCollapsedLauncherVisualSnapshot() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["RIFF_LAUNCHER_SNAPSHOT_PATH"] else {
            throw XCTSkip("Set RIFF_LAUNCHER_SNAPSHOT_PATH to render the visual QA artifact.")
        }

        let snapshotQuery = ProcessInfo.processInfo.environment["RIFF_LAUNCHER_SNAPSHOT_QUERY"]
        let canvasHeight: CGFloat = snapshotQuery == nil ? 260 : 760
        let model = AppModel(clipboard: ClipboardStore())
        if let query = snapshotQuery {
            model.query = query
        }
        let view = ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.10, blue: 0.18),
                    Color(red: 0.17, green: 0.08, blue: 0.25),
                    Color(red: 0.03, green: 0.22, blue: 0.28)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            HStack(spacing: 52) {
                ForEach(0..<7, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(index.isMultiple(of: 2) ? 0.22 : 0.11))
                        .frame(width: 90, height: 90)
                        .overlay {
                            Image(systemName: ["photo", "bubble.left.and.bubble.right", "music.note", "doc.text"][index % 4])
                                .font(.system(size: 31, weight: .medium))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                }
            }
            .blur(radius: 3)
            .offset(y: 54)

            LauncherView(
                model: model,
                close: {},
                showNote: {},
                showSettings: {},
                setDesignSize: { _ in },
                focusReady: {}
            )
        }
        .frame(width: 1120, height: canvasHeight)
        .environment(\.colorScheme, .dark)

        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 1120, height: canvasHeight)
        let window = NSWindow(
            contentRect: host.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .black
        window.contentView = host
        window.orderFrontRegardless()

        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        host.displayIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            return XCTFail("Could not allocate a visual snapshot bitmap.")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            return XCTFail("Could not encode the visual snapshot as PNG.")
        }

        try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        window.orderOut(nil)
        XCTAssertGreaterThan(png.count, 10_000)
    }
}

import AppKit
import SwiftUI
import XCTest
@testable import Riff

@MainActor
final class TranslationRenderingSnapshotTests: XCTestCase {
    func testTranslationPanelRendersMarkdownAndMath() throws {
        let source = #"After the last pooling operation, the \(2\times2\times128\) tensor is flattened to 512 values. The head uses \(512\to256\) and \(256\to128\) fully connected layers, each followed by \(\tanh\). We append the normalized block density \(d=\mathrm{nnz}/256\), giving 129 inputs to a final \(129\to7\) layer. This layer produces logits for COO, CSR, ELL, HYB, DRW, DCL, and DNS without an activation function. Training applies softmax cross-entropy to these logits; inference selects the argmax."#
        let result = #"在最后一次池化操作之后，\(2\times2\times128\) 的张量被展平为 512 个值。头部使用 \(512\to256\) 和 \(256\to128\) 的全连接层，每层之后跟随 \(\tanh\)。我们附加归一化的块密度 \(d=\mathrm{nnz}/256\)，为最终的 \(129\to7\) 层提供 129 个输入。该层为 COO、CSR、ELL、HYB、DRW、DCL 和 DNS 生成 logits，不使用激活函数。训练时对这些 logits 应用 softmax 交叉熵；推理时选择 argmax。"#
        let settings = SettingsStore()
        let model = TranslationModel(settings: settings)
        model.preparePreview(
            source: source,
            result: result,
            targetLanguage: .simplifiedChinese,
            detectedLanguage: .english
        )

        let host = NSHostingView(rootView: TranslationView(
            model: model,
            settings: settings,
            openSettings: {},
            close: {}
        ))
        host.frame = NSRect(x: 0, y: 0, width: 840, height: 470)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: representation)
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))

        if let snapshotPath = ProcessInfo.processInfo.environment["RIFF_SNAPSHOT_PATH"] {
            try data.write(to: URL(fileURLWithPath: snapshotPath), options: .atomic)
        }

        let leftText = RichTextRenderer.render(
            source,
            syntax: .markdownAndMath,
            fontSize: 17,
            textColor: .labelColor
        ).string
        XCTAssertTrue(leftText.contains("2 × 2 × 128"))
        XCTAssertFalse(leftText.contains(#"\times"#))
    }
}

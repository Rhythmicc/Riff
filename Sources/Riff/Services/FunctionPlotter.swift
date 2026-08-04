import Foundation

struct FunctionPlotData: Sendable {
    struct Sample: Sendable {
        let x: Double
        let y: Double
    }

    let minimumX = -10.0
    let maximumX = 10.0
    let minimumY: Double
    let maximumY: Double
    let samples: [Sample]

    init(expression: MathExpression) {
        let count = 640
        let domainMinimum = -10.0
        let domainMaximum = 10.0
        let generatedSamples = (0...count).map { index in
            let x = domainMinimum
                + (domainMaximum - domainMinimum) * Double(index) / Double(count)
            return Sample(x: x, y: expression.evaluate(x: x))
        }
        samples = generatedSamples

        let finiteValues = generatedSamples
            .lazy
            .map(\.y)
            .filter { $0.isFinite && abs($0) < 1_000_000 }
            .sorted()
        guard !finiteValues.isEmpty else {
            minimumY = -1
            maximumY = 1
            return
        }

        let lowerIndex = Int(Double(finiteValues.count - 1) * 0.02)
        let upperIndex = Int(Double(finiteValues.count - 1) * 0.98)
        var low = finiteValues[lowerIndex]
        var high = finiteValues[upperIndex]
        if low == high {
            low -= max(1, abs(low) * 0.25)
            high += max(1, abs(high) * 0.25)
        }
        let padding = max((high - low) * 0.1, 0.2)
        minimumY = low - padding
        maximumY = high + padding
    }

    var ySpan: Double { maximumY - minimumY }
    var formattedMinimumY: String { compact(minimumY) }
    var formattedMaximumY: String { compact(maximumY) }

    func mapX(_ value: Double, width: CGFloat) -> CGFloat {
        CGFloat((value - minimumX) / (maximumX - minimumX)) * width
    }

    func mapY(_ value: Double, height: CGFloat) -> CGFloat {
        height - CGFloat((value - minimumY) / ySpan) * height
    }

    private func compact(_ value: Double) -> String {
        if abs(value) >= 1000 { return String(format: "%.1e", value) }
        if abs(value) >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }
}

enum FunctionPlotter {
    static func plot(_ expression: MathExpression) async -> FunctionPlotData? {
        let task = Task.detached(priority: .userInitiated) { () -> FunctionPlotData? in
            guard !Task.isCancelled else { return nil }
            return FunctionPlotData(expression: expression)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

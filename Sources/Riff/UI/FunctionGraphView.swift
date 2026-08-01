import SwiftUI

struct FunctionGraphCard: View {
    let expression: MathExpression

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("函数图")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LauncherTheme.secondary)
                    Text("y = \(expression.source)")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(LauncherTheme.primary)
                }
                Spacer()
                Text("−10 ≤ x ≤ 10")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(LauncherTheme.secondary)
            }

            FunctionGraphView(expression: expression)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(LauncherTheme.hairline))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FunctionGraphView: View {
    let expression: MathExpression

    var body: some View {
        let plot = PlotData(expression: expression)
        Canvas(rendersAsynchronously: true) { context, size in
            drawGrid(context: &context, size: size, plot: plot)
            drawCurve(context: &context, size: size, plot: plot)
        }
        .overlay(alignment: .topLeading) {
            Text(plot.formattedMaximumY)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(LauncherTheme.secondary)
                .padding(8)
        }
        .overlay(alignment: .bottomLeading) {
            Text(plot.formattedMinimumY)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(LauncherTheme.secondary)
                .padding(8)
        }
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize, plot: PlotData) {
        var minor = Path()
        for index in 1..<10 {
            let x = size.width * CGFloat(index) / 10
            minor.move(to: CGPoint(x: x, y: 0))
            minor.addLine(to: CGPoint(x: x, y: size.height))
        }
        for index in 1..<8 {
            let y = size.height * CGFloat(index) / 8
            minor.move(to: CGPoint(x: 0, y: y))
            minor.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(minor, with: .color(.white.opacity(0.055)), lineWidth: 0.8)

        var axes = Path()
        let zeroX = plot.mapX(0, width: size.width)
        if zeroX >= 0, zeroX <= size.width {
            axes.move(to: CGPoint(x: zeroX, y: 0))
            axes.addLine(to: CGPoint(x: zeroX, y: size.height))
        }
        let zeroY = plot.mapY(0, height: size.height)
        if zeroY >= 0, zeroY <= size.height {
            axes.move(to: CGPoint(x: 0, y: zeroY))
            axes.addLine(to: CGPoint(x: size.width, y: zeroY))
        }
        context.stroke(axes, with: .color(.white.opacity(0.28)), lineWidth: 1.15)
    }

    private func drawCurve(context: inout GraphicsContext, size: CGSize, plot: PlotData) {
        var path = Path()
        var previousY: Double?
        var penIsDown = false

        for sample in plot.samples {
            guard sample.y.isFinite,
                  sample.y >= plot.minimumY,
                  sample.y <= plot.maximumY else {
                penIsDown = false
                previousY = nil
                continue
            }

            let point = CGPoint(
                x: plot.mapX(sample.x, width: size.width),
                y: plot.mapY(sample.y, height: size.height)
            )
            let discontinuity = previousY.map { abs(sample.y - $0) > plot.ySpan * 0.48 } ?? false
            if !penIsDown || discontinuity {
                path.move(to: point)
                penIsDown = true
            } else {
                path.addLine(to: point)
            }
            previousY = sample.y
        }

        context.addFilter(.shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1))
        context.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.72, green: 0.77, blue: 0.83),
                    Color(red: 0.45, green: 0.53, blue: 0.63)
                ]),
                startPoint: CGPoint(x: 0, y: size.height / 2),
                endPoint: CGPoint(x: size.width, y: size.height / 2)
            ),
            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
        )
    }
}

private struct PlotData {
    struct Sample {
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
            let x = domainMinimum + (domainMaximum - domainMinimum) * Double(index) / Double(count)
            return Sample(x: x, y: expression.evaluate(x: x))
        }
        samples = generatedSamples

        let finiteValues = generatedSamples.map(\.y).filter { $0.isFinite && abs($0) < 1_000_000 }.sorted()
        if finiteValues.isEmpty {
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

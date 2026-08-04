import SwiftUI

struct FunctionGraphCard: View {
    let expression: MathExpression
    let plot: FunctionPlotData

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("函数图")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LauncherTheme.secondary)
                    Text(expression.displayEquation)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(LauncherTheme.primary)
                }
                Spacer()
                Text("−10 ≤ x ≤ 10")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(LauncherTheme.secondary)
            }

            FunctionGraphView(plot: plot)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LauncherTheme.tileSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(LauncherTheme.hairline))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FunctionGraphView: View {
    let plot: FunctionPlotData

    var body: some View {
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

    private func drawGrid(context: inout GraphicsContext, size: CGSize, plot: FunctionPlotData) {
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
        context.stroke(minor, with: .color(LauncherTheme.hairline.opacity(0.72)), lineWidth: 0.8)

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
        context.stroke(axes, with: .color(LauncherTheme.secondary.opacity(0.56)), lineWidth: 1.15)
    }

    private func drawCurve(context: inout GraphicsContext, size: CGSize, plot: FunctionPlotData) {
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

        context.addFilter(.shadow(color: LauncherTheme.secondary.opacity(0.24), radius: 3, x: 0, y: 1))
        context.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [
                    LauncherTheme.accent.opacity(0.72),
                    LauncherTheme.accent
                ]),
                startPoint: CGPoint(x: 0, y: size.height / 2),
                endPoint: CGPoint(x: size.width, y: size.height / 2)
            ),
            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
        )
    }
}

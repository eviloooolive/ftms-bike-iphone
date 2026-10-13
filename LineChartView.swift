import SwiftUI

/// 纯 SwiftUI Canvas 绘制的实时折线图（不依赖任何第三方图表库）。
struct LineChartView: View {
    let title: String
    let data: [Double]
    let color: Color
    let unit: String

    private var current: String {
        guard let last = data.last else { return "--" }
        return String(format: "%.1f", last)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("\(current) \(unit)").font(.caption.bold())
            }
            Canvas { context, size in
                guard data.count > 1 else { return }
                let w = size.width
                let h = size.height
                let pad: CGFloat = 4
                let maxV = data.max() ?? 1
                let minV = data.min() ?? 0
                let range = (maxV - minV) == 0 ? 1.0 : (maxV - minV)
                let stepX = w / CGFloat(data.count - 1)
                var path = Path()
                for (i, v) in data.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = h - pad - CGFloat((v - minV) / range) * (h - 2 * pad)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(color), lineWidth: 2)
            }
            .frame(height: 90)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(8)
        }
    }
}

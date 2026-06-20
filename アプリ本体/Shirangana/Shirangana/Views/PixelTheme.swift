import SwiftUI

enum PixelTheme {
    static let background = Color(red: 0.94, green: 0.88, blue: 0.72)
    static let paper = Color(red: 1.00, green: 0.97, blue: 0.84)
    static let ink = Color(red: 0.10, green: 0.11, blue: 0.22)
    static let red = Color(red: 0.66, green: 0.13, blue: 0.18)
    static let gold = Color(red: 0.91, green: 0.67, blue: 0.20)
    static let blue = Color(red: 0.13, green: 0.42, blue: 0.49)
    static let shadow = Color(red: 0.25, green: 0.13, blue: 0.20)

    static func font(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

struct PixelPanel: ViewModifier {
    var fill: Color = PixelTheme.paper
    var stroke: Color = PixelTheme.ink
    var lineWidth: CGFloat = 3
    var shadowSize: CGFloat = 5

    func body(content: Content) -> some View {
        content
            .background {
                Rectangle()
                    .fill(fill)
                    .shadow(
                        color: PixelTheme.shadow,
                        radius: 0,
                        x: shadowSize,
                        y: shadowSize
                    )
            }
            .overlay {
                Rectangle()
                    .stroke(stroke, lineWidth: lineWidth)
            }
    }
}

extension View {
    func pixelPanel(
        fill: Color = PixelTheme.paper,
        stroke: Color = PixelTheme.ink,
        lineWidth: CGFloat = 3,
        shadowSize: CGFloat = 5
    ) -> some View {
        modifier(
            PixelPanel(
                fill: fill,
                stroke: stroke,
                lineWidth: lineWidth,
                shadowSize: shadowSize
            )
        )
    }
}

struct RetroScanlines: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for y in stride(from: 0.0, through: size.height, by: 6.0) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.black.opacity(0.13)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

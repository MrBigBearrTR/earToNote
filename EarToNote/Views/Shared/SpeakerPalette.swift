import SwiftUI

enum SpeakerPalette {
    private static let colors: [Color] = [
        .blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown, .red, .mint, .cyan, .yellow,
    ]

    static func color(for number: Int?) -> Color {
        guard let number else { return .gray }
        let count = colors.count
        return colors[((number - 1) % count + count) % count]
    }
}

struct SpeakerDot: View {
    let number: Int?
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(SpeakerPalette.color(for: number))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

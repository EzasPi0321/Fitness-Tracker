import SwiftUI

/// Activity-style ring. Progress beyond 1.0 draws a second lap in the warning colour.
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 14
    var tint: Color = Theme.calories
    var overflowTint: Color = Theme.over

    var body: some View {
        let value = progress.isFinite ? max(0, progress) : 0
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(value, 1))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if value > 1 {
                Circle()
                    .trim(from: 0, to: min(value - 1, 1))
                    .stroke(overflowTint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .black.opacity(0.25), radius: 2)
            }
        }
        .padding(lineWidth / 2)
        .animation(.spring(duration: 0.6), value: value)
    }
}

#Preview {
    HStack(spacing: 24) {
        ProgressRing(progress: 0.65).frame(width: 120, height: 120)
        ProgressRing(progress: 1.2).frame(width: 120, height: 120)
    }
    .padding()
}

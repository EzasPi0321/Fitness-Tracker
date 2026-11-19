import SwiftUI

extension Macro {
    var color: Color {
        switch self {
        case .protein: .blue
        case .carbs: .orange
        case .fat: .purple
        }
    }
}

enum Theme {
    static let calories = Color.green
    static let over = Color.orange
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let screenBackground = Color(.systemGroupedBackground)
}

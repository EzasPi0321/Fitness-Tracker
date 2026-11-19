import Foundation

enum MealType: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snacks"
        }
    }

    var symbolName: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "carrot.fill"
        }
    }

    /// A sensible default meal for the given time of day.
    static func suggested(for date: Date, calendar: Calendar = .current) -> MealType {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}

enum EntrySource: String, Codable, Sendable {
    case barcode, photoAI, manual, customFood

    var symbolName: String {
        switch self {
        case .barcode: "barcode"
        case .photoAI: "sparkles"
        case .manual: "square.and.pencil"
        case .customFood: "star.fill"
        }
    }
}

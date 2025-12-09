import Foundation
import SwiftData

@Model
final class Meal: Identifiable {
    var id: UUID = UUID()
    var name: String

    // one-to-many relationship: Meal -> [FoodEntry]
    @Relationship var entries: [FoodEntry] = []

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    // computed helpers for UI convenience
    var totalCalories: Int {
        entries.reduce(0) { $0 + $1.calories }
    }
    var totalProtein: Double {
        entries.reduce(0.0) { $0 + ($1.protein ?? 0.0) }
    }
    var totalCarbs: Double {
        entries.reduce(0.0) { $0 + ($1.carbs ?? 0.0) }
    }
    var totalFat: Double {                                   // Added totalFat
        entries.reduce(0.0) { $0 + ($1.fat ?? 0.0) }
    }
}

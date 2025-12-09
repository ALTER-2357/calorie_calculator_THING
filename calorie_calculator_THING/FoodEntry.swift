import Foundation
import SwiftData

@Model
final class FoodEntry: Identifiable {
    var id: UUID = UUID()
    var name: String
    var calories: Int
    var protein: Double?
    var carbs: Double?
    var fat: Double?          // Added fat tracking (grams)
    var timestamp: Date
    var servingSize: String?
    var servings: Double?
    var barcode: String?

    // relationship back to a Meal (many-to-one)
    @Relationship(inverse: \Meal.entries) var meal: Meal?

    init(
        id: UUID = UUID(),
        name: String,
        calories: Int,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        timestamp: Date = Date(),
        servingSize: String? = nil,
        servings: Double? = nil,
        barcode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.timestamp = timestamp
        self.servingSize = servingSize
        self.servings = servings
        self.barcode = barcode
    }
}

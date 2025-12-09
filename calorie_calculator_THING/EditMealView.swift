//
//  EditMealView.swift
//  calorie_calculator_THING
//
//  Created by lewis mills on 09/12/2025.
//


import SwiftUI
import SwiftData

// Optional convenience view if you want a separate EditMealView instead of using AddMealView(editingMeal:)
// This file shows how you could present a dedicated meal editor that reuses AddMealView's behavior.
struct EditMealView: View {
    @Environment(\.dismiss) private var dismiss

    let meal: Meal
    let entries: [FoodEntry]
    let onSave: (Meal, String, [FoodEntry]) -> Void

    var body: some View {
        AddMealView(entries: entries, initialSelectedIDs: Set(meal.entries.map { $0.id }), editingMeal: meal) { name, chosen, editing in
            // convert AddMealView callback to an update call
            onSave(meal, name, chosen)
            dismiss()
        }
    }
}
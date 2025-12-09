//
//  calorie_calculator_THINGApp.swift
//  calorie_calculator_THING
//
//  Created by lewis mills on 09/12/2025.
//

import SwiftUI
import SwiftData

@main
struct calorie_calculator_THINGApp: App {
    // Persistent ModelContainer used by the app (constructed once)
    let container: ModelContainer

    init() {
        do {
            // Pass model types as variadic arguments (not as an array)
            container = try ModelContainer(for: FoodEntry.self, Meal.self)

            // Optional: seed sample data once
            let seededKey = "hasSeededFoodDiaryData_v1"
            if !UserDefaults.standard.bool(forKey: seededKey) {
                let ctx = container.mainContext

                let e1 = FoodEntry(name: "Sample Oatmeal", calories: 300, protein: 8.0, carbs: 54.0, timestamp: Date())
                let e2 = FoodEntry(name: "Sample Coffee", calories: 5, protein: 0.0, carbs: 0.0, timestamp: Date())
                let meal = Meal(name: "Breakfast")
                meal.entries.append(e1)
                meal.entries.append(e2)
                e1.meal = meal
                e2.meal = meal

                ctx.insert(e1)
                ctx.insert(e2)
                ctx.insert(meal)

                do {
                    try ctx.save()
                } catch {
                    // Log but don't crash the app
                    print("Warning: failed to save seed data: \(error)")
                }

                UserDefaults.standard.set(true, forKey: seededKey)
            }
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container) // inject the persistent container into the environment
        }
    }
}

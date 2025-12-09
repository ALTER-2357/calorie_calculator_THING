//
//  EditEntryView.swift
//  calorie_calculator_THING
//
//  Created by lewis mills on 09/12/2025.
//


import SwiftUI
import SwiftData

struct EditEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // The entry to edit (passed in from ContentView.sheet(item:))
    let entry: FoodEntry

    // Called when the user taps "Make it a meal". Parent should present AddMealView prefilled.
    var onMakeMeal: (FoodEntry) -> Void

    // Local editable state
    @State private var name: String = ""
    @State private var date: Date = Date()
    @State private var barcode: String = ""
    @State private var servingSizeText: String? = nil
    @State private var caloriesPerServing: Double? = nil
    @State private var proteinsPerServing: Double? = nil
    @State private var carbsPerServing: Double? = nil
    @State private var servingsText: String = "1"
    @State private var caloriesText: String = ""
    @State private var proteinText: String = ""
    @State private var carbsText: String = ""

    @State private var isLookingUp = false
    @State private var lookupError: String?
    @State private var showInvalidAlert = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("What did you eat?")) {
                    TextField("Name", text: $name)
                }

                Section(header: Text("Barcode lookup (optional)")) {
                    HStack {
                        TextField("Barcode", text: $barcode)
                            .keyboardType(.numberPad)
                        Button(action: lookupBarcode) {
                            if isLookingUp {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Text("Lookup")
                            }
                        }
                        .disabled(barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLookingUp)
                    }

                    if let serving = servingSizeText {
                        HStack {
                            Text("Serving")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(serving)
                        }
                    }

                    if caloriesPerServing != nil || proteinsPerServing != nil || carbsPerServing != nil {
                        VStack(spacing: 6) {
                            if let cal = caloriesPerServing {
                                HStack {
                                    Text("Calories per serving")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(cal, specifier: "%.0f") kcal")
                                }
                            }
                            if let p = proteinsPerServing {
                                HStack {
                                    Text("Protein per serving")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(p, specifier: "%.1f") g")
                                }
                            }
                            if let c = carbsPerServing {
                                HStack {
                                    Text("Carbs per serving")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(c, specifier: "%.1f") g")
                                }
                            }
                        }
                    }

                    if let err = lookupError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section(header: Text("Servings / Totals")) {
                    if caloriesPerServing != nil || proteinsPerServing != nil || carbsPerServing != nil {
                        TextField("Servings (e.g. 1, 0.5)", text: $servingsText)
                            .keyboardType(.decimalPad)
                    } else {
                        TextField("Calories (total)", text: $caloriesText)
                            .keyboardType(.numberPad)
                        TextField("Protein (g)", text: $proteinText)
                            .keyboardType(.decimalPad)
                        TextField("Carbs (g)", text: $carbsText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section(header: Text("When")) {
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }

                Section {
                    Button("Make it a meal") {
                        // Dismiss edit sheet first, then instruct parent to present AddMealView prefilled for this entry.
                        dismiss()
                        DispatchQueue.main.async {
                            onMakeMeal(entry)
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Text("Delete Entry")
                    }
                }
            }
            .navigationTitle("Edit Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTapped()
                    }
                }
            }
            .alert("Invalid entry", isPresented: $showInvalidAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please enter a name and a valid calorie value.")
            }
            .confirmationDialog("Are you sure you want to delete this entry?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    deleteEntry()
                }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear {
                // Initialize local state from the model entry once
                name = entry.name
                date = entry.timestamp
                barcode = entry.barcode ?? ""
                servingSizeText = entry.servingSize
                if let s = entry.servings {
                    servingsText = String(s)
                } else {
                    servingsText = "1"
                }
                caloriesText = String(entry.calories)
                proteinText = entry.protein != nil ? String(entry.protein!) : ""
                carbsText = entry.carbs != nil ? String(entry.carbs!) : ""
            }
        }
    }

    private func lookupBarcode() {
        lookupError = nil
        caloriesPerServing = nil
        proteinsPerServing = nil
        carbsPerServing = nil
        servingSizeText = nil
        isLookingUp = true

        Task {
            do {
                let info = try await OpenFoodFactsClient.fetchProduct(barcode: barcode)
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let productName = info.productName {
                    name = productName
                }
                servingSizeText = info.servingSize
                caloriesPerServing = info.caloriesPerServing
                proteinsPerServing = info.proteinsPerServing
                carbsPerServing = info.carbsPerServing
                servingsText = "1"
            } catch OpenFoodFactsError.productNotFound {
                lookupError = "Product not found."
            } catch {
                lookupError = "Lookup failed."
            }
            isLookingUp = false
        }
    }

    private func saveTapped() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            showInvalidAlert = true
            return
        }

        // Compute totals
        var totalCalories: Int = 0
        var totalProtein: Double? = nil
        var totalCarbs: Double? = nil

        if caloriesPerServing != nil || proteinsPerServing != nil || carbsPerServing != nil {
            let parsed = Double(servingsText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1.0
            if let calPer = caloriesPerServing {
                totalCalories = Int(round(calPer * parsed))
            } else {
                totalCalories = 0
            }
            if let pPer = proteinsPerServing {
                totalProtein = pPer * parsed
            }
            if let cPer = carbsPerServing {
                totalCarbs = cPer * parsed
            }
        } else {
            let parsedInt = Int(caloriesText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
            guard parsedInt >= 0 else {
                showInvalidAlert = true
                return
            }
            totalCalories = parsedInt
            let p = Double(proteinText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
            let c = Double(carbsText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
            totalProtein = p
            totalCarbs = c
        }

        withAnimation {
            entry.name = trimmedName
            entry.calories = totalCalories
            entry.protein = totalProtein
            entry.carbs = totalCarbs
            entry.timestamp = date
            entry.servingSize = servingSizeText
            entry.servings = Double(servingsText.replacingOccurrences(of: ",", with: ".")) ?? entry.servings
            entry.barcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        dismiss()
    }

    private func deleteEntry() {
        withAnimation {
            modelContext.delete(entry)
        }
        dismiss()
    }
}

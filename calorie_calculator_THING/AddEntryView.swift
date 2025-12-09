//
//  AddEntryView.swift
//  calorie_calculator_THING
//
//  Created by lewis mills on 09/12/2025.
//


import SwiftUI

struct AddEntryView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var caloriesText: String = ""
    @State private var date: Date = Date()

    // Barcode lookup state
    @State private var barcode: String = ""
    @State private var caloriesPerServing: Double? = nil
    @State private var proteinsPerServing: Double? = nil
    @State private var carbsPerServing: Double? = nil
    @State private var servingSizeText: String? = nil
    @State private var servingsText: String = "1"
    @State private var isLookingUp = false
    @State private var lookupError: String?

    // manual protein/carbs if no lookup
    @State private var proteinText: String = ""
    @State private var carbsText: String = ""

    @State private var showInvalidAlert = false

    // called when user saves:
    // (name, calories, protein grams, carbs grams, date, servingSize, servings, barcode)
    var onSave: (String, Int, Double?, Double?, Date, String?, Double?, String?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("What did you eat?")) {
                    TextField("Name (e.g. Breakfast, Apple)", text: $name)
                }

                Section(header: Text("Barcode lookup (optional)")) {
                    HStack {
                        TextField("Barcode (e.g. 7622210449283)", text: $barcode)
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

                    if lookupError != nil {
                        Text(lookupError!)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section(header: Text("Servings / Totals")) {
                    // If we have per-serving values from lookup, allow specifying number of servings.
                    if caloriesPerServing != nil || proteinsPerServing != nil || carbsPerServing != nil {
                        TextField("Servings (e.g. 1, 0.5)", text: $servingsText)
                            .keyboardType(.decimalPad)
                    } else {
                        // manual total input fallback
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
            }
            .navigationTitle("Add Entry")
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
                Text("Please enter a name and valid nutrition values.")
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
                // reset default servings to 1
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

        // Calculate totals:
        var totalCalories: Int = 0
        var totalProtein: Double? = nil
        var totalCarbs: Double? = nil
        var usedServings: Double? = nil

        if caloriesPerServing != nil || proteinsPerServing != nil || carbsPerServing != nil {
            // prefer per-serving numbers where available
            let parsed = Double(servingsText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1.0
            usedServings = parsed
            if let calPer = caloriesPerServing {
                totalCalories = Int(round(calPer * parsed))
            } else {
                // if calories per serving not available but protein / carbs are, leave calories 0 or try to approximate -- for simplicity set 0
                totalCalories = 0
            }
            if let pPer = proteinsPerServing {
                totalProtein = pPer * parsed
            }
            if let cPer = carbsPerServing {
                totalCarbs = cPer * parsed
            }
        } else {
            // manual input
            let parsedCal = Int(caloriesText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
            guard parsedCal >= 0 else {
                showInvalidAlert = true
                return
            }
            totalCalories = parsedCal

            let p = Double(proteinText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
            let c = Double(carbsText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
            totalProtein = p
            totalCarbs = c
        }

        onSave(trimmedName, totalCalories, totalProtein, totalCarbs, date, servingSizeText, usedServings, barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : barcode.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

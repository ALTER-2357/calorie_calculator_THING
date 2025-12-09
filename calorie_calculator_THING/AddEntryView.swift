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
    @State private var fatPerServing: Double? = nil
    @State private var servingSizeText: String? = nil
    @State private var servingsText: String = "1"
    @State private var isLookingUp = false
    @State private var lookupError: String?
    @State private var showingScanner: Bool = false
 
    // manual protein/carbs/fat if no lookup or to override
    @State private var proteinText: String = ""
    @State private var carbsText: String = ""
    @State private var fatText: String = ""
 
    @State private var showInvalidAlert = false
 
    // called when user saves:
    // (name, calories, protein grams, carbs grams, fat grams, date, servingSize, servings, barcode)
    var onSave: (String, Int, Double?, Double?, Double?, Date, String?, Double?, String?) -> Void
 
    var body: some View {
        NavigationStack {
            Form {
                // Combined "What did you eat?" + scan/lookup controls
                Section(header: Text("What did you eat?")) {
                    HStack(spacing: 8) {
                        TextField("Name (e.g. Breakfast, Apple)", text: $name)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
 
                        // Scan button - opens camera scanner sheet
                        Button(action: { showingScanner = true }) {
                            Image(systemName: "barcode.viewfinder")
                                .imageScale(.large)
                        }
                        .help("Scan barcode")
 
                        // Lookup button - triggers lookup of scanned barcode
                        Button(action: lookupBarcode) {
                            if isLookingUp {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                        .disabled(barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLookingUp)
                    }
 
                    // Show scanned barcode (read-only). End-user doesn't type barcodes.
    
                    if let serving = servingSizeText {
                        HStack {
                            Text("Serving")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(serving)
                        }
                    }
 
                    if caloriesPerServing != nil || proteinsPerServing != nil || carbsPerServing != nil || fatPerServing != nil {
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
                            if let f = fatPerServing {
                                HStack {
                                    Text("Fat per serving")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(f, specifier: "%.1f") g")
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
                    // If we have per-serving values from lookup, allow specifying number of servings.
                    if caloriesPerServing != nil || proteinsPerServing != nil || carbsPerServing != nil || fatPerServing != nil {
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
                        TextField("Fat (g)", text: $fatText)
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
            // scanner sheet (uses your existing BarcodeScannerView)
            .sheet(isPresented: $showingScanner) {
                NavigationStack {
                    BarcodeScannerView { result in
                        switch result {
                        case .success(let code):
                            // set the barcode and auto-lookup
                            barcode = code
                            showingScanner = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                lookupBarcode()
                            }
                        case .failure(let err):
                            lookupError = {
                                switch err {
                                case .permissionDenied:
                                    return "Camera permission denied."
                                case .badInput:
                                    return "Scanner setup failed."
                                case .noData:
                                    return "No barcode found. Try again."
                                case .other:
                                    return "Scanning failed."
                                }
                            }()
                            showingScanner = false
                        }
                    }
                    .ignoresSafeArea()
                    .navigationTitle("Scan Barcode")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingScanner = false }
                        }
                    }
                }
            }
        }
    }
 
    private func lookupBarcode() {
        lookupError = nil
        caloriesPerServing = nil
        proteinsPerServing = nil
        carbsPerServing = nil
        fatPerServing = nil
        servingSizeText = nil
        isLookingUp = true
 
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            lookupError = "Scan a barcode first."
            isLookingUp = false
            return
        }
 
        Task {
            do {
                let info = try await OpenFoodFactsClient.fetchProduct(barcode: trimmed)
 
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let productName = info.productName {
                    name = productName
                }
 
                servingSizeText = info.servingSize
                caloriesPerServing = info.caloriesPerServing
                proteinsPerServing = info.proteinsPerServing
                carbsPerServing = info.carbsPerServing
                fatPerServing = info.fatPerServing
 
                if let fPer = fatPerServing, fatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    fatText = String(format: "%.1f", fPer)
                }
 
                servingsText = "1"
            } catch OpenFoodFactsError.productNotFound {
                lookupError = "Product not found."
            } catch {
                lookupError = "Lookup failed."
            }
            isLookingUp = false
        }
    }
 
    private func parseDouble(_ s: String) -> Double? {
        let cleaned = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return nil }
        return Double(cleaned)
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
        var totalFat: Double? = nil
        var usedServings: Double? = nil
 
        if caloriesPerServing != nil || proteinsPerServing != nil || carbsPerServing != nil || fatPerServing != nil {
            // prefer per-serving numbers where available
            let parsed = Double(servingsText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1.0
            usedServings = parsed
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
 
            // fat: prefer user-entered fat override; otherwise use fatPerServing if available
            if let fOverride = parseDouble(fatText) {
                totalFat = fOverride
            } else if let fPer = fatPerServing {
                totalFat = fPer * parsed
            } else {
                totalFat = nil
            }
        } else {
            // manual input
            let parsedCal = Int(caloriesText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
            guard parsedCal >= 0 else {
                showInvalidAlert = true
                return
            }
            totalCalories = parsedCal
 
            totalProtein = parseDouble(proteinText) ?? 0.0
            totalCarbs = parseDouble(carbsText) ?? 0.0
            totalFat = parseDouble(fatText)
        }
 
        onSave(
            trimmedName,
            totalCalories,
            totalProtein,
            totalCarbs,
            totalFat,
            date,
            servingSizeText,
            usedServings,
            barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        dismiss()
    }
}

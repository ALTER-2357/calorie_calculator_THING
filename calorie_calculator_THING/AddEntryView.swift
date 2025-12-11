//
//  AddEntryView.swift
//  calorie_calculator_THING
//
//  Created by lewis mills on 09/12/2025.
//
//  Reworked local search to fix incorrect selection when duplicate names exist,
//  improve matching (exact > prefix > contains), normalize comparisons,
//  make suggestion rows uniquely identifiable, disable scanner while suggestions
//  are visible, and hide suggestions when the name field loses focus.
//  Adjusted hit areas so the barcode button no longer captures taps outside its
//  visible bounds and nutrition rows are not treated as tappable scanner zones.
//

import SwiftUI

struct AddEntryView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var caloriesText: String = ""
    @State private var date: Date = Date()

    // Barcode lookup state
    @State private var barcode: String = ""
    @State private var productName: String? = nil

    // per-serving values (may be nil)
    @State private var caloriesPerServing: Double? = nil
    @State private var proteinsPerServing: Double? = nil
    @State private var carbsPerServing: Double? = nil
    @State private var fatPerServing: Double? = nil
    @State private var servingSizeText: String? = nil

    // per-100g values (may be nil)
    @State private var caloriesPer100g: Double? = nil
    @State private var proteinsPer100g: Double? = nil
    @State private var carbsPer100g: Double? = nil
    @State private var fatPer100g: Double? = nil

    @State private var servingsText: String = "1"
    @State private var gramsText: String = ""

    @State private var isLookingUp = false
    @State private var lookupError: String?
    @State private var showingScanner: Bool = false

    // manual protein/carbs/fat if no lookup or to override
    @State private var proteinText: String = ""
    @State private var carbsText: String = ""
    @State private var fatText: String = ""

    // Allow user to enter grams instead of servings
    enum AmountMode: String, CaseIterable, Identifiable {
        case servings = "Servings"
        case grams = "Grams"
        var id: String { rawValue }
    }
    @State private var amountMode: AmountMode = .servings

    @State private var showInvalidAlert = false
    @State private var invalidMessage: String = "Please enter a name and valid nutrition values."

    // called when user saves:
    // (name, calories, protein grams, carbs grams, fat grams, date, servingSize, servings, barcode)
    var onSave: (String, Int, Double?, Double?, Double?, Date, String?, Double?, String?) -> Void

    // MARK: - Local JSON search state
    @State private var localProducts: [LocalProduct] = []
    @State private var searchResults: [LocalProduct] = []
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                // Product info + scan/lookup
                Section(header: Text("What did you eat?")) {
                    VStack(spacing: 8) {
                        // Improved tappable/clickable area for both the search field and the scanner button.
                        // Fixes:
                        //  - Make the TextField background tappable but constrained to its visible area.
                        //  - Make the barcode button use a fixed 44x44 hit target so it doesn't capture taps
                        //    outside its visible bounds (no invisible vertical/horizontal extension).
                        HStack(spacing: 8) {
                            // Wrap the TextField to ensure its background is only as large as the field itself.
                            TextField("Name (e.g. Breakfast, Apple)", text: $name)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                                .focused($nameFieldFocused)
                                .onChange(of: name) { _ in
                                    updateSearchResults()
                                }
                                .onChange(of: nameFieldFocused) { focused in
                                    // Delay hiding suggestions slightly so a tap on a suggestion
                                    // has a chance to run its action before the array is cleared.
                                    if !focused {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            // only clear if focus still hasn't returned
                                            if !nameFieldFocused {
                                                searchResults = []
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 10) // make the field taller for easier taps
                                .padding(.horizontal, 8)
                                .background(Color(UIColor.tertiarySystemBackground))
                                .cornerRadius(8)
                                // ensure the textfield expands to take remaining width but doesn't overlap the button
                                .frame(maxWidth: .infinity)
                                // Tapping the visible field area focuses it.
                                .onTapGesture {
                                    nameFieldFocused = true
                                }

                            // Barcode button: fixed hit area (44x44) per HIG
                            // Key: set an explicit frame and contentShape so the tappable area is exactly this rectangle.
                            Button(action: {
                                showingScanner = true
                            }) {
                                Image(systemName: "barcode.viewfinder")
                                    .imageScale(.large)
                                    .frame(width: 24, height: 24) // icon visible size
                            }
                            .buttonStyle(.plain)
                            .frame(width: 44, height: 44) // fixed interactive area
                            .contentShape(Rectangle())     // hit-test restricted to this rectangle
                            .help("Scan barcode")
                            .disabled(!searchResults.isEmpty)
                            .opacity(!searchResults.isEmpty ? 0.5 : 1.0)
                            .accessibilityLabel("Scan barcode")
                            .accessibilityHint(searchResults.isEmpty ? "Opens barcode scanner" : "Disabled while suggestions are visible")
                        }
                        // Add a little padding so the tappable area doesn't feel cramped inside the form row
                        .padding(.vertical, 2)

                        // suggestions from local JSON (only visible while typing)
                        if !searchResults.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                // Use id: \.id so each row is uniquely identified (helps duplicates)
                                ForEach(searchResults, id: \.id) { product in
                                    // Use a plain button and capture the product value directly.
                                    Button(action: {
                                        // select the captured product instance
                                        selectLocalProduct(product)
                                        // hide suggestions and dismiss keyboard after selection
                                        DispatchQueue.main.async {
                                            searchResults = []
                                            nameFieldFocused = false
                                        }
                                    }) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(product.name)
                                                    .foregroundColor(.primary)
                                                HStack(spacing: 8) {
                                                    if let cal = product.calories {
                                                        Text("\(Int(cal)) kcal")
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    if let protein = product.protein {
                                                        Text("\(String(format: "%.0f", protein)) g protein")
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    if let summary = product.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                        Text(summary)
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                            .lineLimit(1)
                                                    }
                                                }
                                            }
                                            Spacer()
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 6)
                                        // ensure the full row is tappable (including padding area)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    if product.id != searchResults.last?.id {
                                        Divider()
                                    }
                                }
                            }
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(8)
                        }

                        // show product name / barcode
                        if let product = productName {
                            HStack {
                                Text("Product")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(product)
                                    .multilineTextAlignment(.trailing)
                            }
                        }

                        if let serving = servingSizeText {
                            HStack {
                                Text("Serving")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(serving)
                            }
                        }

                        // Show available nutrition data
                        // NOTE: these are plain HStacks (not buttons) so they won't capture taps that would
                        // otherwise be delivered to other interactive elements. This avoids accidental
                        // activation of the barcode scanner when tapping nutrition rows.
                        if hasLookupData {
                            VStack(spacing: 8) {
                                if let calS = caloriesPerServing {
                                    HStack {
                                        Text("Calories per serving")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(calS, specifier: "%.0f") kcal")
                                    }
                                }
                                if let cal100 = caloriesPer100g {
                                    HStack {
                                        Text("Calories per 100 g")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(cal100, specifier: "%.0f") kcal")
                                    }
                                }
                                if let p = proteinsPerServing {
                                    HStack {
                                        Text("Protein per serving")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(p, specifier: "%.1f") g")
                                    }
                                } else if let p100 = proteinsPer100g {
                                    HStack {
                                        Text("Protein per 100 g")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(p100, specifier: "%.1f") g")
                                    }
                                }
                                if let c = carbsPerServing {
                                    HStack {
                                        Text("Carbs per serving")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(c, specifier: "%.1f") g")
                                    }
                                } else if let c100 = carbsPer100g {
                                    HStack {
                                        Text("Carbs per 100 g")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(c100, specifier: "%.1f") g")
                                    }
                                }
                                if let f = fatPerServing {
                                    HStack {
                                        Text("Fat per serving")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(f, specifier: "%.1f") g")
                                    }
                                } else if let f100 = fatPer100g {
                                    HStack {
                                        Text("Fat per 100 g")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(f100, specifier: "%.1f") g")
                                    }
                                }
                            }
                            // NOTE: remove contentShape that could make the whole grey block act like a tappable area.
                            // Previously .contentShape(Rectangle()) here could cause taps inside the rounded container to be
                            // interpreted as hitting other interactive elements; leaving it off avoids accidental scanner activation.
                        }

                        if let err = lookupError {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                Section(header: Text("Amount")) {
                    if hasLookupData {
                        let hasServingOption = parseServingGrams(from: servingSizeText) != nil
                            || (caloriesPerServing != nil || proteinsPerServing != nil || carbsPerServing != nil || fatPerServing != nil)

                        if !hasServingOption {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Grams (e.g. 100, 50)", text: $gramsText)
                                    .keyboardType(.decimalPad)
                                Text("Calculated totals from grams:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                let totals = totalsForGrams()
                                HStack {
                                    Text("Calories")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(totals.calories) kcal")
                                }
                                if let p = totals.protein {
                                    HStack {
                                        Text("Protein")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(p, specifier: "%.1f") g")
                                    }
                                }
                                if let c = totals.carbs {
                                    HStack {
                                        Text("Carbs")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(c, specifier: "%.1f") g")
                                    }
                                }
                                if let f = totals.fat {
                                    HStack {
                                        Text("Fat")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(f, specifier: "%.1f") g")
                                    }
                                }

                                if parseServingGrams(from: servingSizeText) == nil &&
                                    (caloriesPer100g == nil && proteinsPer100g == nil && carbsPer100g == nil && fatPer100g == nil) {
                                    Text("No serving weight known — totals computed from per-serving where possible, otherwise from available per-100 g values.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Picker("Amount type", selection: $amountMode) {
                                Text(AmountMode.servings.rawValue).tag(AmountMode.servings)
                                Text(AmountMode.grams.rawValue).tag(AmountMode.grams)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: amountMode) { new in
                                if new == .grams && !canComputeFromGrams() {
                                    amountMode = .servings
                                    lookupError = "Cannot use grams for this product (no per-100g and no serving weight in grams)."
                                } else {
                                    lookupError = nil
                                }
                            }

                            if amountMode == .servings {
                                TextField("Servings (e.g. 1, 0.5)", text: $servingsText)
                                    .keyboardType(.decimalPad)

                                let totals = totalsForServings()
                                HStack {
                                    Text("Calories")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(totals.calories) kcal")
                                }
                                if let p = totals.protein {
                                    HStack {
                                        Text("Protein")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(p, specifier: "%.1f") g")
                                    }
                                }
                                if let c = totals.carbs {
                                    HStack {
                                        Text("Carbs")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(c, specifier: "%.1f") g")
                                    }
                                }
                                if let f = totals.fat {
                                    HStack {
                                        Text("Fat")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(f, specifier: "%.1f") g")
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("Grams (e.g. 100, 50)", text: $gramsText)
                                        .keyboardType(.decimalPad)
                                    Text("Calculated totals from grams:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    let totals = totalsForGrams()
                                    HStack {
                                        Text("Calories")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(totals.calories) kcal")
                                    }
                                    if let p = totals.protein {
                                        HStack {
                                            Text("Protein")
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text("\(p, specifier: "%.1f") g")
                                        }
                                    }
                                    if let c = totals.carbs {
                                        HStack {
                                            Text("Carbs")
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text("\(c, specifier: "%.1f") g")
                                        }
                                    }
                                    if let f = totals.fat {
                                        HStack {
                                            Text("Fat")
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text("\(f, specifier: "%.1f") g")
                                        }
                                    }

                                    if let grams = parseDouble(gramsText), let gramsPerServing = parseServingGrams(from: servingSizeText) {
                                        let eqServings = grams / gramsPerServing
                                        HStack {
                                            Text("Equivalent servings")
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text("\(eqServings, specifier: "%.2f")")
                                        }
                                    } else if parseDouble(gramsText) != nil && parseServingGrams(from: servingSizeText) == nil {
                                        Text("No serving weight known — totals computed from per-100g if available.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } else {
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
            .onChange(of: servingSizeText) { new in
                if parseServingGrams(from: new) == nil
                    && (caloriesPerServing == nil && proteinsPerServing == nil && carbsPerServing == nil && fatPerServing == nil) {
                    amountMode = .grams
                }
            }
            .onAppear {
                loadLocalProducts()
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
                    .disabled(!isSaveAllowed())
                }
            }
            .alert("Invalid entry", isPresented: $showInvalidAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(invalidMessage)
            }
            .sheet(isPresented: $showingScanner) {
                NavigationStack {
                    BarcodeScannerView { result in
                        switch result {
                        case .success(let code):
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

    // MARK: - Local JSON product model & loader

    private struct LocalProductsRoot: Codable {
        let data: [LocalProduct]
    }

    private struct LocalProduct: Codable, Identifiable {
        // id is generated when decoding so each decoded instance is uniquely identifiable
        let id: UUID
        let name: String
        let summary: String?
        let ingredients: String?
        let calories: Double?
        let fat: Double?
        let saturated_fat: Double?
        let carbohydrates: Double?
        let sugar: Double?
        let fibre: Double?
        let protein: Double?
        let salt: Double?

        private enum CodingKeys: String, CodingKey {
            case name, summary, ingredients, calories, fat, saturated_fat, carbohydrates, sugar, fibre, protein, salt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            summary = try container.decodeIfPresent(String.self, forKey: .summary)
            ingredients = try container.decodeIfPresent(String.self, forKey: .ingredients)
            calories = try container.decodeIfPresent(Double.self, forKey: .calories)
            fat = try container.decodeIfPresent(Double.self, forKey: .fat)
            saturated_fat = try container.decodeIfPresent(Double.self, forKey: .saturated_fat)
            carbohydrates = try container.decodeIfPresent(Double.self, forKey: .carbohydrates)
            sugar = try container.decodeIfPresent(Double.self, forKey: .sugar)
            fibre = try container.decodeIfPresent(Double.self, forKey: .fibre)
            protein = try container.decodeIfPresent(Double.self, forKey: .protein)
            salt = try container.decodeIfPresent(Double.self, forKey: .salt)
            id = UUID()
        }
    }

    private func loadLocalProducts() {
        guard let url = Bundle.main.url(forResource: "json", withExtension: "json") else {
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let root = try JSONDecoder().decode(LocalProductsRoot.self, from: data)
            // sort alphabetically for stable ordering
            localProducts = root.data.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            print("Failed to load local products: \(error)")
        }
    }

    // Normalize strings for comparison: remove diacritics, lowercase, trim
    private func normalized(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateSearchResults() {
        let q = normalized(name)
        guard !q.isEmpty else {
            searchResults = []
            return
        }

        // Filter products by normalized name contains
        var filtered = localProducts.filter { normalized($0.name).contains(q) }

        // Sort: exact match first, then prefix matches, then contains; tie-breaker shorter name first
        filtered.sort { a, b in
            let an = normalized(a.name)
            let bn = normalized(b.name)

            // exact match preference
            let aExact = (an == q)
            let bExact = (bn == q)
            if aExact != bExact { return aExact }

            // prefix preference
            let aPrefix = an.hasPrefix(q)
            let bPrefix = bn.hasPrefix(q)
            if aPrefix != bPrefix { return aPrefix }

            // fallback: shorter name first
            if a.name.count != b.name.count { return a.name.count < b.name.count }

            // stable: alphabetical
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        if filtered.count > 10 { filtered = Array(filtered.prefix(10)) }
        searchResults = filtered
    }

    private func selectLocalProduct(_ p: LocalProduct) {
        // Use the exact product instance selected
        name = p.name
        productName = p.name

        // Fill per-serving fields from the JSON product where available
        caloriesPerServing = p.calories
        proteinsPerServing = p.protein
        carbsPerServing = p.carbohydrates
        fatPerServing = p.fat

        // clear any per-100g derived values; the JSON doesn't provide per-100g
        caloriesPer100g = nil
        proteinsPer100g = nil
        carbsPer100g = nil
        fatPer100g = nil

        // Set servings to 1 and switch to servings mode so user can immediately save or adjust servings.
        servingsText = "1"
        amountMode = .servings

        // reset grams input
        gramsText = ""
        lookupError = nil

        // Ensure scanner is not presented and clear barcode to avoid accidental lookup interactions
        showingScanner = false
        barcode = ""
    }

    // MARK: - Lookup

    private var hasLookupData: Bool {
        return caloriesPerServing != nil || proteinsPerServing != nil || carbsPerServing != nil || fatPerServing != nil || caloriesPer100g != nil || proteinsPer100g != nil || carbsPer100g != nil || fatPer100g != nil
    }

    private func lookupBarcode() {
        lookupError = nil
        productName = nil

        caloriesPerServing = nil
        proteinsPerServing = nil
        carbsPerServing = nil
        fatPerServing = nil
        caloriesPer100g = nil
        proteinsPer100g = nil
        carbsPer100g = nil
        fatPer100g = nil
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

                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let product = info.productName {
                    name = product
                }
                productName = info.productName

                // assign both per-serving and per-100g fields directly from API model
                caloriesPerServing = info.caloriesPerServing
                proteinsPerServing = info.proteinsPerServing
                carbsPerServing = info.carbsPerServing
                fatPerServing = info.fatPerServing

                caloriesPer100g = info.caloriesPer100g
                proteinsPer100g = info.proteinsPer100g
                carbsPer100g = info.carbsPer100g
                fatPer100g = info.fatPer100g

                servingSizeText = info.servingSize

                // If we don't have per-100g but do have per-serving + serving weight in grams, derive per-100g
                derivePer100gIfNeeded()

                // prefill fat override field so user can quickly override if desired
                if let fPer = fatPerServing, fatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    fatText = String(format: "%.1f", fPer)
                }

                servingsText = "1"
                gramsText = ""
                lookupError = nil
            } catch OpenFoodFactsError.productNotFound {
                lookupError = "Product not found."
            } catch {
                lookupError = "Lookup failed."
            }
            isLookingUp = false
        }
    }

    // MARK: - Parsing helpers

    private func parseDouble(_ s: String?) -> Double? {
        guard let s = s else { return nil }
        let cleaned = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return nil }
        return Double(cleaned)
    }

    private func parseServingGrams(from servingText: String?) -> Double? {
        guard let s = servingText else { return nil }
        do {
            let pattern = #"(\d+[.,]?\d*)\s*[gG]\b"#
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            if let match = regex.firstMatch(in: s, options: [], range: range), match.numberOfRanges >= 2 {
                if let rg = Range(match.range(at: 1), in: s) {
                    let numStr = s[rg].replacingOccurrences(of: ",", with: ".")
                    return Double(numStr)
                }
            }
        } catch {
            // ignore regex errors
        }
        return nil
    }

    private func derivePer100gIfNeeded() {
        if (caloriesPer100g == nil || proteinsPer100g == nil || carbsPer100g == nil || fatPer100g == nil),
           let gramsPerServing = parseServingGrams(from: servingSizeText), gramsPerServing > 0 {
            if caloriesPer100g == nil, let calPerServ = caloriesPerServing {
                caloriesPer100g = calPerServ / gramsPerServing * 100.0
            }
            if proteinsPer100g == nil, let pPerServ = proteinsPerServing {
                proteinsPer100g = pPerServ / gramsPerServing * 100.0
            }
            if carbsPer100g == nil, let cPerServ = carbsPerServing {
                carbsPer100g = cPerServ / gramsPerServing * 100.0
            }
            if fatPer100g == nil, let fPerServ = fatPerServing {
                fatPer100g = fPerServ / gramsPerServing * 100.0
            }
        }
    }

    private func canComputeFromGrams() -> Bool {
        if caloriesPer100g != nil || proteinsPer100g != nil || carbsPer100g != nil || fatPer100g != nil {
            return true
        }
        if (caloriesPerServing != nil || proteinsPerServing != nil || carbsPerServing != nil || fatPerServing != nil),
           parseServingGrams(from: servingSizeText) != nil {
            return true
        }
        return false
    }

    // MARK: - Totals calculations

    private func totalsForServings() -> (calories: Int, protein: Double?, carbs: Double?, fat: Double?) {
        let servings = parseDouble(servingsText) ?? 1.0
        var cal = 0
        var p: Double? = nil
        var c: Double? = nil
        var f: Double? = nil

        if let calPer = caloriesPerServing {
            cal = Int(round(calPer * servings))
        } else if let cal100 = caloriesPer100g, let gramsPerServing = parseServingGrams(from: servingSizeText) {
            let perServ = cal100 * gramsPerServing / 100.0
            cal = Int(round(perServ * servings))
        }

        if let pPer = proteinsPerServing {
            p = pPer * servings
        } else if let p100 = proteinsPer100g, let gramsPerServing = parseServingGrams(from: servingSizeText) {
            p = p100 * gramsPerServing / 100.0 * servings
        }

        if let cPer = carbsPerServing {
            c = cPer * servings
        } else if let c100 = carbsPer100g, let gramsPerServing = parseServingGrams(from: servingSizeText) {
            c = c100 * gramsPerServing / 100.0 * servings
        }

        if let fOverride = parseDouble(fatText), !(fatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            f = fOverride
        } else if let fPer = fatPerServing {
            f = fPer * servings
        } else if let f100 = fatPer100g, let gramsPerServing = parseServingGrams(from: servingSizeText) {
            f = f100 * gramsPerServing / 100.0 * servings
        }

        return (cal, p, c, f)
    }

    private func totalsForGrams() -> (calories: Int, protein: Double?, carbs: Double?, fat: Double?) {
        let grams = parseDouble(gramsText) ?? 0.0
        var cal = 0
        var p: Double? = nil
        var c: Double? = nil
        var f: Double? = nil

        if let cal100 = caloriesPer100g {
            cal = Int(round(cal100 * grams / 100.0))
        } else if let calPerServ = caloriesPerServing, let gramsPerServ = parseServingGrams(from: servingSizeText), gramsPerServ > 0 {
            cal = Int(round(calPerServ * (grams / gramsPerServ)))
        }

        if let p100 = proteinsPer100g {
            p = p100 * grams / 100.0
        } else if let pPer = proteinsPerServing, let gramsPerServ = parseServingGrams(from: servingSizeText), gramsPerServ > 0 {
            p = pPer * (grams / gramsPerServ)
        }

        if let c100 = carbsPer100g {
            c = c100 * grams / 100.0
        } else if let cPer = carbsPerServing, let gramsPerServ = parseServingGrams(from: servingSizeText), gramsPerServ > 0 {
            c = cPer * (grams / gramsPerServ)
        }

        if let fOverride = parseDouble(fatText), !(fatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            f = fOverride
        } else if let f100 = fatPer100g {
            f = f100 * grams / 100.0
        } else if let fPer = fatPerServing, let gramsPerServ = parseServingGrams(from: servingSizeText), gramsPerServ > 0 {
            f = fPer * (grams / gramsPerServ)
        }

        return (cal, p, c, f)
    }

    // MARK: - Save / Validation

    private func isSaveAllowed() -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        if hasLookupData {
            if amountMode == .grams {
                guard canComputeFromGrams() else { return false }
                if let g = parseDouble(gramsText), g >= 0.0 { return true }
                return false
            } else {
                if let s = parseDouble(servingsText), s >= 0.0 { return true }
                return false
            }
        } else {
            if let parsed = Int(caloriesText.trimmingCharacters(in: .whitespacesAndNewlines)), parsed >= 0 { return true }
            return false
        }
    }

    private func saveTapped() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            invalidMessage = "Please enter a name."
            showInvalidAlert = true
            return
        }

        var totalCalories: Int = 0
        var totalProtein: Double? = nil
        var totalCarbs: Double? = nil
        var totalFat: Double? = nil
        var usedServings: Double? = nil

        if hasLookupData {
            if amountMode == .servings {
                let parsed = parseDouble(servingsText) ?? 1.0
                usedServings = parsed
                let res = totalsForServings()
                totalCalories = res.calories
                totalProtein = res.protein
                totalCarbs = res.carbs
                totalFat = res.fat
            } else {
                guard canComputeFromGrams() else {
                    invalidMessage = "Cannot calculate from grams for this product."
                    showInvalidAlert = true
                    return
                }
                guard let gramsVal = parseDouble(gramsText), gramsVal >= 0 else {
                    invalidMessage = "Please enter a valid grams amount."
                    showInvalidAlert = true
                    return
                }

                let res = totalsForGrams()
                totalCalories = res.calories
                totalProtein = res.protein
                totalCarbs = res.carbs
                totalFat = res.fat

                if let gramsPerServ = parseServingGrams(from: servingSizeText), gramsPerServ > 0 {
                    usedServings = gramsVal / gramsPerServ
                } else {
                    usedServings = nil
                }
            }
        } else {
            let parsedCal = Int(caloriesText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
            guard parsedCal >= 0 else {
                invalidMessage = "Please enter a valid calorie value."
                showInvalidAlert = true
                return
            }
            totalCalories = parsedCal
            totalProtein = parseDouble(proteinText) ?? 0.0
            totalCarbs = parseDouble(carbsText) ?? 0.0
            totalFat = parseDouble(fatText)
            usedServings = nil
        }

        var capturedServingSizeText = servingSizeText
        if amountMode == .grams, let g = parseDouble(gramsText) {
            capturedServingSizeText = String(format: "%.0f g", g)
        }

        onSave(
            trimmedName,
            totalCalories,
            totalProtein,
            totalCarbs,
            totalFat,
            date,
            capturedServingSizeText,
            usedServings,
            barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        dismiss()
    }
}

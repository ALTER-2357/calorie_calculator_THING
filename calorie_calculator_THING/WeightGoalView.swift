import SwiftUI

struct WeightGoalView: View {
    // Bind to the app's current daily calorie goal so we can compute a suggested intake if needed.
    @Binding var dailyCalorieGoal: Int

    // View model holding state, persistence and compute logic
    @StateObject private var vm = WeightGoalViewModel()

    // Focus state for fields
    private enum Field: Hashable {
        case weight, feet, inches, age
    }
    @FocusState private var focusedField: Field?

    // Keyboard observer (keeps your previous behaviour)
    @StateObject private var keyboard = KeyboardObserver()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Sex picker
                    Picker("Sex", selection: $vm.userSex) {
                        Text("Male").tag("male")
                        Text("Female").tag("female")
                    }
                    .pickerStyle(.segmented)

                    // Weight input (text field) with validation overlay
                    VStack(spacing: 6) {
                        HStack {
                            Text("Weight")
                            Spacer()
                            TextField("e.g. 72.5", text: $vm.weightText)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                                .frame(maxWidth: 140)
                                .focused($focusedField, equals: .weight)
                                .id(Field.weight)

                            Picker("", selection: Binding(get: { vm.weightUnit }, set: { new in vm.convertWeightUnit(to: new) })) {
                                Text("kg").tag("kg")
                                Text("lb").tag("lb")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                        }

                        if !isWeightValid {
                            Text("Enter a valid weight (20–660).")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }

                    // Height input: feet and inches
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Height")
                            Spacer()
                            HStack(spacing: 6) {
                                TextField("ft", text: $vm.feetText)
                                    .multilineTextAlignment(.center)
                                    .textFieldStyle(.roundedBorder)
                                    .keyboardType(.numberPad)
                                    .frame(width: 60)
                                    .focused($focusedField, equals: .feet)
                                    .id(Field.feet)
                                Text("ft")
                            }
                            HStack(spacing: 6) {
                                TextField("in", text: $vm.inchesText)
                                    .multilineTextAlignment(.center)
                                    .textFieldStyle(.roundedBorder)
                                    .keyboardType(.numberPad)
                                    .frame(width: 60)
                                    .focused($focusedField, equals: .inches)
                                    .id(Field.inches)
                                Text("in")
                            }
                        }
                        if !isHeightValid {
                            Text("Enter a valid height (e.g. 5 ft 7 in).")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }

                    // Age input with validation
                    VStack(spacing: 6) {
                        HStack {
                            Text("Age")
                            Spacer()
                            TextField("years", text: $vm.ageText)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                                .frame(maxWidth: 80)
                                .focused($focusedField, equals: .age)
                                .id(Field.age)
                        }
                        if !isAgeValid {
                            Text("Enter a valid age (10–120).")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }

                    // Activity level
                    Picker("Activity", selection: Binding(get: {
                        ActivityLevel.fromStorageKey(vm.userActivityLevel)
                    }, set: { newVal in
                        vm.userActivityLevel = newVal.storageKey
                    })) {
                        ForEach(ActivityLevel.allCases) { lvl in
                            Text(lvl.rawValue).tag(lvl)
                        }
                    }
                    .pickerStyle(.menu)

                    // Mode (lose/maintain/gain)
                    Picker("Target", selection: $vm.mode) {
                        ForEach(Mode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Weekly rate (persisted)
                    HStack {
                        Text("Rate per week")
                        Spacer()
                        if vm.weightUnit == "kg" {
                            Text(String(format: "%.1f kg/week", vm.targetKgPerWeek))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(String(format: "%.2f lb/week", vm.targetKgPerWeek * vm.lbPerKg))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Stepper(value: $vm.targetKgPerWeek, in: 0.0...1.5, step: 0.1) {
                        EmptyView()
                    }
                    .labelsHidden()

                    // Sliders to tune protein/fat per kg presets
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Protein (g/kg):")
                            Spacer()
                            Text(String(format: "%.1f", vm.proteinPerKgLocal))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $vm.proteinPerKgLocal, in: 1.2...2.4, step: 0.1)

                        HStack {
                            Text("Fat (g/kg):")
                            Spacer()
                            Text(String(format: "%.1f", vm.fatPerKgLocal))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $vm.fatPerKgLocal, in: 0.6...1.2, step: 0.1)
                    }

                    // Results and automatic macro update info (reads from vm outputs)
                    VStack(alignment: .leading, spacing: 8) {
                        if vm.maintenanceCalories == nil {
                            Text("Enter valid weight, height and age to compute maintenance calories.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            if let maintenance = vm.maintenanceCalories {
                                HStack {
                                    Text("Estimated maintenance")
                                    Spacer()
                                    Text("\(maintenance) kcal")
                                        .bold()
                                }
                                .font(.subheadline)
                            }

                            let delta = Int(((vm.targetKgPerWeek * vm.kcalPerKg) / 7.0).rounded())
                            if vm.mode == .maintain {
                                Text("Maintain current weight — no calorie change.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if vm.mode == .lose {
                                Text("To lose \(String(format: "%.1f", vm.targetKgPerWeek)) kg/week you need an average daily deficit of about \(delta) kcal.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("To gain \(String(format: "%.1f", vm.targetKgPerWeek)) kg/week you need an average daily surplus of about \(delta) kcal.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let suggested = vm.suggestedDailyIntake {
                                HStack {
                                    Text("Suggested daily intake")
                                    Spacer()
                                    Text("\(suggested) kcal")
                                        .bold()
                                }
                                .font(.subheadline)

                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("Protein")
                                        Text("\(vm.computedProteinG) g")
                                            .font(.headline)
                                    }
                                    Spacer()
                                    VStack(alignment: .leading) {
                                        Text("Fat")
                                        Text("\(vm.computedFatG) g")
                                            .font(.headline)
                                    }
                                    Spacer()
                                    VStack(alignment: .leading) {
                                        Text("Carbs")
                                        Text("\(vm.computedCarbsG) g")
                                            .font(.headline)
                                    }
                                }
                                .font(.caption)
                                .padding(.top, 4)

                                let proteinStr = String(format: "%.1f", vm.proteinPerKgLocal)
                                let fatStr = String(format: "%.1f", vm.fatPerKgLocal)
                                Text("Macros: Protein \(proteinStr) g/kg, Fat \(fatStr) g/kg; Carbs fill remaining calories.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }
                        }

                        Text("Uses Mifflin–St Jeor for BMR and activity multipliers. Macros update automatically to match the suggested intake.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.top, 4)
                }
                .padding()
                // scroll to focused field when focus changes, animating with keyboard timing
                .onChange(of: focusedField) { _, field in
                    guard let field = field else { return }
                    withAnimation(keyboard.swiftUIAnimation) {
                        proxy.scrollTo(field, anchor: .center)
                    }
                }
            }
        }
        .onAppear {
            // nothing heavy on appear — view model did its own initialization
        }
    }

    // MARK: - Validation helpers (UI-only)
    private var parsedWeight: Double? {
        Double(vm.weightText.replacingOccurrences(of: ",", with: "."))
    }

    private var isWeightValid: Bool {
        guard let v = parsedWeight else { return false }
        return v > 20.0 && v < 660.0
    }

    private var heightCmFromFields: Double? {
        guard let feet = Int(vm.feetText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let inches = Int(vm.inchesText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let totalInches = Double(feet) * vm.inchesPerFoot + Double(inches)
        return totalInches * vm.cmPerInch
    }

    private var isHeightValid: Bool {
        guard let cm = heightCmFromFields else { return false }
        return cm >= 50.0 && cm <= 272.0
    }

    private var isAgeValid: Bool {
        guard let v = Int(vm.ageText) else { return false }
        return v >= 10 && v <= 120
    }
}

struct WeightGoalView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            Form {
                WeightGoalView(dailyCalorieGoal: .constant(2000))
            }
        }
        .previewLayout(.sizeThatFits)
    }
}

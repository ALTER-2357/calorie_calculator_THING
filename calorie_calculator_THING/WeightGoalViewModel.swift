import Foundation
import Combine
import SwiftUI

// Shared types used by view + view model
enum Mode: String, CaseIterable, Identifiable {
    case lose = "Lose"
    case maintain = "Maintain"
    case gain = "Gain"
    var id: String { rawValue }
}

enum ActivityLevel: String, CaseIterable, Identifiable {
    case sedentary = "Sedentary"
    case light = "Light"
    case moderate = "Moderate"
    case active = "Active"
    case veryActive = "Very Active"

    var id: String { rawValue }

    var factor: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }

    static func fromStorageKey(_ key: String) -> ActivityLevel {
        switch key {
        case "sedentary": return .sedentary
        case "light": return .light
        case "moderate": return .moderate
        case "active": return .active
        case "veryActive": return .veryActive
        default: return .moderate
        }
    }

    var storageKey: String {
        switch self {
        case .sedentary: return "sedentary"
        case .light: return "light"
        case .moderate: return "moderate"
        case .active: return "active"
        case .veryActive: return "veryActive"
        }
    }
}

final class WeightGoalViewModel: ObservableObject {
    // MARK: - Persistence keys & defaults
    private enum Keys {
        static let userWeight = "userWeight"
        static let weightUnit = "weightUnit"
        static let userHeightCm = "userHeightCm"
        static let userAge = "userAge"
        static let userSex = "userSex"
        static let userActivityLevel = "userActivityLevel"

        static let dailyProteinGoal = "dailyProteinGoal"
        static let dailyCarbGoal = "dailyCarbGoal"
        static let dailyFatGoal = "dailyFatGoal"

        static let weeklyTargetKgPerWeek = "weeklyTargetKgPerWeek"
        static let proteinPerKg = "proteinPerKg"
        static let fatPerKg = "fatPerKg"
        static let weightGoalMode = "weightGoalMode"
    }

    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Conversion constants (exposed so the view can reference them if needed)
    let kcalPerKg = 7700.0
    let kgPerLb = 0.45359237
    let lbPerKg = 2.2046226218
    let cmPerInch = 2.54
    let inchesPerFoot = 12.0

    // MARK: - Persisted backing (kept as simple properties so they can also be read externally)
    // Provide initial values so stored properties are fully initialized before init body runs.
    @Published private(set) var userWeight: Double = 70.0
    @Published var weightUnit: String = "kg"
    @Published private(set) var userHeightCm: Double = 170.0
    @Published private(set) var userAge: Int = 30
    @Published var userSex: String = "male"
    @Published var userActivityLevel: String = "moderate"

    // Persisted macro goals (also published so UI/other parts can observe changes)
    @Published private(set) var dailyProteinGoal: Int = 100
    @Published private(set) var dailyCarbGoal: Int = 250
    @Published private(set) var dailyFatGoal: Int = 70

    // Persisted tuning & mode
    @Published var storedWeeklyTargetKgPerWeek: Double = 0.5
    @Published var storedProteinPerKg: Double = 1.8
    @Published var storedFatPerKg: Double = 0.9
    @Published var storedWeightGoalMode: String = "maintain"

    // MARK: - UI backing fields (user-editable text + controls)
    @Published var weightText: String = ""
    @Published var feetText: String = ""
    @Published var inchesText: String = ""
    @Published var ageText: String = ""
    @Published var proteinPerKgLocal: Double = 1.8
    @Published var fatPerKgLocal: Double = 0.9
    @Published var targetKgPerWeek: Double = 0.5
    @Published var mode: Mode = .maintain

    // MARK: - Computed outputs (published)
    @Published private(set) var maintenanceCalories: Int?
    @Published private(set) var suggestedDailyIntake: Int?
    @Published private(set) var computedProteinG: Int = 0
    @Published private(set) var computedFatG: Int = 0
    @Published private(set) var computedCarbsG: Int = 0

    // Simple cache to skip recalculation if inputs unchanged
    private var lastInputSignature: String?

    // MARK: - Init
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Load persisted values (use sensible defaults)
        let loadedUserWeight = defaults.double(forKey: Keys.userWeight)
        self.userWeight = (loadedUserWeight == 0) ? 70.0 : loadedUserWeight

        self.weightUnit = defaults.string(forKey: Keys.weightUnit) ?? "kg"

        let loadedHeight = defaults.double(forKey: Keys.userHeightCm)
        self.userHeightCm = (loadedHeight == 0) ? 170.0 : loadedHeight

        let a = defaults.integer(forKey: Keys.userAge)
        self.userAge = (a == 0) ? 30 : a

        self.userSex = defaults.string(forKey: Keys.userSex) ?? "male"
        self.userActivityLevel = defaults.string(forKey: Keys.userActivityLevel) ?? "moderate"

        let loadedProteinGoal = defaults.integer(forKey: Keys.dailyProteinGoal)
        self.dailyProteinGoal = (loadedProteinGoal == 0) ? 100 : loadedProteinGoal

        let loadedCarbGoal = defaults.integer(forKey: Keys.dailyCarbGoal)
        self.dailyCarbGoal = (loadedCarbGoal == 0) ? 250 : loadedCarbGoal

        let loadedFatGoal = defaults.integer(forKey: Keys.dailyFatGoal)
        self.dailyFatGoal = (loadedFatGoal == 0) ? 70 : loadedFatGoal

        self.storedWeeklyTargetKgPerWeek = defaults.object(forKey: Keys.weeklyTargetKgPerWeek) as? Double ?? 0.5
        self.storedProteinPerKg = defaults.object(forKey: Keys.proteinPerKg) as? Double ?? 1.8
        self.storedFatPerKg = defaults.object(forKey: Keys.fatPerKg) as? Double ?? 0.9
        self.storedWeightGoalMode = defaults.string(forKey: Keys.weightGoalMode) ?? "maintain"

        // Initialize UI fields from persisted values
        if weightUnit == "kg" {
            self.weightText = Self.fmt(self.userWeight, decimals: 1)
        } else {
            // stored userWeight is in persisted unit; show with 2 decimals for lb by default
            self.weightText = Self.fmt(self.userWeight, decimals: 2)
        }

        // height -> feet + inches
        let totalInches = self.userHeightCm / cmPerInch
        let feet = Int(totalInches / inchesPerFoot)
        let inches = Int(round(totalInches.truncatingRemainder(dividingBy: inchesPerFoot)))
        self.feetText = String(feet)
        self.inchesText = String(inches)

        self.ageText = String(self.userAge)
        self.proteinPerKgLocal = storedProteinPerKg
        self.fatPerKgLocal = storedFatPerKg
        self.targetKgPerWeek = storedWeeklyTargetKgPerWeek
        self.mode = Mode(rawValue: storedWeightGoalMode.capitalized) ?? .maintain

        // Set up Combine pipeline to debounce user edits and trigger save & recompute
        setupPipeline()
        // Immediately compute once (non-debounced) to populate outputs quickly
        computeAndPersistIfNeeded()
    }

    deinit {
        cancellables.forEach { $0.cancel() }
    }

    // MARK: - Combine pipeline
    private func setupPipeline() {
        // Make a list of publishers that should trigger the debounced save & compute
        let publishers: [AnyPublisher<Void, Never>] = [
            $weightText.map { _ in () }.eraseToAnyPublisher(),
            $feetText.map { _ in () }.eraseToAnyPublisher(),
            $inchesText.map { _ in () }.eraseToAnyPublisher(),
            $ageText.map { _ in () }.eraseToAnyPublisher(),
            $weightUnit.map { _ in () }.eraseToAnyPublisher(),
            $userSex.map { _ in () }.eraseToAnyPublisher(),
            $userActivityLevel.map { _ in () }.eraseToAnyPublisher(),
            $proteinPerKgLocal.map { _ in () }.eraseToAnyPublisher(),
            $fatPerKgLocal.map { _ in () }.eraseToAnyPublisher(),
            $targetKgPerWeek.map { _ in () }.eraseToAnyPublisher(),
            $mode.map { _ in () }.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(publishers)
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.computeAndPersistIfNeeded()
            }
            .store(in: &cancellables)
    }

    // MARK: - Helpers & parsing
    private static func fmt(_ value: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", value)
    }

    private var parsedWeight: Double? {
        Double(weightText.replacingOccurrences(of: ",", with: "."))
    }

    private var parsedFeet: Int? {
        Int(feetText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var parsedInches: Int? {
        if inchesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 0 }
        return Int(inchesText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var parsedAge: Int? {
        Int(ageText)
    }

    private var heightCmFromFields: Double? {
        guard let feet = parsedFeet, let inches = parsedInches else { return nil }
        let totalInches = Double(feet) * inchesPerFoot + Double(inches)
        return totalInches * cmPerInch
    }

    private var weightKgFromFields: Double? {
        guard let w = parsedWeight else { return nil }
        return weightUnit == "kg" ? w : w * kgPerLb
    }

    // BMR helper
    private func bmr(sex: String, weightKg: Double, heightCm: Double, age: Int) -> Double {
        let base = 10.0 * weightKg + 6.25 * heightCm - 5.0 * Double(age)
        if sex.lowercased().starts(with: "m") {
            return base + 5.0
        } else {
            return base - 161.0
        }
    }

    // MARK: - Main compute + persist routine (debounced)
    /// Computes outputs and persists values to UserDefaults when inputs are valid.
    /// Uses a signature to skip repeated identical computations.
    func computeAndPersistIfNeeded() {
        // Build signature of inputs that affect computation or persistence
        let weightTextSig = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        let feetSig = feetText.trimmingCharacters(in: .whitespacesAndNewlines)
        let inchesSig = inchesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let ageSig = ageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sig = [
            weightTextSig,
            weightUnit,
            feetSig, inchesSig,
            ageSig,
            userSex,
            userActivityLevel,
            String(proteinPerKgLocal),
            String(fatPerKgLocal),
            String(targetKgPerWeek),
            mode.rawValue
        ].joined(separator: "|")

        if sig == lastInputSignature {
            // nothing changed since last compute/persist
            return
        }
        lastInputSignature = sig

        // Persist valid fields
        if let v = parsedWeight {
            // Persist numeric value according to selected unit (keeps same behavior as original)
            defaults.set(v, forKey: Keys.userWeight)
            self.userWeight = v
        }

        if let cm = heightCmFromFields {
            defaults.set(cm, forKey: Keys.userHeightCm)
            self.userHeightCm = cm
        }

        if let a = parsedAge {
            defaults.set(a, forKey: Keys.userAge)
            self.userAge = a
        }

        // Persist pickers immediately
        defaults.set(weightUnit, forKey: Keys.weightUnit)
        defaults.set(userSex, forKey: Keys.userSex)
        defaults.set(userActivityLevel, forKey: Keys.userActivityLevel)

        defaults.set(storedProteinPerKg, forKey: Keys.proteinPerKg)
        defaults.set(storedFatPerKg, forKey: Keys.fatPerKg)
        defaults.set(storedWeeklyTargetKgPerWeek, forKey: Keys.weeklyTargetKgPerWeek)
        defaults.set(storedWeightGoalMode, forKey: Keys.weightGoalMode)

        // Compute maintenance + suggested + macros if we have required parsed inputs
        guard let wkg = weightKgFromFields,
              let heightCm = heightCmFromFields,
              let age = parsedAge else {
            // Invalidate outputs
            DispatchQueue.main.async {
                self.maintenanceCalories = nil
                self.suggestedDailyIntake = nil
                self.computedProteinG = 0
                self.computedFatG = 0
                self.computedCarbsG = 0
            }
            return
        }

        // Compute maintenance
        let b = bmr(sex: userSex, weightKg: wkg, heightCm: heightCm, age: age)
        let maintenance = Int((b * ActivityLevel.fromStorageKey(userActivityLevel).factor).rounded())

        // Calculate daily delta (kcal/day) based on targetKgPerWeek
        let dailyCalorieDelta = Int(((targetKgPerWeek * kcalPerKg) / 7.0).rounded())

        let suggested: Int
        switch mode {
        case .maintain:
            suggested = maintenance
        case .lose:
            suggested = max(0, maintenance - dailyCalorieDelta)
        case .gain:
            suggested = maintenance + dailyCalorieDelta
        }

        // Compute macros
        let proteinGDouble = (wkg * proteinPerKgLocal).rounded()
        let proteinCal = proteinGDouble * 4.0
        let fatGDouble = (wkg * fatPerKgLocal).rounded()
        let fatCal = fatGDouble * 9.0
        let remainingCal = max(0.0, Double(suggested) - proteinCal - fatCal)
        let carbsGDouble = (remainingCal / 4.0).rounded()

        let proteinG = max(0, Int(proteinGDouble))
        let fatG = max(0, Int(fatGDouble))
        let carbsG = max(0, Int(carbsGDouble))

        // Publish results & persist macro goals
        DispatchQueue.main.async {
            self.maintenanceCalories = maintenance
            self.suggestedDailyIntake = suggested
            self.computedProteinG = proteinG
            self.computedFatG = fatG
            self.computedCarbsG = carbsG
        }

        defaults.set(proteinG, forKey: Keys.dailyProteinGoal)
        defaults.set(fatG, forKey: Keys.dailyFatGoal)
        defaults.set(carbsG, forKey: Keys.dailyCarbGoal)

        // Update published persisted macro goals
        self.dailyProteinGoal = proteinG
        self.dailyFatGoal = fatG
        self.dailyCarbGoal = carbsG

        // Persist tuning values for future sessions
        defaults.set(proteinPerKgLocal, forKey: Keys.proteinPerKg)
        defaults.set(fatPerKgLocal, forKey: Keys.fatPerKg)
        defaults.set(targetKgPerWeek, forKey: Keys.weeklyTargetKgPerWeek)
        defaults.set(mode.rawValue.lowercased(), forKey: Keys.weightGoalMode)
    }

    // MARK: - Unit conversion helper (call from UI when user toggles unit instantly)
    /// Convert the currently shown numeric value to the new unit and persist appropriately.
    func convertWeightUnit(to newUnit: String) {
        // prefer currently typed value if valid, otherwise fallback to persisted userWeight
        let currentValue = (parsedWeight ?? userWeight)
        if weightUnit == newUnit {
            weightUnit = newUnit
            defaults.set(newUnit, forKey: Keys.weightUnit)
            return
        }

        if weightUnit == "kg" && newUnit == "lb" {
            let converted = currentValue * lbPerKg
            userWeight = converted
            weightText = Self.fmt(converted, decimals: 2)
            defaults.set(converted, forKey: Keys.userWeight)
        } else if weightUnit == "lb" && newUnit == "kg" {
            let converted = currentValue * kgPerLb
            userWeight = converted
            weightText = Self.fmt(converted, decimals: 1)
            defaults.set(converted, forKey: Keys.userWeight)
        } else {
            // fallback: persist chosen unit and keep numeric as-is
            weightText = Self.fmt(currentValue, decimals: newUnit == "kg" ? 1 : 2)
            userWeight = currentValue
            defaults.set(currentValue, forKey: Keys.userWeight)
        }

        weightUnit = newUnit
        defaults.set(newUnit, forKey: Keys.weightUnit)
        // schedule immediate compute (no debounce) so UI updates appropriately
        computeAndPersistIfNeeded()
    }
}

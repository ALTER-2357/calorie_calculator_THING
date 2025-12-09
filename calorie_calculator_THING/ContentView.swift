import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    // Entries and meals queries (explicit key paths so compiler can infer types)
    @Query(sort: [SortDescriptor(\FoodEntry.timestamp, order: .reverse)]) private var entries: [FoodEntry]
    @Query(sort: [SortDescriptor(\Meal.name, order: .forward)]) private var meals: [Meal]

    // Selection / sheet state
    @State private var selection: FoodEntry?
    @State private var showingAddEntry = false

    // meal composer sheet state
    @State private var showingAddMeal = false
    @State private var addMealPrefillIDs: Set<UUID> = []
    @State private var mealToEdit: Meal? = nil

    @State private var editingEntry: FoodEntry?
    @State private var selectedMeal: Meal? = nil

    @State private var viewMode: ViewMode = .entries

    // Search/filter state
    @State private var searchText: String = ""

    // Confirmation dialog state
    @State private var mealToDelete: Meal? = nil
    @State private var showDeleteMealConfirmation = false

    // Settings persistent with AppStorage
    @AppStorage("dailyCalorieGoal") private var dailyCalorieGoal: Int = 2000

    // New macro goals (grams)
    @AppStorage("dailyProteinGoal") private var dailyProteinGoal: Int = 100
    @AppStorage("dailyCarbGoal") private var dailyCarbGoal: Int = 250
    @AppStorage("dailyFatGoal") private var dailyFatGoal: Int = 70

    // Settings sheet
    @State private var showingSettings = false

    // MARK: - ViewMode
    private enum ViewMode: String, CaseIterable, Identifiable {
        case entries = "Entries"
        case meals = "Meals"
        var id: String { rawValue }
    }

    // MARK: - Totals
    private var totalCaloriesToday: Int {
        let calendar = Calendar.current
        return entries.filter { calendar.isDateInToday($0.timestamp) }.reduce(0) { $0 + $1.calories }
    }
    private var totalProteinToday: Double {
        let calendar = Calendar.current
        return entries.filter { calendar.isDateInToday($0.timestamp) }.reduce(0.0) { $0 + ($1.protein ?? 0.0) }
    }
    private var totalCarbsToday: Double {
        let calendar = Calendar.current
        return entries.filter { calendar.isDateInToday($0.timestamp) }.reduce(0.0) { $0 + ($1.carbs ?? 0.0) }
    }
    private var totalFatToday: Double {
        let calendar = Calendar.current
        return entries.filter { calendar.isDateInToday($0.timestamp) }.reduce(0.0) { $0 + ($1.fat ?? 0.0) }
    }

    private var totalCaloriesAllTime: Int {
        entries.reduce(0) { $0 + $1.calories }
    }
    private var totalProteinAllTime: Double {
        entries.reduce(0.0) { $0 + ($1.protein ?? 0.0) }
    }
    private var totalCarbsAllTime: Double {
        entries.reduce(0.0) { $0 + ($1.carbs ?? 0.0) }
    }
    // Added totalFatAllTime
    private var totalFatAllTime: Double {
        entries.reduce(0.0) { $0 + ($1.fat ?? 0.0) }
    }

    // Helper to format doubles consistently and avoid interpolation quoting issues
    private func fmt(_ value: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", value)
    }

    // Precompute the "All time" text
    private var allTimeText: String {
        "\(totalCaloriesAllTime) kcal • \(fmt(totalProteinAllTime)) g protein • \(fmt(totalCarbsAllTime)) g carbs • \(fmt(totalFatAllTime)) g fat"
    }

    // Group entries by start of day, sorted descending by day
    private var groupedEntries: [(dayStart: Date, items: [FoodEntry])] {
        let calendar = Calendar.current
        let filtered = entries.filter { entryMatchesSearch($0) }
        let grouped = Dictionary(grouping: filtered) { (entry: FoodEntry) in
            calendar.startOfDay(for: entry.timestamp)
        }
        return grouped
            .map { (dayStart: $0.key, items: $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { $0.dayStart > $1.dayStart }
    }

    // Filtered meals (by search text)
    private var filteredMeals: [Meal] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return meals }
        return meals.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Helpers
    private func entryMatchesSearch(_ entry: FoodEntry) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if entry.name.localizedCaseInsensitiveContains(query) { return true }
        if let mealName = entry.meal?.name, mealName.localizedCaseInsensitiveContains(query) { return true }
        if let barcode = entry.barcode, barcode.localizedCaseInsensitiveContains(query) { return true }
        return false
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar: top spacing and inline search
            VStack() {
                // Inline search field placed at the very top of the content so it sits close under the toolbar.
                inlineSearchField
                    .padding(.horizontal, 16)

                // Mode picker
                Picker("Mode", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                // Totals card with progress
                totalsCard
                    .padding(.horizontal, 16)

                // Content lists
                if viewMode == .entries {
                    entriesList
                } else {
                    mealsList
                }
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 240, ideal: 340)
#endif
            .toolbar {
                // Combined Menu + larger toolbar controls
                #if os(macOS)
                // Single combined menu on the leading side with a larger control size
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        if meals.isEmpty {
                            Text("No meals")
                        } else {
                            Section {
                                ForEach(meals) { meal in
                                    Button {
                                        selectedMeal = meal
                                        selection = nil
                                        viewMode = .meals
                                    } label: {
                                        Label(meal.name, systemImage: "tray.full")
                                    }
                                }
                            }
                        }
                        Button {
                            addMealPrefillIDs = []
                            mealToEdit = nil
                            showingAddMeal = true
                        } label: {
                            Label("New Meal", systemImage: "plus.rectangle.on.rectangle")
                        }

                        Divider()

                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Label("Menu", systemImage: "line.horizontal.3")
                            .labelStyle(.iconOnly)
                            .imageScale(.large)
                    }
                    .controlSize(.large)
                    .help("Meals, quick actions & settings")
                }

                // Add entry primary action (more prominent)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddEntry = true }) {
                        Label("Add Entry", systemImage: "plus")
                    }
                    .controlSize(.large)
                }
                #else
                // On iOS / Catalyst show a bottom bar toolbar with combined menu and larger font
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Label("Menu", systemImage: "line.horizontal.3")
                            .imageScale(.large)
                    }
                    .font(.title3)
                    .help("Meals, quick actions & settings")
                }

                ToolbarItem(placement: .bottomBar) {
                    Button(action: { showingAddEntry = true }) {
                        Label("Add Entry", systemImage: "plus")
                    }
                    .font(.title3)
                }
                #endif
            }
            // Add/edit meal sheet
            .sheet(isPresented: $showingAddMeal) {
                AddMealView(
                    entries: entries,
                    initialSelectedIDs: addMealPrefillIDs,
                    editingMeal: mealToEdit
                ) { name, chosenEntries, editing in
                    addOrUpdateMeal(name: name, chosen: chosenEntries, editingMeal: editing)
                    addMealPrefillIDs = []
                    mealToEdit = nil
                }
            }
            // Add entry sheet (updated to include fat in closure)
            .sheet(isPresented: $showingAddEntry) {
                AddEntryView { name, calories, protein, carbs, fat, date, servingSize, servings, barcode in
                    addEntry(
                        name: name,
                        calories: calories,
                        protein: protein,
                        carbs: carbs,
                        fat: fat,
                        date: date,
                        servingSize: servingSize,
                        servings: servings,
                        barcode: barcode
                    )
                }
            }
            // Edit entry sheet
            .sheet(item: $editingEntry) { entry in
                EditEntryView(entry: entry) { entryForMeal in
                    addMealPrefillIDs = [entryForMeal.id]
                    mealToEdit = nil
                    showingAddMeal = true
                }
            }
            .confirmationDialog("Delete meal?", isPresented: $showDeleteMealConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let toDelete = mealToDelete {
                        deleteMeal(toDelete)
                    }
                    mealToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    mealToDelete = nil
                }
            } message: {
                if let m = mealToDelete {
                    Text("This will remove the meal but keep the items as standalone entries: \"\(m.name)\".")
                } else {
                    Text("Are you sure?")
                }
            }
            // Settings sheet
            .sheet(isPresented: $showingSettings) {
                SettingsView(
                    dailyCalorieGoal: $dailyCalorieGoal,
                    dailyProteinGoal: $dailyProteinGoal,
                    dailyCarbGoal: $dailyCarbGoal,
                    dailyFatGoal: $dailyFatGoal
                )
            }
        } detail: {
            // Detail area
            if let sel = selection {
                entryDetail(sel)
            } else if let meal = selectedMeal {
                mealDetail(meal)
            } else if entries.isEmpty {
                VStack {
                    Text("No entries yet")
                        .font(.title3)
                        .bold()
                    Text("Tap + to add your first food entry.")
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                Text("Select an entry or open the menu to view a meal")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    // Inline search field placed at the top of the sidebar so it sits closely under the toolbar.
    private var inlineSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search entries and meals", text: $searchText)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.06)))
    }

    // MARK: - Subviews: Totals Card

    private var totalsCard: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(totalCaloriesToday) kcal")
                        .font(.title2)
                        .bold()
                    Text("Calories")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Show three small nutrient metrics: Protein, Carbs, Fat
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading) {
                            Text("\(fmt(totalProteinToday)) g")
                                .font(.title2)
                                .bold()
                            Text("Protein")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading) {
                            Text("\(fmt(totalCarbsToday)) g")
                                .font(.title2)
                                .bold()
                            Text("Carbs")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading) {
                            Text("\(fmt(totalFatToday)) g")
                                .font(.title2)
                                .bold()
                            Text("Fat")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            ProgressView(value: min(Double(totalCaloriesToday) / Double(max(1, dailyCalorieGoal)), 1.0)) {
                Text("Daily goal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } currentValueLabel: {
                Text("\(totalCaloriesToday)/\(dailyCalorieGoal) kcal")
                    .font(.caption2)
            }

            .accessibilityLabel("Daily calories")
            .accessibilityValue("\(totalCaloriesToday) of \(dailyCalorieGoal) calories")

            // Macro progress bars (always shown)
            VStack(spacing: 8) {
                // Protein
                HStack {
                    Text("Protein")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(fmt(totalProteinToday)) / \(dailyProteinGoal) g")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(totalProteinToday / Double(max(1, dailyProteinGoal)), 1.0))
                    .accessibilityLabel("Protein")
                    .accessibilityValue("\(fmt(totalProteinToday)) of \(dailyProteinGoal) grams")

                // Carbs
                HStack {
                    Text("Carbs")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(fmt(totalCarbsToday)) / \(dailyCarbGoal) g")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(totalCarbsToday / Double(max(1, dailyCarbGoal)), 1.0))
                    .accessibilityLabel("Carbohydrates")
                    .accessibilityValue("\(fmt(totalCarbsToday)) of \(dailyCarbGoal) grams")

                // Fat
                HStack {
                    Text("Fat")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(fmt(totalFatToday)) / \(dailyFatGoal) g")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(totalFatToday / Double(max(1, dailyFatGoal)), 1.0))
                    .accessibilityLabel("Fat")
                    .accessibilityValue("\(fmt(totalFatToday)) of \(dailyFatGoal) grams")
            }

            HStack {
                Text("All time:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(allTimeText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.08)))
    }

    // MARK: - Subviews: Lists

    private var entriesList: some View {
        List {
            if groupedEntries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No entries match")
                        .bold()
                    Text("Try adding a new entry or clearing your search.")
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                ForEach(groupedEntries, id: \.dayStart) { group in
                    Section(header: Text(group.dayStart, format: .dateTime.day().month().year())) {
                        ForEach(group.items) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func entryRow(_ entry: FoodEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    if let meal = entry.meal {
                        Label(meal.name, systemImage: "tray.full")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(entry.timestamp, format: .dateTime.hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("\(entry.calories) kcal")
                    .bold()
                    .font(.body)
                HStack(spacing: 8) {
                    if let p = entry.protein {
                        Text("\(fmt(p)) g")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let c = entry.carbs {
                        Text("\(fmt(c)) g")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let f = entry.fat {
                        Text("\(fmt(f)) g")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            selection = entry
            selectedMeal = nil
            viewMode = .entries
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                withAnimation {
                    modelContext.delete(entry)
                    if selection?.id == entry.id { selection = nil }
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                editingEntry = entry
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)

            Button {
                addMealPrefillIDs = [entry.id]
                mealToEdit = nil
                showingAddMeal = true
            } label: {
                Label("Make Meal", systemImage: "plus.rectangle.on.rectangle")
            }
            .tint(.green)
        }
    }

    private var mealsList: some View {
        List {
            if filteredMeals.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No meals found")
                        .bold()
                    Text("Create a new meal to group frequently eaten items.")
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                ForEach(filteredMeals) { meal in
                    Button {
                        selectedMeal = meal
                        selection = nil
                        viewMode = .meals
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(meal.name)
                                    .font(.headline)
                                Text("\(meal.entries.count) items • \(meal.totalCalories) kcal • \(fmt(meal.totalFat)) g fat")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(meal.totalCalories) kcal")
                                .bold()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            mealToDelete = meal
                            showDeleteMealConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            addMealPrefillIDs = Set(meal.entries.map { $0.id })
                            mealToEdit = meal
                            showingAddMeal = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Detail views

    @ViewBuilder
    private func entryDetail(_ selected: FoodEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selected.name)
                        .font(.largeTitle)
                        .bold()
                    Text("\(selected.calories) kcal")
                        .font(.title2)
                        .foregroundStyle(.primary)
                }

                Spacer()

                Button("Edit") {
                    editingEntry = selected
                }
                .buttonStyle(.bordered)
            }

            if let serving = selected.servingSize {
                Text("Serving: \(serving)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let s = selected.servings {
                Text("Servings: \(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let p = selected.protein {
                Text("Protein: \(fmt(p)) g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let c = selected.carbs {
                Text("Carbs: \(fmt(c)) g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let f = selected.fat {
                Text("Fat: \(fmt(f)) g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let code = selected.barcode {
                Text("Barcode: \(code)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let meal = selected.meal {
                Text("Part of meal: \(meal.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(selected.timestamp, format: .dateTime.year().month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private func mealDetail(_ meal: Meal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(meal.name)
                        .font(.largeTitle)
                        .bold()
                    Text("\(meal.totalCalories) kcal • \(fmt(meal.totalProtein)) g P • \(fmt(meal.totalCarbs)) g C • \(fmt(meal.totalFat)) g F")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }

                Spacer()

                Button("Edit") {
                    addMealPrefillIDs = Set(meal.entries.map { $0.id })
                    mealToEdit = meal
                    showingAddMeal = true
                }
                .buttonStyle(.bordered)
            }

            if meal.entries.isEmpty {
                Text("No items in this meal")
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(meal.entries) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name)
                                    .font(.body)
                                Text(item.timestamp, format: .dateTime.year().month().day().hour().minute())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(item.calories) kcal")
                                    .bold()
                                HStack(spacing: 8) {
                                    if let p = item.protein {
                                        Text("\(fmt(p)) g P")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let c = item.carbs {
                                        Text("\(fmt(c)) g C")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let f = item.fat {
                                        Text("\(fmt(f)) g F")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        let itemsToRemove = offsets.map { meal.entries[$0] }
                        for entry in itemsToRemove {
                            removeEntryFromMeal(entry)
                        }
                    }
                }
                .frame(minHeight: 200, maxHeight: 400)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Actions

    private func addEntry(
        name: String,
        calories: Int,
        protein: Double?,
        carbs: Double?,
        fat: Double?,          // added fat param
        date: Date,
        servingSize: String?,
        servings: Double?,
        barcode: String?
    ) {
        withAnimation {
            let newEntry = FoodEntry(
                name: name,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat,
                timestamp: date,
                servingSize: servingSize,
                servings: servings,
                barcode: barcode
            )
            modelContext.insert(newEntry)
            // attempt explicit save during development to surface errors (optional)
            do {
                try modelContext.save()
            } catch {
                print("Warning: failed to save new entry: \(error)")
            }

            selection = newEntry
            selectedMeal = nil
            viewMode = .entries
        }
    }

    /// Create a new meal or update an existing one
    private func addOrUpdateMeal(name: String, chosen: [FoodEntry], editingMeal: Meal?) {
        withAnimation {
            if let meal = editingMeal {
                // detach entries that are no longer selected
                let chosenIDs = Set(chosen.map { $0.id })
                for e in meal.entries where !chosenIDs.contains(e.id) {
                    e.meal = nil
                }
                // set new entries array
                meal.entries = chosen
                for e in chosen { e.meal = meal }
                meal.name = name
                selectedMeal = meal
                selection = nil
                viewMode = .meals
            } else {
                let meal = Meal(name: name)
                modelContext.insert(meal)
                for e in chosen {
                    meal.entries.append(e)
                    e.meal = meal
                }
                selectedMeal = meal
                selection = nil
                viewMode = .meals
            }
        }
    }

    private func removeEntryFromMeal(_ entry: FoodEntry) {
        withAnimation {
            if let meal = entry.meal {
                meal.entries.removeAll { $0.id == entry.id }
                entry.meal = nil
            }
        }
    }

    private func deleteMeal(_ meal: Meal) {
        withAnimation {
            for entry in meal.entries {
                entry.meal = nil
            }
            modelContext.delete(meal)
            if selectedMeal?.id == meal.id {
                selectedMeal = nil
            }
        }
    }
}

// Preview helper
#Preview {
    ContentView()
        .modelContainer(for: [FoodEntry.self, Meal.self], inMemory: true, isAutosaveEnabled: true, isUndoEnabled: true, onSetup: { _ in })
}

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

    // New: weight & goal sheet
    @State private var showingWeightGoal = false

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

    // Percentage for calorie progress (0.0 - 1.0)
    private var calorieProgress: Double {
        min(Double(totalCaloriesToday) / Double(max(1, dailyCalorieGoal)), 1.0)
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(spacing: 12) {
                // Inline search field placed at the very top of the content so it sits close under the toolbar.
                inlineSearchField
                    .padding(.horizontal, 16)

                // Mode picker with icons
                Picker("Mode", selection: $viewMode) {
                    Label("Entries", systemImage: "list.bullet").tag(ViewMode.entries)
                    Label("Meals", systemImage: "tray.full").tag(ViewMode.meals)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                // Totals card with circular progress
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        if meals.isEmpty {
                            Text("No meals")
                        } else {
                            Section {
                                // Changed behavior: tapping a meal in this menu will add that meal's items as new entries for today
                                ForEach(meals) { meal in
                                    Button {
                                        addMealEntriesToToday(meal)
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
                            showingWeightGoal = true
                        } label: {
                            Label("Weight & Goal", systemImage: "scalemass")
                        }

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

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddEntry = true }) {
                        Label("Add Entry", systemImage: "plus")
                    }
                    .controlSize(.large)
                }
                #else
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        Button {
                            showingWeightGoal = true
                        } label: {
                            Label("Weight & Goal", systemImage: "scalemass")
                        }

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
            // Weight & Goal sheet
            .sheet(isPresented: $showingWeightGoal) {
                NavigationView {
                    Form {
                        WeightGoalView(dailyCalorieGoal: $dailyCalorieGoal)
                    }
                    .navigationTitle("Weight & Goal")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingWeightGoal = false }
                        }
                    }
                }
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
            if !searchText.isEmpty {
                Button {
                    withAnimation { searchText = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.06)))
    }

    // MARK: - Subviews: Totals Card

    private var totalsCard: some View {
        HStack(spacing: 12) {
            CircularProgress(value: calorieProgress, size: 72, lineWidth: 10, color: .red)
                .accessibilityLabel("Daily calories")
                .accessibilityValue("\(totalCaloriesToday) of \(dailyCalorieGoal) calories")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(totalCaloriesToday) kcal")
                            .font(.title2)
                            .bold()
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(totalCaloriesToday)/\(dailyCalorieGoal) kcal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Macro progress rows with color accents
                VStack(spacing: 8) {
                    MacroProgressRow(title: "Protein", value: totalProteinToday, target: Double(dailyProteinGoal), color: .blue)
                    MacroProgressRow(title: "Carbs", value: totalCarbsToday, target: Double(dailyCarbGoal), color: .orange)
                    MacroProgressRow(title: "Fat", value: totalFatToday, target: Double(dailyFatGoal), color: .pink)
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
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.08)))
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
        HStack(spacing: 12) {
            // Leading icon circle
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.name)
                    .font(.headline)
                    .lineLimit(1)
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

            VStack(alignment: .trailing, spacing: 6) {
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
        .contextMenu {
            Button {
                addMealPrefillIDs = [entry.id]
                mealToEdit = nil
                showingAddMeal = true
            } label: {
                Label("Make Meal", systemImage: "plus.rectangle.on.rectangle")
            }
            Button {
                editingEntry = entry
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                withAnimation {
                    modelContext.delete(entry)
                    if selection?.id == entry.id { selection = nil }
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
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
                            VStack(alignment: .trailing) {
                                Text("\(meal.totalCalories) kcal")
                                    .bold()
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            addMealPrefillIDs = Set(meal.entries.map { $0.id })
                            mealToEdit = meal
                            showingAddMeal = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            mealToDelete = meal
                            showDeleteMealConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
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

    /// Add all items from a meal as new standalone entries with today's timestamp.
    private func addMealEntriesToToday(_ meal: Meal) {
        guard !meal.entries.isEmpty else { return }
        withAnimation {
            let now = Date()
            var lastInserted: FoodEntry? = nil
            for item in meal.entries {
                let copy = FoodEntry(
                    name: item.name,
                    calories: item.calories,
                    protein: item.protein,
                    carbs: item.carbs,
                    fat: item.fat,
                    timestamp: now,
                    servingSize: item.servingSize,
                    servings: item.servings,
                    barcode: item.barcode
                )
                modelContext.insert(copy)
                lastInserted = copy
            }
            // attempt explicit save to surface errors during development (optional)
            do {
                try modelContext.save()
            } catch {
                print("Warning: failed to save meal copies: \(error)")
            }
            if let last = lastInserted {
                selection = last
                selectedMeal = nil
                viewMode = .entries
            }
        }
    }
}

// MARK: - Supporting UI components

private struct CircularProgress: View {
    var value: Double // 0..1
    var size: CGFloat = 64
    var lineWidth: CGFloat = 8
    var color: Color = .accentColor

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.12), lineWidth: lineWidth)
                .frame(width: size, height: size)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(value, 0), 1)))
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .foregroundColor(color)
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)
            VStack {
                Text("\(Int(value * 100))%")
                    .font(.caption2)
                    .bold()
                Text("Daily")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MacroProgressRow: View {
    var title: String
    var value: Double
    var target: Double
    var color: Color

    private var progress: Double {
        min(value / max(1.0, target), 1.0)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(String(format: "%.0f", value)) / \(Int(target)) g")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(color)
                .accessibilityLabel(title)
                .accessibilityValue("\(String(format: "%.0f", value)) of \(Int(target)) grams")
        }
    }
}

// Preview helper
#Preview {
    ContentView()
        .modelContainer(for: [FoodEntry.self, Meal.self], inMemory: true, isAutosaveEnabled: true, isUndoEnabled: true, onSetup: { _ in })
}

//
//  AddMealView.swift
//  calorie_calculator_THING
//
//  Created by lewis mills on 09/12/2025.
//


import SwiftUI
import SwiftData

/// AddMealView can be used to create a new Meal or edit an existing one.
/// - entries: list of available FoodEntry items to choose from
/// - initialSelectedIDs: useful to prefill (e.g. "make it a meal" from a single entry)
/// - editingMeal: if non-nil, the view is in "edit" mode and will prefill with the meal's data
/// - onSave: called with (mealName, chosenEntries, editingMeal). editingMeal is nil for creates.
/// 
struct AddMealView: View {
    @Environment(\.dismiss) private var dismiss

    let entries: [FoodEntry]
    let initialSelectedIDs: Set<UUID>
    let editingMeal: Meal?
    let onSave: (String, [FoodEntry], Meal?) -> Void

    @State private var mealName: String = ""
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var editingEntry: FoodEntry? = nil

    init(entries: [FoodEntry], initialSelectedIDs: Set<UUID> = [], editingMeal: Meal? = nil, onSave: @escaping (String, [FoodEntry], Meal?) -> Void) {
        self.entries = entries
        self.initialSelectedIDs = initialSelectedIDs
        self.editingMeal = editingMeal
        self.onSave = onSave
        _selectedEntryIDs = State(initialValue: initialSelectedIDs)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(editingMeal == nil ? "New meal name" : "Edit meal name")) {
                    TextField("e.g. Lunch", text: $mealName)
                }

                Section(header: Text("Choose items")) {
                    if entries.isEmpty {
                        Text("No food entries available. Add items first.")
                            .foregroundStyle(.secondary)
                    } else {
                        List {
                            ForEach(entries) { entry in
                                HStack {
                                    Button(action: { toggleSelection(id: entry.id) }) {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(entry.name)
                                                    .font(.body)
                                                Text(entry.timestamp, format: .dateTime.year().month().day().hour().minute())
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                HStack(spacing: 8) {
                                                    if let p = entry.protein {
                                                        // Use String(format:) to avoid nested interpolation/escaping issues
                                                        Text("\(String(format: "%.1f", p)) g P")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    if let c = entry.carbs {
                                                        Text("\(String(format: "%.1f", c)) g C")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                            }
                                            Spacer()
                                            Text("\(entry.calories) kcal")
                                                .bold()
                                            Image(systemName: selectedEntryIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(selectedEntryIDs.contains(entry.id) ? .accentColor : .secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    // Edit button to allow quick editing of this entry while composing meal
                                    Button {
                                        editingEntry = entry
                                    } label: {
                                        Image(systemName: "pencil")
                                            .imageScale(.small)
                                    }
                                    .buttonStyle(.borderless)
                                    .padding(.leading, 8)
                                }
                                .padding(.vertical, 6)
                            }
                        }
                        .listStyle(.plain)
                        .frame(minHeight: 200, maxHeight: 420)
                    }
                }
            }
            .navigationTitle(editingMeal == nil ? "New Meal" : "Edit Meal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedEntryIDs.isEmpty)
                }
            }
            .onAppear {
                if let meal = editingMeal {
                    mealName = meal.name
                    selectedEntryIDs = Set(meal.entries.map { $0.id })
                } else if !initialSelectedIDs.isEmpty {
                    selectedEntryIDs = initialSelectedIDs
                }
            }
            // Present EditEntryView so the user can adjust protein/carbs/calories for entries while building the meal.
            .sheet(item: $editingEntry) { entry in
                // EditEntryView mutates the model entry directly, so changes are visible in this list.
                EditEntryView(entry: entry, onMakeMeal: { _ in /* no-op when editing inside meal composer */ })
            }
        }
    }

    private func toggleSelection(id: UUID) {
        if selectedEntryIDs.contains(id) {
            selectedEntryIDs.remove(id)
        } else {
            selectedEntryIDs.insert(id)
        }
    }

    private func save() {
        let chosen = entries.filter { selectedEntryIDs.contains($0.id) }
        onSave(mealName.trimmingCharacters(in: .whitespacesAndNewlines), chosen, editingMeal)
        dismiss()
    }
}

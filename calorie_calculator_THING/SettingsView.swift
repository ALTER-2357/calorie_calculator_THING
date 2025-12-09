//
//  SettingsView.swift
//  calorie_calculator_THING
//
//  Created by lewis mills on 09/12/2025.
//


import SwiftUI

struct SettingsView: View {
    // Bindings to AppStorage values in ContentView
    @Binding var dailyCalorieGoal: Int
    @Binding var compactLayout: Bool

    // Local temp value so we don't commit every stepper tick unless desired
    @State private var tempGoal: Int = 0

    private let minGoal = 800
    private let maxGoal = 6000
    private let step = 50

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Daily Goal")) {
                    HStack {
                        Text("Calorie goal")
                        Spacer()
                        Text("\(dailyCalorieGoal) kcal")
                            .foregroundStyle(.secondary)
                    }

                    Stepper(value: $tempGoal, in: minGoal...maxGoal, step: step) {
                        Text("Set goal: \(tempGoal) kcal")
                    }
                    .onAppear { tempGoal = dailyCalorieGoal }
                    .onChange(of: tempGoal) { new in
                        // commit immediately — you can change this to only commit on Done if desired
                        dailyCalorieGoal = new
                    }

                    Button("Reset to default (2000 kcal)") {
                        tempGoal = 2000
                        dailyCalorieGoal = 2000
                    }
                    .foregroundStyle(.blue)
                }

                Section(header: Text("Layout")) {
                    Toggle(isOn: $compactLayout) {
                        VStack(alignment: .leading) {
                            Text("Compact layout")
                            Text("Reduce spacing and text sizes for narrow or dense layouts")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(header: Text("About")) {
                    Text("Settings are saved automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // iOS/macOS will dismiss via parent sheet binding
                        // Nothing to do here — parent controls dismissal.
                    }
                }
            }
        }
    }
}

// Simple preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(dailyCalorieGoal: .constant(2000), compactLayout: .constant(false))
    }
}
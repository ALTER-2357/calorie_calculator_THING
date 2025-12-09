import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    // Bindings to AppStorage values in ContentView
    @Binding var dailyCalorieGoal: Int

    // New macro goal bindings
    @Binding var dailyProteinGoal: Int
    @Binding var dailyCarbGoal: Int
    @Binding var dailyFatGoal: Int

    // Local temp values so we don't commit every stepper tick unless desired
    @State private var tempGoal: Int = 0
    @State private var tempProtein: Int = 0
    @State private var tempCarbs: Int = 0
    @State private var tempFat: Int = 0

    // File export / import state
    @State private var showingImporter = false
    @State private var exportURL: URL? = nil
    @State private var showingShareSheet = false
    @State private var alertMessage: String? = nil
    @State private var showingAlert = false

    @Environment(\.modelContext) private var modelContext

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
                    .onAppear {
                        tempGoal = dailyCalorieGoal
                        tempProtein = dailyProteinGoal
                        tempCarbs = dailyCarbGoal
                        tempFat = dailyFatGoal
                    }
                    .onChange(of: tempGoal) { new in
                        // commit immediately — you can change this to only commit on Done if desired
                        dailyCalorieGoal = new
                    }

                    Button("Reset to default (2000 kcal)") {
                        tempGoal = 2000
                        dailyCalorieGoal = 2000
                        // also reset macros to sensible defaults
                        tempProtein = 100
                        tempCarbs = 250
                        tempFat = 70
                        dailyProteinGoal = 100
                        dailyCarbGoal = 250
                        dailyFatGoal = 70
                    }
                    .foregroundStyle(.blue)
                }

                Section(header: Text("Macronutrient Goals")) {
                    HStack {
                        Text("Protein")
                        Spacer()
                        Text("\(dailyProteinGoal) g")
                            .foregroundStyle(.secondary)
                    }
                    Stepper(value: $tempProtein, in: 0...500, step: 1) {
                        Text("Protein: \(tempProtein) g")
                    }
                    .onChange(of: tempProtein) { new in
                        dailyProteinGoal = new
                    }

                    HStack {
                        Text("Carbs")
                        Spacer()
                        Text("\(dailyCarbGoal) g")
                            .foregroundStyle(.secondary)
                    }
                    Stepper(value: $tempCarbs, in: 0...1000, step: 5) {
                        Text("Carbs: \(tempCarbs) g")
                    }
                    .onChange(of: tempCarbs) { new in
                        dailyCarbGoal = new
                    }

                    HStack {
                        Text("Fat")
                        Spacer()
                        Text("\(dailyFatGoal) g")
                            .foregroundStyle(.secondary)
                    }
                    Stepper(value: $tempFat, in: 0...300, step: 1) {
                        Text("Fat: \(tempFat) g")
                    }
                    .onChange(of: tempFat) { new in
                        dailyFatGoal = new
                    }
                }

                // New section for backup/export/import
                Section(header: Text("Backup & Export")) {
                    Button {
                        doExport()
                    } label: {
                        Label("Export backup (JSON)", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import backup", systemImage: "square.and.arrow.down")
                    }
                    .fileImporter(
                        isPresented: $showingImporter,
                        allowedContentTypes: [UTType.json],
                        allowsMultipleSelection: false
                    ) { result in
                        switch result {
                        case .success(let urls):
                            guard let url = urls.first else { return }
                            importBackup(from: url)
                        case .failure(let error):
                            alertMessage = "Failed to open file: \(error.localizedDescription)"
                            showingAlert = true
                        }
                    }

                    Text("Export creates a JSON file containing your entries and meals. Use 'Import' to restore or merge from a previously exported file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        // Parent sheet dismisses; nothing else to do here.
                    }
                }
            }
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("Backup"), message: Text(alertMessage ?? ""), dismissButton: .default(Text("OK")))
            }
            // Present share sheet when we have an export url
            .sheet(isPresented: $showingShareSheet, onDismiss: {
                // remove temp file if needed
                if let url = exportURL {
                    try? FileManager.default.removeItem(at: url)
                    exportURL = nil
                }
            }) {
                if let url = exportURL {
                    #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
                    ShareSheet(activityItems: [url])
                        .edgesIgnoringSafeArea(.all)
                    #else
                    // macOS share sheet wrapper
                    ShareSheet(items: [url])
                    #endif
                } else {
                    Text("Preparing export...")
                }
            }
        }
    }

    private func doExport() {
        do {
            let fileURL = try BackupManager.createBackupFile(from: modelContext)
            exportURL = fileURL
            showingShareSheet = true
        } catch {
            alertMessage = "Export failed: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func importBackup(from url: URL) {
        do {
            let (entriesImported, mealsImported) = try BackupManager.importBackup(from: url, into: modelContext)
            alertMessage = "Imported \(entriesImported) entries and \(mealsImported) meals."
            showingAlert = true
        } catch {
            alertMessage = "Import failed: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}

// Simple preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(
            dailyCalorieGoal: .constant(2000),
            dailyProteinGoal: .constant(100),
            dailyCarbGoal: .constant(250),
            dailyFatGoal: .constant(70)
        )
    }
}

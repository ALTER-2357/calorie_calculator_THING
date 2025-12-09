import Foundation
import SwiftData
import UniformTypeIdentifiers

// Simple DTOs for exporting/importing SwiftData model content as JSON.
// We intentionally keep these separate from the @Model classes to avoid
// coupling the on-disk representation to SwiftData internals.
fileprivate struct FoodEntryDTO: Codable {
    var id: UUID
    var name: String
    var calories: Int
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var timestamp: Date
    var servingSize: String?
    var servings: Double?
    var barcode: String?
    // Preserve relationship by storing the meal id (if any)
    var mealID: UUID?
}

fileprivate struct MealDTO: Codable {
    var id: UUID
    var name: String
    // list of entry IDs that belong to this meal
    var entryIDs: [UUID]
}

fileprivate struct FoodDiaryBackup: Codable {
    var exportedAt: Date
    var entries: [FoodEntryDTO]
    var meals: [MealDTO]
}

enum BackupError: Error {
    case failedToCreateBackupFile
    case invalidBackupFile
    case decodingError(Error)
    case encodingError(Error)
    case writingError(Error)
    case readingError(Error)
    case importFailed(Error)
}

struct BackupManager {
    static let preferredFileUTType = UTType.json

    // Create a JSON backup file in the temporary directory and return its URL.
    // The caller is responsible for presenting / sharing the file.
    static func createBackupFile(from modelContext: ModelContext) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        var entryDTOs: [FoodEntryDTO] = []
        var mealDTOs: [MealDTO] = []

        let entryFetch = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        let mealFetch = FetchDescriptor<Meal>(sortBy: [SortDescriptor(\.name, order: .forward)])

        do {
            let entries = try modelContext.fetch(entryFetch)
            let meals = try modelContext.fetch(mealFetch)

            entryDTOs = entries.map { e in
                FoodEntryDTO(
                    id: e.id,
                    name: e.name,
                    calories: e.calories,
                    protein: e.protein,
                    carbs: e.carbs,
                    fat: e.fat,
                    timestamp: e.timestamp,
                    servingSize: e.servingSize,
                    servings: e.servings,
                    barcode: e.barcode,
                    mealID: e.meal?.id
                )
            }

            mealDTOs = meals.map { m in
                MealDTO(
                    id: m.id,
                    name: m.name,
                    entryIDs: m.entries.map { $0.id }
                )
            }
        } catch {
            throw BackupError.importFailed(error)
        }

        let backup = FoodDiaryBackup(exportedAt: Date(), entries: entryDTOs, meals: mealDTOs)

        do {
            let data = try encoder.encode(backup)
            let iso = ISO8601DateFormatter().string(from: Date())
            let fileName = "FoodDiaryBackup_\(iso).json"
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            do {
                try data.write(to: fileURL, options: .atomic)
                return fileURL
            } catch {
                throw BackupError.writingError(error)
            }
        } catch {
            throw BackupError.encodingError(error)
        }
    }

    // Import a backup JSON file and insert entries + meals into the provided ModelContext.
    // This implementation will add the items found in the backup. It does not attempt to detect or deduplicate items
    // with the same logical id — depending on your needs you can add dedupe logic (e.g. skip if a FoodEntry with same UUID exists).
    // Returns (entriesImported, mealsImported)
    static func importBackup(from url: URL, into modelContext: ModelContext) throws -> (Int, Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BackupError.readingError(error)
        }

        let backup: FoodDiaryBackup
        do {
            backup = try decoder.decode(FoodDiaryBackup.self, from: data)
        } catch {
            throw BackupError.decodingError(error)
        }

        // Insert entries first and keep a map of id -> FoodEntry
        var insertedEntriesByID: [UUID: FoodEntry] = [:]
        var entriesInserted = 0
        var mealsInserted = 0

        // Insert inside a synchronous closure to ensure thread-safety with SwiftData.
        // Many SwiftData versions expose perform/performAndWait; to keep the code simple
        // and compatible we execute the block directly. If you need to call a real
        // performAndWait on newer SwiftData versions, you can add conditional code here.
        do {
            try modelContext.performAndWait {
                for dto in backup.entries {
                    let entry = FoodEntry(
                        id: dto.id,
                        name: dto.name,
                        calories: dto.calories,
                        protein: dto.protein,
                        carbs: dto.carbs,
                        fat: dto.fat,
                        timestamp: dto.timestamp,
                        servingSize: dto.servingSize,
                        servings: dto.servings,
                        barcode: dto.barcode
                    )
                    modelContext.insert(entry)
                    insertedEntriesByID[dto.id] = entry
                    entriesInserted += 1
                }

                // Now insert meals and wire up relationships
                for mdto in backup.meals {
                    let meal = Meal(id: mdto.id, name: mdto.name)
                    modelContext.insert(meal)
                    // Attach entries found in this meal using the id -> object map
                    for entryID in mdto.entryIDs {
                        if let e = insertedEntriesByID[entryID] {
                            meal.entries.append(e)
                            e.meal = meal
                        } else {
                            // If the entry wasn't in the backup's entries array (possible),
                            // we leave it unlinked. Optionally you could try to find an existing entry by ID.
                        }
                    }
                    mealsInserted += 1
                }

                // Attempt to save so changes are persisted right away
                do {
                    try modelContext.save()
                } catch {
                    // Propagate save failures
                    throw BackupError.importFailed(error)
                }
            }
        } catch {
            // If the performAndWait wrapper throws, propagate as importFailed
            if let be = error as? BackupError {
                throw be
            } else {
                throw BackupError.importFailed(error)
            }
        }

        return (entriesInserted, mealsInserted)
    }
}

// MARK: - ModelContext convenient performAndWait helper
// To avoid fragile Objective-C selector reflection and the compile-time issue you encountered,
// we provide a simple performAndWait implementation which executes the block directly on the
// current thread. If you are using a SwiftData runtime that exposes an async/synchronous
// perform API and you want to use it, you can extend this helper to call it conditionally.
fileprivate extension ModelContext {
    func performAndWait(_ block: () throws -> Void) rethrows {
        try block()
    }
}

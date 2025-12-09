//
//  OpenFoodFactsClient.swift
//  calorie_calculator_THING
//
//  Created by lewis mills on 09/12/2025.
//

import Foundation

/// Small helper client to fetch product info from world.openfoodfacts.org
enum OpenFoodFactsError: Error {
    case invalidBarcode
    case productNotFound
    case decodingFailed
    case networkError(Error)
}

/// Returned product info that we care about
struct OFFProductInfo {
    let productName: String?
    /// calories per serving if available
    let caloriesPerServing: Double?
    /// protein grams per serving if available
    let proteinsPerServing: Double?
    /// carbs grams per serving if available
    let carbsPerServing: Double?
    /// fat grams per serving if available (NEW)
    let fatPerServing: Double?
    /// human readable serving size, e.g. "1 slice (30 g)"
    let servingSize: String?
    let barcode: String
}

final class OpenFoodFactsClient {
    private static let base = "https://world.openfoodfacts.org/api/v0/product"

    /// Fetch product by barcode. Returns OFFProductInfo on success.
    static func fetchProduct(barcode: String) async throws -> OFFProductInfo {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OpenFoodFactsError.invalidBarcode }

        // Build URL: https://world.openfoodfacts.org/api/v0/product/{barcode}.json
        guard let url = URL(string: "\(base)/\(trimmed).json") else {
            throw OpenFoodFactsError.invalidBarcode
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw OpenFoodFactsError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OpenFoodFactsError.productNotFound
        }

        // Decode JSON (we only decode the bits we need)
        struct ProductResponse: Decodable {
            let status: Int
            let product: Product?
        }
        struct Product: Decodable {
            let product_name: String?
            let nutriments: Nutriments?
            let serving_size: String?
        }
        struct Nutriments: Decodable {
            // keys like "energy-kcal_serving" or "energy-kcal_100g"
            let energy_kcal_serving: Double?
            let energy_kcal_100g: Double?

            // proteins / carbs keys
            let proteins_serving: Double?
            let proteins_100g: Double?
            let carbohydrates_serving: Double?
            let carbohydrates_100g: Double?

            // fat keys (added)
            let fat_serving: Double?
            let fat_100g: Double?

            private enum CodingKeys: String, CodingKey {
                case energy_kcal_serving = "energy-kcal_serving"
                case energy_kcal_100g = "energy-kcal_100g"
                case proteins_serving = "proteins_serving"
                case proteins_100g = "proteins_100g"
                case carbohydrates_serving = "carbohydrates_serving"
                case carbohydrates_100g = "carbohydrates_100g"
                case fat_serving = "fat_serving"
                case fat_100g = "fat_100g"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)

                func decodeDouble(_ key: CodingKeys) -> Double? {
                    if let d = try? container.decodeIfPresent(Double.self, forKey: key) { return d }
                    if let s = try? container.decodeIfPresent(String.self, forKey: key) {
                        let cleaned = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
                        return Double(cleaned)
                    }
                    return nil
                }

                energy_kcal_serving = decodeDouble(.energy_kcal_serving)
                energy_kcal_100g = decodeDouble(.energy_kcal_100g)
                proteins_serving = decodeDouble(.proteins_serving)
                proteins_100g = decodeDouble(.proteins_100g)
                carbohydrates_serving = decodeDouble(.carbohydrates_serving)
                carbohydrates_100g = decodeDouble(.carbohydrates_100g)
                fat_serving = decodeDouble(.fat_serving)
                fat_100g = decodeDouble(.fat_100g)
            }
        }

        let decoder = JSONDecoder()
        let decoded: ProductResponse
        do {
            decoded = try decoder.decode(ProductResponse.self, from: data)
        } catch {
            throw OpenFoodFactsError.decodingFailed
        }

        guard decoded.status == 1, let product = decoded.product else {
            throw OpenFoodFactsError.productNotFound
        }

        var caloriesPerServing: Double? = nil
        var proteinsPerServing: Double? = nil
        var carbsPerServing: Double? = nil
        var fatPerServing: Double? = nil

        if let n = product.nutriments {
            // Prefer per-serving values; fall back to per-100g if present.
            caloriesPerServing = n.energy_kcal_serving ?? n.energy_kcal_100g
            proteinsPerServing = n.proteins_serving ?? n.proteins_100g
            carbsPerServing = n.carbohydrates_serving ?? n.carbohydrates_100g
            fatPerServing = n.fat_serving ?? n.fat_100g
        }

        let servingSize = product.serving_size

        return OFFProductInfo(
            productName: product.product_name,
            caloriesPerServing: caloriesPerServing,
            proteinsPerServing: proteinsPerServing,
            carbsPerServing: carbsPerServing,
            fatPerServing: fatPerServing,
            servingSize: servingSize,
            barcode: trimmed
        )
    }
}

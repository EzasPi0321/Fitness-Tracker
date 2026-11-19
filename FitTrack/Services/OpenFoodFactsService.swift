import Foundation

enum FoodLookupError: LocalizedError, Equatable {
    case invalidBarcode
    case notFound
    case badResponse(status: Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidBarcode: "That doesn't look like a valid product barcode."
        case .notFound: "This product isn't in the Open Food Facts database yet."
        case .badResponse(let status): "Open Food Facts returned an error (\(status)). Please try again."
        case .decoding: "The product data couldn't be read."
        }
    }
}

/// Client for the public Open Food Facts product API.
/// Docs: https://openfoodfacts.github.io/openfoodfacts-server/api/
struct OpenFoodFactsService: Sendable {
    var session: URLSession = .shared
    var baseURL = URL(string: "https://world.openfoodfacts.org/api/v0/product/")!

    func product(for rawBarcode: String) async throws -> FoodProduct {
        let barcode = rawBarcode.filter(\.isNumber)
        guard (6...14).contains(barcode.count) else { throw FoodLookupError.invalidBarcode }

        var request = URLRequest(url: baseURL.appendingPathComponent("\(barcode).json"))
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Open Food Facts asks every client to identify itself.
        request.setValue("FitTrack-iOS/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FoodLookupError.badResponse(status: -1) }
        if http.statusCode == 404 { throw FoodLookupError.notFound }
        guard (200..<300).contains(http.statusCode) else { throw FoodLookupError.badResponse(status: http.statusCode) }

        let decoded: OFFProductResponse
        do {
            decoded = try JSONDecoder().decode(OFFProductResponse.self, from: data)
        } catch {
            throw FoodLookupError.decoding
        }
        guard decoded.status == 1,
              let off = decoded.product,
              let product = FoodProduct(barcode: barcode, off: off) else {
            throw FoodLookupError.notFound
        }
        return product
    }
}

// MARK: - Codable models
//
// Open Food Facts is crowd-sourced: numbers sometimes arrive as strings ("12,5"), fields are
// missing or empty. Decoding is therefore lossy per-field instead of failing the whole product.

struct OFFProductResponse: Decodable {
    let status: Int
    let product: OFFProduct?

    private enum CodingKeys: String, CodingKey { case status, product }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = container.lossyDouble(forKey: .status).map { Int($0) } ?? 0
        product = try? container.decodeIfPresent(OFFProduct.self, forKey: .product)
    }
}

struct OFFProduct: Decodable {
    let productName: String?
    let genericName: String?
    let brands: String?
    let servingSize: String?
    let servingQuantity: Double?
    let imageFrontURL: URL?
    let nutriments: OFFNutriments?

    private enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case productNameEN = "product_name_en"
        case genericName = "generic_name"
        case brands
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
        case imageFrontURL = "image_front_url"
        case nutriments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        productName = c.lossyString(forKey: .productName) ?? c.lossyString(forKey: .productNameEN)
        genericName = c.lossyString(forKey: .genericName)
        brands = c.lossyString(forKey: .brands)
        servingSize = c.lossyString(forKey: .servingSize)
        servingQuantity = c.lossyDouble(forKey: .servingQuantity)
        imageFrontURL = c.lossyString(forKey: .imageFrontURL).flatMap(URL.init(string:))
        nutriments = try? c.decodeIfPresent(OFFNutriments.self, forKey: .nutriments)
    }
}

struct OFFNutriments: Decodable {
    let energyKcal100g: Double?
    let energyKcalServing: Double?
    let energyKJ100g: Double?
    let energyKJServing: Double?
    let proteins100g: Double?
    let proteinsServing: Double?
    let carbohydrates100g: Double?
    let carbohydratesServing: Double?
    let fat100g: Double?
    let fatServing: Double?

    private enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case energyKcalServing = "energy-kcal_serving"
        case energyKJ100g = "energy_100g"          // kJ
        case energyKJServing = "energy_serving"    // kJ
        case proteins100g = "proteins_100g"
        case proteinsServing = "proteins_serving"
        case carbohydrates100g = "carbohydrates_100g"
        case carbohydratesServing = "carbohydrates_serving"
        case fat100g = "fat_100g"
        case fatServing = "fat_serving"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        energyKcal100g = c.lossyDouble(forKey: .energyKcal100g)
        energyKcalServing = c.lossyDouble(forKey: .energyKcalServing)
        energyKJ100g = c.lossyDouble(forKey: .energyKJ100g)
        energyKJServing = c.lossyDouble(forKey: .energyKJServing)
        proteins100g = c.lossyDouble(forKey: .proteins100g)
        proteinsServing = c.lossyDouble(forKey: .proteinsServing)
        carbohydrates100g = c.lossyDouble(forKey: .carbohydrates100g)
        carbohydratesServing = c.lossyDouble(forKey: .carbohydratesServing)
        fat100g = c.lossyDouble(forKey: .fat100g)
        fatServing = c.lossyDouble(forKey: .fatServing)
    }

    var per100g: Nutrients? {
        guard let kcal = energyKcal100g ?? energyKJ100g.map({ $0 / 4.184 }) else { return nil }
        return Nutrients(calories: kcal,
                         protein: proteins100g ?? 0,
                         carbs: carbohydrates100g ?? 0,
                         fat: fat100g ?? 0).sanitized
    }

    var perServing: Nutrients? {
        guard let kcal = energyKcalServing ?? energyKJServing.map({ $0 / 4.184 }) else { return nil }
        return Nutrients(calories: kcal,
                         protein: proteinsServing ?? 0,
                         carbs: carbohydratesServing ?? 0,
                         fat: fatServing ?? 0).sanitized
    }
}

extension FoodProduct {
    init?(barcode: String, off: OFFProduct) {
        let per100g = off.nutriments?.per100g
        let perServing = off.nutriments?.perServing
        let name = off.productName ?? off.genericName
        guard name != nil || per100g != nil || perServing != nil else { return nil }

        let servingGrams = off.servingQuantity.flatMap { $0 > 0 ? $0 : nil }
        self.init(barcode: barcode,
                  name: name ?? "Product \(barcode)",
                  brand: off.brands?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) },
                  imageURL: off.imageFrontURL,
                  servingDescription: off.servingSize,
                  servingGrams: servingGrams,
                  per100g: per100g,
                  perServingReported: perServing,
                  source: .barcode)
    }
}

extension KeyedDecodingContainer {
    /// Decodes a number that may be encoded as a JSON number or a numeric string.
    func lossyDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value.isFinite ? value : nil
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            let normalized = string.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            return Double(normalized)
        }
        return nil
    }

    func lossyString(forKey key: Key) -> String? {
        guard let value = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

import XCTest
@testable import FitTrack

final class NutritionCalculatorTests: XCTestCase {
    func testMifflinStJeorMale() {
        // 10*80 + 6.25*180 - 5*30 + 5 = 1780
        XCTAssertEqual(NutritionCalculator.bmr(sex: .male, weightKg: 80, heightCm: 180, age: 30), 1780, accuracy: 0.001)
    }

    func testMifflinStJeorFemale() {
        // 10*60 + 6.25*165 - 5*25 - 161 = 1345.25
        XCTAssertEqual(NutritionCalculator.bmr(sex: .female, weightKg: 60, heightCm: 165, age: 25), 1345.25, accuracy: 0.001)
    }

    func testPlanMacrosAddUpToCalories() {
        let plan = NutritionCalculator.plan(sex: .male, age: 30, heightCm: 180, weightKg: 80,
                                            activity: .moderate, goal: .lose)
        XCTAssertEqual(plan.tdee, 1780 * 1.55, accuracy: 0.01)
        XCTAssertEqual(plan.targets.calories, 2260) // 2759 - 500 → rounded to 10
        XCTAssertEqual(plan.targets.protein, 160)   // 2.0 g/kg
        let macroKcal = plan.targets.protein * 4 + plan.targets.carbs * 4 + plan.targets.fat * 9
        XCTAssertEqual(macroKcal, plan.targets.calories, accuracy: 15)
    }

    func testPlanRespectsCalorieFloor() {
        let plan = NutritionCalculator.plan(sex: .female, age: 80, heightCm: 150, weightKg: 42,
                                            activity: .sedentary, goal: .lose)
        XCTAssertGreaterThanOrEqual(plan.targets.calories, 1200)
        XCTAssertGreaterThanOrEqual(plan.targets.carbs, 0)
    }
}

final class OpenFoodFactsDecodingTests: XCTestCase {
    func testDecodesStringNumbersAndDerivesServing() throws {
        let json = """
        {
          "status": 1,
          "code": "3017620422003",
          "product": {
            "product_name": "Nutella",
            "brands": "Ferrero, Nutella",
            "serving_size": "15 g",
            "serving_quantity": "15",
            "image_front_url": "",
            "nutriments": {
              "energy-kcal_100g": 539,
              "proteins_100g": "6,3",
              "carbohydrates_100g": 57.5,
              "fat_100g": 30.9
            }
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(OFFProductResponse.self, from: json)
        XCTAssertEqual(response.status, 1)
        let product = try XCTUnwrap(FoodProduct(barcode: "3017620422003", off: XCTUnwrap(response.product)))
        XCTAssertEqual(product.name, "Nutella")
        XCTAssertEqual(product.brand, "Ferrero")
        XCTAssertNil(product.imageURL)
        XCTAssertEqual(product.per100g?.protein ?? 0, 6.3, accuracy: 0.001)
        let serving = try XCTUnwrap(product.perServing)
        XCTAssertEqual(serving.calories, 539 * 0.15, accuracy: 0.01)
        XCTAssertEqual(product.nutrients(forGrams: 200)?.calories ?? 0, 1078, accuracy: 0.01)
    }

    func testFallsBackToKilojoules() throws {
        let json = #"{"status":1,"product":{"product_name":"Oats","nutriments":{"energy_100g":1500}}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(OFFProductResponse.self, from: json)
        let product = try XCTUnwrap(FoodProduct(barcode: "12345678", off: XCTUnwrap(response.product)))
        XCTAssertEqual(product.per100g?.calories ?? 0, 1500 / 4.184, accuracy: 0.01)
        XCTAssertNil(product.perServing)
    }

    func testNotFoundStatus() throws {
        let json = #"{"status":0,"status_verbose":"product not found"}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(OFFProductResponse.self, from: json)
        XCTAssertEqual(response.status, 0)
        XCTAssertNil(response.product)
    }
}

final class AIVisionDecodingTests: XCTestCase {
    func testDecodesFencedJSONAndDropsInvalidItems() throws {
        let raw = """
        ```json
        {"items":[
          {"name":"Grilled chicken","estimated_grams":150,"calories":248,"protein_g":46,"carbs_g":0,"fat_g":5.4,"confidence":0.9},
          {"name":"","estimated_grams":50,"calories":10,"protein_g":0,"carbs_g":2,"fat_g":0,"confidence":0.2},
          {"name":"Rice","estimated_grams":0,"calories":0,"protein_g":0,"carbs_g":0,"fat_g":0,"confidence":0.4}
        ],"notes":"Oil not visible."}
        ```
        """
        let analysis = try AIVisionService.decodeAnalysis(from: raw)
        XCTAssertEqual(analysis.items.count, 1)
        XCTAssertEqual(analysis.items.first?.name, "Grilled chicken")
        XCTAssertEqual(analysis.notes, "Oil not visible.")
    }

    func testReviewItemScalesWithGrams() {
        var item = ReviewItem(DetectedFood(name: "Rice", grams: 200, calories: 260, protein: 5, carbs: 56, fat: 0.6, confidence: 0.8))
        item.grams = 100
        XCTAssertEqual(item.nutrients.calories, 130, accuracy: 0.001)
        XCTAssertEqual(item.nutrients.carbs, 28, accuracy: 0.001)
    }
}

final class FoodEntryTests: XCTestCase {
    func testRescaleIsLinear() {
        let entry = FoodEntry(name: "Yogurt", meal: .breakfast, source: .manual, quantity: 1, unit: "cup",
                              grams: 245, nutrients: Nutrients(calories: 150, protein: 15, carbs: 8, fat: 6))
        entry.rescale(toQuantity: 1.5)
        XCTAssertEqual(entry.calories, 225, accuracy: 0.001)
        XCTAssertEqual(entry.grams ?? 0, 367.5, accuracy: 0.001)
        XCTAssertEqual(entry.portionDescription, "1.5 × cup")
    }

    func testSuggestedMeal() {
        let calendar = Calendar(identifier: .gregorian)
        func at(_ hour: Int) -> Date { calendar.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: hour))! }
        XCTAssertEqual(MealType.suggested(for: at(8), calendar: calendar), .breakfast)
        XCTAssertEqual(MealType.suggested(for: at(13), calendar: calendar), .lunch)
        XCTAssertEqual(MealType.suggested(for: at(19), calendar: calendar), .dinner)
        XCTAssertEqual(MealType.suggested(for: at(16), calendar: calendar), .snack)
    }
}

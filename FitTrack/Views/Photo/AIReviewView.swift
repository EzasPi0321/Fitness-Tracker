import SwiftData
import SwiftUI

/// An editable AI-detected item. Nutrition scales linearly with the edited gram weight.
struct ReviewItem: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var grams: Double
    let referenceGrams: Double
    let referenceNutrients: Nutrients
    let confidence: Double

    init(_ food: DetectedFood) {
        name = food.name
        grams = food.grams.rounded()
        referenceGrams = food.grams
        referenceNutrients = food.nutrients
        confidence = food.confidence
    }

    var nutrients: Nutrients {
        referenceGrams > 0 ? referenceNutrients * (grams / referenceGrams) : referenceNutrients
    }
}

struct AIReviewView: View {
    let logDate: Date
    var onLogged: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKit

    @State private var items: [ReviewItem]
    @State private var meal: MealType
    @State private var isSaving = false
    private let image: UIImage
    private let notes: String

    init(review: MealReview, logDate: Date, onLogged: @escaping () -> Void) {
        self.logDate = logDate
        self.onLogged = onLogged
        self.image = review.image
        self.notes = review.analysis.notes
        _items = State(initialValue: review.analysis.items.map(ReviewItem.init))
        _meal = State(initialValue: .suggested(for: logDate))
    }

    private var total: Nutrients { items.map(\.nutrients).sum() }

    var body: some View {
        List {
            Section {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .listRowInsets(EdgeInsets())
            } footer: {
                if let notes = notes.nilIfBlank { Text(notes) }
            }

            Section {
                ForEach($items) { $item in
                    ReviewItemRow(item: $item)
                }
                .onDelete { items.remove(atOffsets: $0) }
            } header: {
                Text("Detected Items")
            } footer: {
                Text("Swipe left to remove anything misidentified. Changing the weight rescales calories and macros.")
            }

            Section("Meal Total") { NutritionFactsRows(nutrients: total) }

            Section {
                Picker("Meal", selection: $meal) {
                    ForEach(MealType.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
            }
        }
        .navigationTitle("Review Estimate")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Log") { Task { await save() } }
                    .disabled(items.isEmpty || isSaving)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("No Items", systemImage: "fork.knife",
                                       description: Text("All detected items were removed."))
            }
        }
    }

    private func save() async {
        isSaving = true
        let entries = items.compactMap { item -> FoodEntry? in
            guard let name = item.name.nilIfBlank, item.grams > 0 else { return nil }
            return FoodEntry(name: name, meal: meal, source: .photoAI, consumedAt: logDate,
                             quantity: item.grams, unit: "g", grams: item.grams, nutrients: item.nutrients)
        }
        await FoodLogger(context: modelContext, healthKit: healthKit).log(entries)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onLogged()
    }
}

private struct ReviewItemRow: View {
    @Binding var item: ReviewItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Food name", text: $item.name)
                    .font(.headline)
                if item.confidence < 0.5 {
                    Text("Low confidence")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            Stepper(value: $item.grams, in: 5...3000, step: 10) {
                HStack(spacing: 4) {
                    TextField("Grams", value: $item.grams, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 64)
                        .monospacedDigit()
                    Text("g").foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("\(item.nutrients.calories.wholeNumber) kcal")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                MacroInlineText(nutrients: item.nutrients)
            }
        }
        .padding(.vertical, 4)
    }
}

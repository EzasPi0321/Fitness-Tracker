import SwiftData
import SwiftUI

enum PortionUnit: String, CaseIterable, Identifiable {
    case servings, grams
    var id: String { rawValue }
    var title: String { self == .servings ? "Servings" : "Grams" }
}

struct ProductDetailSheet: View {
    let product: FoodProduct
    let logDate: Date
    var onLogged: () -> Void
    var onNeedsManualEntry: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKit

    @State private var unit: PortionUnit
    @State private var servings: Double = 1
    @State private var grams: Double
    @State private var meal: MealType
    @State private var isSaving = false

    init(product: FoodProduct,
         logDate: Date,
         onLogged: @escaping () -> Void,
         onNeedsManualEntry: @escaping () -> Void) {
        self.product = product
        self.logDate = logDate
        self.onLogged = onLogged
        self.onNeedsManualEntry = onNeedsManualEntry
        _unit = State(initialValue: product.perServing != nil ? .servings : .grams)
        _grams = State(initialValue: product.servingGrams ?? 100)
        _meal = State(initialValue: .suggested(for: logDate))
    }

    private var availableUnits: [PortionUnit] {
        var units: [PortionUnit] = []
        if product.perServing != nil { units.append(.servings) }
        if product.supportsGrams { units.append(.grams) }
        return units
    }

    private var nutrients: Nutrients? {
        switch unit {
        case .servings: product.nutrients(forServings: servings)
        case .grams: product.nutrients(forGrams: grams)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { header }

                if product.hasNutrition {
                    Section("Portion") {
                        if availableUnits.count > 1 {
                            Picker("Unit", selection: $unit) {
                                ForEach(availableUnits) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        switch unit {
                        case .servings:
                            Stepper(value: $servings, in: 0.25...50, step: 0.25) {
                                VStack(alignment: .leading) {
                                    Text("\(servings.formatted(.number.precision(.fractionLength(0...2)))) × serving")
                                        .monospacedDigit()
                                    Text(product.servingLabel).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        case .grams:
                            Stepper(value: $grams, in: 1...5000, step: 5) {
                                HStack(spacing: 4) {
                                    TextField("Grams", value: $grams, format: .number.precision(.fractionLength(0...1)))
                                        .keyboardType(.decimalPad)
                                        .frame(maxWidth: 80)
                                        .monospacedDigit()
                                    Text("g").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if let nutrients {
                        Section {
                            NutritionFactsRows(nutrients: nutrients)
                        } header: {
                            Text("Nutrition")
                        } footer: {
                            if product.source == .barcode {
                                Text("Data from Open Food Facts. Values are community-contributed.")
                            }
                        }
                    }

                    Section {
                        Picker("Meal", selection: $meal) {
                            ForEach(MealType.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                        }
                    }
                } else {
                    Section {
                        Label("Nutrition information is missing for this product.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Button("Enter Nutrition Manually") {
                            onNeedsManualEntry()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await save() } }
                        .disabled(nutrients == nil || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(spacing: 14) {
            AsyncImage(url: product.imageURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Image(systemName: product.source == .customFood ? "star.fill" : "takeoutbag.and.cup.and.straw.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 64)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(product.name).font(.headline).lineLimit(2)
                if let brand = product.brand {
                    Text(brand).font(.subheadline).foregroundStyle(.secondary)
                }
                if let per100 = product.per100g {
                    Text("\(per100.calories.wholeNumber) kcal / 100 g")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func save() async {
        guard let nutrients else { return }
        isSaving = true
        let entry: FoodEntry
        switch unit {
        case .servings:
            entry = FoodEntry(name: product.name, brand: product.brand, barcode: product.barcode,
                              meal: meal, source: product.source, consumedAt: logDate,
                              quantity: servings, unit: product.servingLabel,
                              grams: product.servingGrams.map { $0 * servings }, nutrients: nutrients)
        case .grams:
            entry = FoodEntry(name: product.name, brand: product.brand, barcode: product.barcode,
                              meal: meal, source: product.source, consumedAt: logDate,
                              quantity: grams, unit: "g", grams: grams, nutrients: nutrients)
        }
        await FoodLogger(context: modelContext, healthKit: healthKit).log([entry])
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onLogged()
        dismiss()
    }
}

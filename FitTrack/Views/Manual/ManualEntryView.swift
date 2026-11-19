import SwiftData
import SwiftUI

/// Manual food entry. Also the fallback for unknown barcodes — saving with "Save to My Foods"
/// caches the barcode locally so the next scan resolves instantly.
struct ManualEntryView: View {
    let logDate: Date
    var barcode: String?
    var onLogged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKit
    @Query private var customFoods: [CustomFood]

    @State private var name: String
    @State private var brand: String
    @State private var servingDescription = "serving"
    @State private var servingGrams: Double?
    @State private var servings: Double = 1
    @State private var calories: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var meal: MealType
    @State private var saveAsCustomFood: Bool
    @State private var selectedCustomFood: CustomFood?
    @State private var isSaving = false

    init(logDate: Date,
         barcode: String? = nil,
         prefillName: String? = nil,
         prefillBrand: String? = nil,
         onLogged: @escaping () -> Void = {}) {
        self.logDate = logDate
        self.barcode = barcode
        self.onLogged = onLogged
        _name = State(initialValue: prefillName ?? "")
        _brand = State(initialValue: prefillBrand ?? "")
        _meal = State(initialValue: .suggested(for: logDate))
        _saveAsCustomFood = State(initialValue: barcode != nil)
        _customFoods = Query(sort: \CustomFood.lastUsedAt, order: .reverse)
    }

    private var perServing: Nutrients {
        Nutrients(calories: calories ?? 0, protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0)
    }

    private var isValid: Bool {
        name.nilIfBlank != nil && (calories ?? -1) >= 0 && servings > 0
    }

    var body: some View {
        Form {
            if barcode == nil, !customFoods.isEmpty {
                Section {
                    NavigationLink {
                        CustomFoodListView { apply($0) }
                    } label: {
                        Label("Choose from My Foods", systemImage: "star")
                    }
                }
            }

            Section("Food") {
                TextField("Name (required)", text: $name)
                    .textInputAutocapitalization(.words)
                TextField("Brand", text: $brand)
                    .textInputAutocapitalization(.words)
                if let barcode {
                    LabeledContent("Barcode", value: barcode)
                        .monospacedDigit()
                }
            }

            Section {
                LabeledContent("Serving") {
                    TextField("e.g. 1 cup, 1 bar", text: $servingDescription)
                        .multilineTextAlignment(.trailing)
                }
                NumberField(title: "Serving Weight", value: $servingGrams, unit: "g")
                Stepper(value: $servings, in: 0.25...50, step: 0.25) {
                    LabeledContent("Servings Eaten",
                                   value: servings.formatted(.number.precision(.fractionLength(0...2))))
                }
            } header: {
                Text("Serving")
            }

            Section("Nutrition per Serving") {
                NumberField(title: "Calories", value: $calories, unit: "kcal", fractionDigits: 0...0)
                NumberField(title: "Protein", value: $protein, unit: "g")
                NumberField(title: "Carbs", value: $carbs, unit: "g")
                NumberField(title: "Fat", value: $fat, unit: "g")
            }

            Section {
                Picker("Meal", selection: $meal) {
                    ForEach(MealType.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
                Toggle("Save to My Foods", isOn: $saveAsCustomFood)
            } footer: {
                if servings != 1, calories != nil {
                    Text("Total: \((perServing * servings).calories.wholeNumber) kcal for \(servings.formatted()) servings")
                }
            }
        }
        .navigationTitle("Manual Entry")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { Task { await save() } }
                    .disabled(!isValid || isSaving)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
            }
        }
    }

    private func apply(_ food: CustomFood) {
        selectedCustomFood = food
        name = food.name
        brand = food.brand ?? ""
        servingDescription = food.servingDescription
        servingGrams = food.servingGrams
        calories = food.calories
        protein = food.protein
        carbs = food.carbs
        fat = food.fat
        saveAsCustomFood = false
    }

    private func save() async {
        guard isValid, let trimmedName = name.nilIfBlank else { return }
        isSaving = true
        let unitLabel = servingDescription.nilIfBlank ?? "serving"
        let source: EntrySource = selectedCustomFood != nil ? .customFood : (barcode != nil ? .barcode : .manual)

        let entry = FoodEntry(name: trimmedName,
                              brand: brand.nilIfBlank,
                              barcode: barcode,
                              meal: meal,
                              source: source,
                              consumedAt: logDate,
                              quantity: servings,
                              unit: unitLabel,
                              grams: servingGrams.map { $0 * servings },
                              nutrients: perServing * servings)

        if saveAsCustomFood { upsertCustomFood(name: trimmedName, unitLabel: unitLabel) }
        selectedCustomFood?.markUsed()

        await FoodLogger(context: modelContext, healthKit: healthKit).log([entry])
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onLogged()
        dismiss()
    }

    private func upsertCustomFood(name: String, unitLabel: String) {
        var existing: CustomFood?
        if let barcode {
            let code: String? = barcode
            var descriptor = FetchDescriptor<CustomFood>(predicate: #Predicate { $0.barcode == code })
            descriptor.fetchLimit = 1
            existing = try? modelContext.fetch(descriptor).first
        }
        if let existing {
            existing.name = name
            existing.brand = brand.nilIfBlank
            existing.servingDescription = unitLabel
            existing.servingGrams = servingGrams
            existing.perServing = perServing
            existing.markUsed()
        } else {
            let food = CustomFood(name: name, brand: brand.nilIfBlank, barcode: barcode,
                                  servingDescription: unitLabel, servingGrams: servingGrams,
                                  perServing: perServing)
            food.markUsed()
            modelContext.insert(food)
        }
    }
}

struct CustomFoodListView: View {
    var onSelect: (CustomFood) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomFood.lastUsedAt, order: .reverse) private var foods: [CustomFood]
    @State private var searchText = ""

    private var filtered: [CustomFood] {
        guard let query = searchText.nilIfBlank else { return foods }
        return foods.filter {
            $0.name.localizedCaseInsensitiveContains(query) || ($0.brand?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        List {
            ForEach(filtered) { food in
                Button {
                    onSelect(food)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(food.name).foregroundStyle(.primary)
                        Text("\(food.servingDescription) · \(food.calories.wholeNumber) kcal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets { modelContext.delete(filtered[index]) }
            }
        }
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, prompt: "Search My Foods")
        .navigationTitle("My Foods")
    }
}

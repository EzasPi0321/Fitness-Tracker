import SwiftData
import SwiftUI

struct EditEntryView: View {
    let entry: FoodEntry

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKit

    @State private var quantity: Double
    @State private var meal: MealType
    @State private var time: Date
    @State private var confirmDelete = false

    init(entry: FoodEntry) {
        self.entry = entry
        _quantity = State(initialValue: entry.quantity)
        _meal = State(initialValue: entry.meal)
        _time = State(initialValue: entry.consumedAt)
    }

    private var isGrams: Bool { entry.unit == "g" }
    private var step: Double { isGrams ? 5 : 0.25 }
    private var preview: Nutrients {
        entry.quantity > 0 ? entry.nutrients * (quantity / entry.quantity) : entry.nutrients
    }
    private var logger: FoodLogger { FoodLogger(context: modelContext, healthKit: healthKit) }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(.headline)
                    if let brand = entry.brand { Text(brand).font(.subheadline).foregroundStyle(.secondary) }
                }
            }

            Section("Portion") {
                Stepper(value: $quantity, in: step...5000, step: step) {
                    HStack(spacing: 4) {
                        TextField("Amount", value: $quantity, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 80)
                            .monospacedDigit()
                        Text(isGrams ? "g" : "× \(entry.unit)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Section("Nutrition") { NutritionFactsRows(nutrients: preview) }

            Section {
                Picker("Meal", selection: $meal) {
                    ForEach(MealType.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
                DatePicker("Time", selection: $time)
            }

            Section {
                Button("Delete Entry", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle("Edit Entry")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(quantity <= 0)
            }
        }
        .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    await logger.delete(entry)
                    dismiss()
                }
            }
        }
    }

    private func save() async {
        entry.rescale(toQuantity: quantity)
        entry.meal = meal
        entry.consumedAt = time
        await logger.update(entry)
        dismiss()
    }
}

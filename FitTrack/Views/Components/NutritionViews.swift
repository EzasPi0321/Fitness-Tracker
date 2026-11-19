import SwiftUI

/// Calories + macros as `LabeledContent` rows for use inside a Form/List section.
struct NutritionFactsRows: View {
    let nutrients: Nutrients

    var body: some View {
        LabeledContent("Calories") {
            Text("\(nutrients.calories.wholeNumber) kcal").monospacedDigit()
        }
        ForEach(Macro.allCases) { macro in
            LabeledContent {
                Text("\(macro.value(in: nutrients).formatted(.number.precision(.fractionLength(0...1)))) g")
                    .monospacedDigit()
            } label: {
                Label {
                    Text(macro.title)
                } icon: {
                    Circle().fill(macro.color).frame(width: 10, height: 10)
                }
            }
        }
    }
}

/// Compact "P 12 · C 30 · F 5" line.
struct MacroInlineText: View {
    let nutrients: Nutrients

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Macro.allCases) { macro in
                HStack(spacing: 2) {
                    Text(macro.shortTitle).foregroundStyle(macro.color).fontWeight(.semibold)
                    Text(macro.value(in: nutrients).wholeNumber)
                }
            }
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Protein \(nutrients.protein.wholeNumber) grams, carbs \(nutrients.carbs.wholeNumber) grams, fat \(nutrients.fat.wholeNumber) grams"
        )
    }
}

/// Numeric text field row with a trailing unit label.
struct NumberField: View {
    let title: String
    @Binding var value: Double?
    var unit: String
    var fractionDigits: ClosedRange<Int> = 0...1

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("0", value: $value, format: .number.precision(.fractionLength(fractionDigits)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }
}

struct ChartCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

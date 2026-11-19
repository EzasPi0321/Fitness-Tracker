import SwiftUI

struct DailySummaryCard: View {
    let consumed: Nutrients
    let targets: Nutrients
    let activeEnergy: Double
    let includeActiveEnergy: Bool
    let showsActiveEnergy: Bool

    private var budget: Double { targets.calories + (includeActiveEnergy ? activeEnergy : 0) }
    private var remaining: Double { budget - consumed.calories }
    private var progress: Double { budget > 0 ? consumed.calories / budget : 0 }

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                ZStack {
                    ProgressRing(progress: progress, lineWidth: 16)
                    VStack(spacing: 0) {
                        Text(abs(remaining).wholeNumber)
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(remaining >= 0 ? "kcal left" : "kcal over")
                            .font(.caption)
                            .foregroundStyle(remaining >= 0 ? Color.secondary : Theme.over)
                    }
                    .padding(.horizontal, 24)
                }
                .frame(width: 148, height: 148)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Calories")
                .accessibilityValue("\(consumed.calories.wholeNumber) of \(budget.wholeNumber) kilocalories eaten, \(abs(remaining).wholeNumber) \(remaining >= 0 ? "remaining" : "over")")

                VStack(alignment: .leading, spacing: 14) {
                    StatLine(title: "Goal", value: targets.calories, symbol: "flag.fill", tint: .secondary)
                    StatLine(title: "Eaten", value: consumed.calories, symbol: "fork.knife", tint: Theme.calories)
                    if showsActiveEnergy {
                        StatLine(title: includeActiveEnergy ? "Active (+)" : "Active",
                                 value: activeEnergy, symbol: "flame.fill", tint: .orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top) {
                ForEach(Macro.allCases) { macro in
                    MacroGauge(macro: macro,
                               consumed: macro.value(in: consumed),
                               target: macro.value(in: targets))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 12)
    }
}

private struct StatLine: View {
    let title: String
    let value: Double
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text("\(value.wholeNumber) kcal")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Native `Gauge` in the circular-capacity style, tinted per macro.
struct MacroGauge: View {
    let macro: Macro
    let consumed: Double
    let target: Double

    var body: some View {
        let upperBound = max(target, 1)
        VStack(spacing: 6) {
            Gauge(value: min(consumed, upperBound), in: 0...upperBound) {
                Text(macro.shortTitle)
            } currentValueLabel: {
                Text(consumed.wholeNumber)
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(consumed > target * 1.1 ? Theme.over : macro.color)

            Text(macro.title)
                .font(.caption.weight(.semibold))
            Text("\(consumed.wholeNumber) / \(target.wholeNumber) g")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(macro.title)
        .accessibilityValue("\(consumed.wholeNumber) of \(target.wholeNumber) grams")
    }
}

#Preview {
    List {
        DailySummaryCard(consumed: Nutrients(calories: 1450, protein: 98, carbs: 160, fat: 48),
                         targets: Nutrients(calories: 2100, protein: 140, carbs: 230, fat: 70),
                         activeEnergy: 420, includeActiveEnergy: true, showsActiveEnergy: true)
    }
}

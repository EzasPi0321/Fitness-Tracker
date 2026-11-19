import Charts
import SwiftData
import SwiftUI

enum TrendRange: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, quarter = 90

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .week: "7D"
        case .month: "30D"
        case .quarter: "90D"
        }
    }

    var axisStride: Int {
        switch self {
        case .week: 1
        case .month: 7
        case .quarter: 30
        }
    }
}

struct DailyIntake: Identifiable, Hashable {
    let date: Date
    let nutrients: Nutrients
    let entryCount: Int
    var id: Date { date }
    var calories: Double { nutrients.calories }
}

struct TrendsView: View {
    let profile: UserProfile

    @Query private var entries: [FoodEntry]
    @Query(sort: \WeightEntry.date) private var localWeights: [WeightEntry]
    @Environment(HealthKitManager.self) private var healthKit
    @AppStorage(SettingsKey.healthKitEnabled) private var healthKitEnabled = false

    @State private var range: TrendRange = .week
    @State private var healthWeights: [WeightSample] = []
    @State private var activeByDay: [Date: Double] = [:]
    @State private var showLogWeight = false
    @State private var reloadToken = 0

    init(profile: UserProfile) {
        self.profile = profile
        let cutoff = Date.now.startOfDay.adding(days: -TrendRange.quarter.rawValue)
        _entries = Query(filter: #Predicate<FoodEntry> { $0.consumedAt >= cutoff },
                         sort: \FoodEntry.consumedAt)
    }

    private var rangeStart: Date { Date.now.startOfDay.adding(days: -(range.rawValue - 1)) }

    private var dailyIntake: [DailyIntake] {
        let start = rangeStart
        let grouped = Dictionary(grouping: entries.filter { $0.consumedAt >= start }) { $0.consumedAt.startOfDay }
        return (0..<range.rawValue).map { offset in
            let day = start.adding(days: offset)
            let dayEntries = grouped[day] ?? []
            return DailyIntake(date: day, nutrients: dayEntries.map(\.nutrients).sum(), entryCount: dayEntries.count)
        }
    }

    private var weightPoints: [WeightSample] {
        let start = rangeStart
        if healthKitEnabled, !healthWeights.isEmpty {
            return healthWeights.filter { $0.date >= start }
        }
        return localWeights
            .filter { $0.date >= start }
            .map { WeightSample(id: $0.id, date: $0.date, kilograms: $0.kilograms) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Range", selection: $range) {
                        ForEach(TrendRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    calorieCard
                    macroCard
                    weightCard
                }
                .padding()
            }
            .background(Theme.screenBackground)
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showLogWeight = true } label: {
                        Label("Log Weight", systemImage: "scalemass")
                    }
                }
            }
            .task(id: "\(range.rawValue)-\(healthKitEnabled)-\(reloadToken)") { await loadHealthData() }
            .refreshable { await loadHealthData() }
            .sheet(isPresented: $showLogWeight) {
                NavigationStack {
                    LogWeightView(profile: profile) { reloadToken += 1 }
                }
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: Cards

    private var loggedDays: [DailyIntake] { dailyIntake.filter { $0.entryCount > 0 } }

    private var calorieCard: some View {
        let logged = loggedDays
        let average = logged.isEmpty ? 0 : logged.map(\.calories).reduce(0, +) / Double(logged.count)
        let onTarget = logged.filter { abs($0.calories - profile.calorieTarget) <= profile.calorieTarget * 0.1 }.count
        let activeValues = dailyIntake.compactMap { activeByDay[$0.date] }
        let averageActive = activeValues.isEmpty ? nil : activeValues.reduce(0, +) / Double(activeValues.count)

        return ChartCard(title: "Calorie Intake",
                         subtitle: logged.isEmpty ? "No meals logged in this period" : "Average \(average.wholeNumber) kcal/day") {
            CalorieTrendChart(data: dailyIntake, target: profile.calorieTarget, range: range)
            HStack {
                StatTile(title: "Days Logged", value: "\(logged.count)/\(range.rawValue)")
                StatTile(title: "Within ±10%", value: "\(onTarget)")
                if healthKitEnabled, let averageActive {
                    StatTile(title: "Avg Active", value: "\(averageActive.wholeNumber) kcal")
                }
            }
        }
    }

    private var macroCard: some View {
        let logged = loggedDays
        let average = logged.isEmpty ? Nutrients.zero : logged.map(\.nutrients).sum() * (1 / Double(logged.count))
        return ChartCard(title: "Average Macros", subtitle: "Per logged day vs. target") {
            Chart {
                ForEach(Macro.allCases) { macro in
                    BarMark(x: .value("Grams", macro.value(in: average)),
                            y: .value("Macro", macro.title))
                        .foregroundStyle(macro.color.gradient)
                        .cornerRadius(4)
                        .annotation(position: .trailing) {
                            Text("\(macro.value(in: average).wholeNumber) / \(macro.value(in: profile.targets).wholeNumber) g")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    // Target tick
                    PointMark(x: .value("Target", macro.value(in: profile.targets)),
                              y: .value("Macro", macro.title))
                        .symbol {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.primary.opacity(0.6))
                                .frame(width: 3, height: 22)
                        }
                }
            }
            .chartXScale(domain: 0...macroAxisMax(average))
            .chartXAxis(.hidden)
            .frame(height: 130)
        }
    }

    private func macroAxisMax(_ average: Nutrients) -> Double {
        let values = Macro.allCases.flatMap { [$0.value(in: average), $0.value(in: profile.targets)] }
        return max(values.max() ?? 1, 1) * 1.45 // room for the trailing annotation
    }

    private var weightCard: some View {
        let points = weightPoints
        let usesMetric = profile.usesMetric
        let subtitle: String = {
            guard let first = points.first, let last = points.last else { return "No weigh-ins in this period" }
            let delta = (last.kilograms - first.kilograms) * (usesMetric ? 1 : UnitConversion.poundsPerKilogram)
            let unit = usesMetric ? "kg" : "lb"
            let sign = delta > 0 ? "+" : ""
            return "\(Self.formatWeight(last.kilograms, metric: usesMetric)) · \(sign)\(delta.formatted(.number.precision(.fractionLength(1)))) \(unit)"
        }()

        return ChartCard(title: "Body Weight", subtitle: subtitle) {
            if points.isEmpty {
                Button { showLogWeight = true } label: {
                    Label("Log Your Weight", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.vertical, 24)
            } else {
                WeightTrendChart(points: points, usesMetric: usesMetric, range: range)
            }
        }
    }

    static func formatWeight(_ kilograms: Double, metric: Bool) -> String {
        let value = metric ? kilograms : kilograms * UnitConversion.poundsPerKilogram
        return "\(value.formatted(.number.precision(.fractionLength(1)))) \(metric ? "kg" : "lb")"
    }

    private func loadHealthData() async {
        guard healthKitEnabled, healthKit.isAvailable else {
            healthWeights = []
            activeByDay = [:]
            return
        }
        let start = Date.now.startOfDay.adding(days: -TrendRange.quarter.rawValue)
        healthWeights = (try? await healthKit.bodyMassHistory(since: start)) ?? []
        activeByDay = (try? await healthKit.dailyActiveEnergy(from: rangeStart, to: .now)) ?? [:]
    }
}

private struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct CalorieTrendChart: View {
    let data: [DailyIntake]
    let target: Double
    let range: TrendRange

    @State private var selectedDate: Date?

    private var selected: DailyIntake? {
        guard let selectedDate else { return nil }
        return data.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private var axisFormat: Date.FormatStyle {
        range == .week
            ? Date.FormatStyle.dateTime.weekday(.narrow)
            : Date.FormatStyle.dateTime.month(.defaultDigits).day()
    }

    var body: some View {
        Chart {
            ForEach(data) { day in
                BarMark(x: .value("Day", day.date, unit: .day),
                        y: .value("Calories", day.calories))
                    .foregroundStyle(day.calories > target * 1.1 ? Theme.over.gradient : Theme.calories.gradient)
                    .cornerRadius(range == .quarter ? 1 : 4)
                    .opacity(selected == nil || selected?.date == day.date ? 1 : 0.4)
            }

            RuleMark(y: .value("Goal", target))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Goal \(target.wholeNumber)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

            if let selected {
                RuleMark(x: .value("Selected", selected.date, unit: .day))
                    .foregroundStyle(.gray.opacity(0.25))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(selected.calories.wholeNumber) kcal")
                                .font(.caption.weight(.semibold))
                            MacroInlineText(nutrients: selected.nutrients)
                        }
                        .padding(8)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.12), radius: 4)
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: range.axisStride)) { _ in
                AxisGridLine()
                AxisValueLabel(format: axisFormat, centered: range == .week)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .frame(height: 220)
        .accessibilityLabel("Daily calorie intake chart")
    }
}

struct WeightTrendChart: View {
    let points: [WeightSample]
    let usesMetric: Bool
    let range: TrendRange

    private func display(_ kilograms: Double) -> Double {
        usesMetric ? kilograms : kilograms * UnitConversion.poundsPerKilogram
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map { display($0.kilograms) }
        let low = (values.min() ?? 0) - 1
        let high = (values.max() ?? 1) + 1
        return low...high
    }

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Date", point.date),
                     y: .value("Weight", display(point.kilograms)))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.indigo)
            PointMark(x: .value("Date", point.date),
                      y: .value("Weight", display(point.kilograms)))
                .foregroundStyle(Color.indigo)
                .symbolSize(points.count > 30 ? 12 : 36)
        }
        .chartYScale(domain: yDomain)
        .chartYAxisLabel(usesMetric ? "kg" : "lb")
        .chartXScale(domain: Date.now.startOfDay.adding(days: -(range.rawValue - 1))...Date.now)
        .frame(height: 200)
        .accessibilityLabel("Body weight chart")
    }
}

struct LogWeightView: View {
    let profile: UserProfile
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKit
    @AppStorage(SettingsKey.healthKitEnabled) private var healthKitEnabled = false

    @State private var weight: Double?
    @State private var date = Date.now
    @State private var isSaving = false

    init(profile: UserProfile, onSaved: @escaping () -> Void) {
        self.profile = profile
        self.onSaved = onSaved
        let display = profile.usesMetric ? profile.weightKg : profile.weightKg * UnitConversion.poundsPerKilogram
        _weight = State(initialValue: (display * 10).rounded() / 10)
    }

    var body: some View {
        Form {
            NumberField(title: "Weight", value: $weight, unit: profile.usesMetric ? "kg" : "lb")
            DatePicker("Date", selection: $date, in: ...Date.now)
        }
        .navigationTitle("Log Weight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled((weight ?? 0) <= 0 || isSaving)
            }
        }
    }

    private func save() async {
        guard let weight, weight > 0 else { return }
        isSaving = true
        let kilograms = profile.usesMetric ? weight : weight / UnitConversion.poundsPerKilogram

        // Keep the profile weight in sync with the most recent weigh-in.
        var latest = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        latest.fetchLimit = 1
        let latestDate = (try? modelContext.fetch(latest).first?.date) ?? .distantPast
        modelContext.insert(WeightEntry(date: date, kilograms: kilograms))
        if date >= latestDate { profile.weightKg = kilograms }
        try? modelContext.save()

        if healthKitEnabled {
            do { try await healthKit.saveBodyMass(kilograms: kilograms, date: date) } catch { healthKit.report(error) }
        }
        onSaved()
        dismiss()
    }
}

#if DEBUG
#Preview {
    TrendsView(profile: PreviewData.profile)
        .modelContainer(PreviewData.container)
        .environment(HealthKitManager())
}
#endif

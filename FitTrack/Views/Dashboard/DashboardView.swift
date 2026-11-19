import SwiftData
import SwiftUI

enum LogAction: String, Identifiable {
    case scan, snap, manual
    var id: String { rawValue }
}

struct DashboardView: View {
    let profile: UserProfile

    @State private var selectedDate = Date.now.startOfDay
    @State private var isScanning = false
    @State private var sheetAction: LogAction?

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    private var title: String {
        if isToday { return "Today" }
        if Calendar.current.isDateInYesterday(selectedDate) { return "Yesterday" }
        return selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    var body: some View {
        NavigationStack {
            DayLogView(date: selectedDate, profile: profile)
                .navigationTitle(title)
                .toolbar { dateToolbar }
                .overlay(alignment: .bottomTrailing) {
                    QuickAddButton { action in
                        if action == .scan { isScanning = true } else { sheetAction = action }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
                }
        }
        .fullScreenCover(isPresented: $isScanning) {
            ScanFlowView(logDate: .logTimestamp(for: selectedDate))
        }
        .sheet(item: $sheetAction) { action in
            switch action {
            case .snap: SnapMealView(logDate: .logTimestamp(for: selectedDate))
            case .manual: NavigationStack { ManualEntryView(logDate: .logTimestamp(for: selectedDate)) }
            case .scan: EmptyView()
            }
        }
    }

    @ToolbarContentBuilder
    private var dateToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !isToday {
                Button("Today") { withAnimation { selectedDate = Date.now.startOfDay } }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                withAnimation { selectedDate = selectedDate.adding(days: -1) }
            } label: {
                Label("Previous Day", systemImage: "chevron.left")
            }
            Button {
                withAnimation { selectedDate = selectedDate.adding(days: 1) }
            } label: {
                Label("Next Day", systemImage: "chevron.right")
            }
            .disabled(isToday)
        }
    }
}

/// Floating action button offering the three ways to log food.
struct QuickAddButton: View {
    var onSelect: (LogAction) -> Void

    var body: some View {
        Menu {
            Button { onSelect(.scan) } label: { Label("Scan Barcode", systemImage: "barcode.viewfinder") }
            Button { onSelect(.snap) } label: { Label("Snap Meal", systemImage: "camera.viewfinder") }
            Button { onSelect(.manual) } label: { Label("Manual Entry", systemImage: "square.and.pencil") }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Circle().fill(Color.accentColor.gradient))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .accessibilityLabel("Log Food")
    }
}

/// The list for a single day. Built with an init-time `@Query` filtered to that day.
struct DayLogView: View {
    let date: Date
    let profile: UserProfile

    @Query private var entries: [FoodEntry]
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKit
    @AppStorage(SettingsKey.healthKitEnabled) private var healthKitEnabled = false
    @AppStorage(SettingsKey.addActiveEnergyToBudget) private var addActiveEnergy = false

    @State private var expandedMeals = Set(MealType.allCases)
    @State private var activeEnergy: Double = 0
    @State private var workouts: [WorkoutSummary] = []
    @State private var editingEntry: FoodEntry?

    init(date: Date, profile: UserProfile) {
        self.date = date
        self.profile = profile
        let bounds = date.dayBounds
        let start = bounds.start
        let end = bounds.end
        _entries = Query(filter: #Predicate<FoodEntry> { $0.consumedAt >= start && $0.consumedAt < end },
                         sort: \FoodEntry.consumedAt)
    }

    private var consumed: Nutrients { entries.map(\.nutrients).sum() }

    var body: some View {
        List {
            Section {
                DailySummaryCard(consumed: consumed,
                                 targets: profile.targets,
                                 activeEnergy: activeEnergy,
                                 includeActiveEnergy: healthKitEnabled && addActiveEnergy,
                                 showsActiveEnergy: healthKitEnabled)
            }

            ForEach(MealType.allCases) { meal in
                let mealEntries = entries.filter { $0.meal == meal }
                Section {
                    DisclosureGroup(isExpanded: expansionBinding(for: meal)) {
                        if mealEntries.isEmpty {
                            Text("Nothing logged yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(mealEntries) { entry in
                            Button { editingEntry = entry } label: { FoodEntryRow(entry: entry) }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task { await logger.delete(entry) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } label: {
                        MealHeader(meal: meal, calories: mealEntries.map(\.calories).reduce(0, +))
                    }
                }
            }

            if healthKitEnabled, !workouts.isEmpty {
                Section("Workouts") {
                    ForEach(workouts) { WorkoutRow(workout: $0) }
                }
            }

            // Leave room so the floating button never covers the last row.
            Color.clear.frame(height: 64).listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .task(id: "\(date.timeIntervalSince1970)-\(healthKitEnabled)") { await loadHealthData() }
        .refreshable { await loadHealthData() }
        .sheet(item: $editingEntry) { entry in
            NavigationStack { EditEntryView(entry: entry) }
        }
    }

    private var logger: FoodLogger { FoodLogger(context: modelContext, healthKit: healthKit) }

    private func expansionBinding(for meal: MealType) -> Binding<Bool> {
        Binding(
            get: { expandedMeals.contains(meal) },
            set: { isExpanded in
                if isExpanded { expandedMeals.insert(meal) } else { expandedMeals.remove(meal) }
            }
        )
    }

    private func loadHealthData() async {
        guard healthKitEnabled, healthKit.isAvailable else {
            activeEnergy = 0
            workouts = []
            return
        }
        activeEnergy = (try? await healthKit.activeEnergyBurned(on: date)) ?? 0
        workouts = (try? await healthKit.workouts(on: date)) ?? []
    }
}

private struct MealHeader: View {
    let meal: MealType
    let calories: Double

    var body: some View {
        HStack {
            Label(meal.title, systemImage: meal.symbolName)
                .font(.headline)
                .symbolRenderingMode(.multicolor)
            Spacer()
            Text("\(calories.wholeNumber) kcal")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct FoodEntryRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: entry.source.symbolName)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.body)
                    .lineLimit(1)
                Text([entry.brand, entry.portionDescription].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(entry.calories.wholeNumber) kcal")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                MacroInlineText(nutrients: entry.nutrients)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double-tap to edit")
    }
}

private struct WorkoutRow: View {
    let workout: WorkoutSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.symbolName)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name).font(.body)
                Text("\(workout.start.formatted(date: .omitted, time: .shortened)) · \(Duration.seconds(workout.duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let kcal = workout.activeCalories {
                Text("\(kcal.wholeNumber) kcal")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    DashboardView(profile: PreviewData.profile)
        .modelContainer(PreviewData.container)
        .environment(HealthKitManager())
}
#endif

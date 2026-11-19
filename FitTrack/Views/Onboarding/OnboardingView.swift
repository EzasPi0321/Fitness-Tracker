import SwiftData
import SwiftUI

enum OnboardingStep: Int, CaseIterable, Comparable {
    case welcome, health, body, activity, goal, summary

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .welcome: ""
        case .health: "Apple Health"
        case .body: "About You"
        case .activity: "Activity Level"
        case .goal: "Your Goal"
        case .summary: "Your Plan"
        }
    }
}

/// Editable profile values collected during onboarding.
struct ProfileDraft {
    var sex: BiologicalSex = .female
    var birthDate: Date = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    var heightCm: Double = 170
    var weightKg: Double = 70
    var activity: ActivityLevel = .moderate
    var goal: WeightGoal = .maintain
    var usesMetric: Bool = Locale.current.measurementSystem == .metric

    init() {}

    init(profile: UserProfile) {
        sex = profile.sex
        birthDate = profile.birthDate
        heightCm = profile.heightCm
        weightKg = profile.weightKg
        activity = profile.activity
        goal = profile.goal
        usesMetric = profile.usesMetric
    }

    var age: Int { max(0, Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 0) }

    var plan: EnergyPlan {
        NutritionCalculator.plan(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg,
                                 activity: activity, goal: goal)
    }

    var isBodyValid: Bool {
        (13...110).contains(age) && (100...250).contains(heightCm) && (30...350).contains(weightKg)
    }

    // Unit-aware bindings
    var displayWeight: Double? {
        get { ((usesMetric ? weightKg : weightKg * UnitConversion.poundsPerKilogram) * 10).rounded() / 10 }
        set {
            guard let newValue else { return }
            weightKg = usesMetric ? newValue : newValue / UnitConversion.poundsPerKilogram
        }
    }

    var heightCentimeters: Int {
        get { Int(heightCm.rounded()) }
        set { heightCm = Double(newValue) }
    }

    private var totalInches: Int { Int((heightCm / UnitConversion.centimetersPerInch).rounded()) }

    var heightFeet: Int {
        get { totalInches / 12 }
        set { heightCm = Double(newValue * 12 + heightInches) * UnitConversion.centimetersPerInch }
    }

    var heightInches: Int {
        get { totalInches % 12 }
        set { heightCm = Double(heightFeet * 12 + newValue) * UnitConversion.centimetersPerInch }
    }

    mutating func apply(_ snapshot: HealthProfileSnapshot) {
        if let sex = snapshot.sex { self.sex = sex }
        if let birthDate = snapshot.birthDate { self.birthDate = birthDate }
        if let height = snapshot.heightCm, (100...250).contains(height) { heightCm = height }
        if let weight = snapshot.weightKg, (30...350).contains(weight) { weightKg = weight }
    }

    func write(to profile: UserProfile) {
        profile.sex = sex
        profile.birthDate = birthDate
        profile.heightCm = heightCm
        profile.weightKg = weightKg
        profile.activity = activity
        profile.goal = goal
        profile.usesMetric = usesMetric
        profile.apply(plan)
    }
}

struct OnboardingView: View {
    /// When set, the flow recalculates targets for an existing profile instead of creating one.
    var existingProfile: UserProfile?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitManager.self) private var healthKit
    @AppStorage(SettingsKey.healthKitEnabled) private var healthKitEnabled = false

    @State private var step: OnboardingStep
    @State private var draft: ProfileDraft
    @State private var isConnectingHealth = false
    @State private var healthMessage: String?

    init(existingProfile: UserProfile? = nil) {
        self.existingProfile = existingProfile
        _draft = State(initialValue: existingProfile.map(ProfileDraft.init(profile:)) ?? ProfileDraft())
        _step = State(initialValue: existingProfile == nil ? .welcome : .body)
    }

    private var steps: [OnboardingStep] {
        existingProfile == nil ? OnboardingStep.allCases : [.body, .activity, .goal, .summary]
    }

    private var stepIndex: Int { steps.firstIndex(of: step) ?? 0 }

    private var canContinue: Bool {
        step == .body ? draft.isBodyValid : true
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if step != .welcome {
                    ProgressView(value: Double(stepIndex), total: Double(max(steps.count - 1, 1)))
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }

                Group {
                    switch step {
                    case .welcome: WelcomeStep()
                    case .health: healthStep
                    case .body: BodyStep(draft: $draft)
                    case .activity: ActivityStep(selection: $draft.activity)
                    case .goal: GoalStep(selection: $draft.goal)
                    case .summary: SummaryStep(draft: draft)
                    }
                }
                .id(step)
                .transition(.push(from: .trailing))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomBar
            }
            .background(Theme.screenBackground)
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if existingProfile != nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if stepIndex > 0 {
                Button {
                    withAnimation(.snappy) { step = steps[stepIndex - 1] }
                } label: {
                    Text("Back").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Button {
                advance()
            } label: {
                Text(primaryTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canContinue)
        }
        .controlSize(.large)
        .padding()
        .background(.bar)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get Started"
        case .health: healthKitEnabled ? "Continue" : "Not Now"
        case .summary: existingProfile == nil ? "Start Tracking" : "Save Targets"
        default: "Continue"
        }
    }

    private func advance() {
        hideKeyboard()
        if step == .summary {
            finish()
        } else if stepIndex + 1 < steps.count {
            withAnimation(.snappy) { step = steps[stepIndex + 1] }
        }
    }

    private func finish() {
        if let existingProfile {
            draft.write(to: existingProfile)
            try? modelContext.save()
            dismiss()
        } else {
            let profile = UserProfile()
            draft.write(to: profile)
            modelContext.insert(profile)
            modelContext.insert(WeightEntry(date: .now, kilograms: draft.weightKg))
            try? modelContext.save()
        }
    }

    // MARK: Health step

    private var healthStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 72))
                .foregroundStyle(.pink.gradient)
                .accessibilityHidden(true)
            Text("Connect Apple Health")
                .font(.title2.bold())
            Text("FitTrack can read your active energy, workouts and weight to personalise your budget, and save the meals you log as nutrition data.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if healthKitEnabled {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else if healthKit.isAvailable {
                Button {
                    Task { await connectHealth() }
                } label: {
                    if isConnectingHealth {
                        ProgressView()
                    } else {
                        Label("Connect", systemImage: "heart.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .controlSize(.large)
                .disabled(isConnectingHealth)
            } else {
                Text("Health data isn't available on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let healthMessage {
                Text(healthMessage).font(.footnote).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(32)
    }

    private func connectHealth() async {
        isConnectingHealth = true
        defer { isConnectingHealth = false }
        do {
            try await healthKit.requestAuthorization()
            healthKitEnabled = true
            draft.apply(await healthKit.profileSnapshot())
        } catch {
            healthMessage = error.localizedDescription
        }
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(Color.accentColor.gradient)
                    .padding(.top, 48)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text("Welcome to FitTrack")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("Simple, private nutrition tracking that works with Apple Health.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(symbol: "barcode.viewfinder", tint: .blue,
                               title: "Scan Barcodes", detail: "Instant nutrition facts from Open Food Facts.")
                    FeatureRow(symbol: "camera.viewfinder", tint: .purple,
                               title: "Snap Meals", detail: "AI estimates calories and macros from a photo.")
                    FeatureRow(symbol: "heart.fill", tint: .pink,
                               title: "Apple Health", detail: "Sync workouts, weight and nutrition.")
                    FeatureRow(symbol: "chart.xyaxis.line", tint: .green,
                               title: "See Progress", detail: "Calorie and weight trends over time.")
                }
                .padding(.horizontal, 8)
            }
            .padding(24)
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BodyStep: View {
    @Binding var draft: ProfileDraft

    private var latestAllowedBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -13, to: .now) ?? .now
    }

    var body: some View {
        Form {
            Section {
                Picker("Biological Sex", selection: $draft.sex) {
                    ForEach(BiologicalSex.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Biological Sex")
            } footer: {
                Text("Used by the Mifflin–St Jeor equation to estimate your resting energy.")
            }

            Section("Age") {
                DatePicker("Date of Birth", selection: $draft.birthDate,
                           in: ...latestAllowedBirthDate, displayedComponents: .date)
                LabeledContent("Age", value: "\(draft.age)")
            }

            Section("Measurements") {
                Picker("Units", selection: $draft.usesMetric) {
                    Text("Metric").tag(true)
                    Text("Imperial").tag(false)
                }
                .pickerStyle(.segmented)

                if draft.usesMetric {
                    Picker("Height", selection: $draft.heightCentimeters) {
                        ForEach(100...250, id: \.self) { Text("\($0) cm").tag($0) }
                    }
                } else {
                    Picker("Height (ft)", selection: $draft.heightFeet) {
                        ForEach(3...8, id: \.self) { Text("\($0) ft").tag($0) }
                    }
                    Picker("Height (in)", selection: $draft.heightInches) {
                        ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
                    }
                }

                NumberField(title: "Weight", value: $draft.displayWeight, unit: draft.usesMetric ? "kg" : "lb")
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct ActivityStep: View {
    @Binding var selection: ActivityLevel

    var body: some View {
        Form {
            Section {
                ForEach(ActivityLevel.allCases) { level in
                    SelectableRow(title: level.title, detail: level.detail, symbol: nil,
                                  isSelected: selection == level) { selection = level }
                }
            } header: {
                Text("How active are you on a typical week?")
            } footer: {
                Text("Don't count workouts tracked by Apple Watch if you plan to add active energy to your budget.")
            }
        }
    }
}

private struct GoalStep: View {
    @Binding var selection: WeightGoal

    var body: some View {
        Form {
            Section("What would you like to achieve?") {
                ForEach(WeightGoal.allCases) { goal in
                    SelectableRow(title: goal.title, detail: goal.detail, symbol: goal.symbolName,
                                  isSelected: selection == goal) { selection = goal }
                }
            }
        }
    }
}

private struct SelectableRow: View {
    let title: String
    let detail: String
    let symbol: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 32)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

private struct SummaryStep: View {
    let draft: ProfileDraft

    var body: some View {
        let plan = draft.plan
        let targets = plan.targets
        Form {
            Section {
                VStack(spacing: 4) {
                    Text(targets.calories.wholeNumber)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                    Text("kcal per day")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("How It's Calculated") {
                LabeledContent("Resting energy (BMR)", value: "\(plan.bmr.wholeNumber) kcal")
                LabeledContent("Activity × \(draft.activity.multiplier.formatted())", value: "\(plan.tdee.wholeNumber) kcal")
                LabeledContent("Goal adjustment",
                               value: "\(draft.goal.calorieAdjustment >= 0 ? "+" : "")\(draft.goal.calorieAdjustment.wholeNumber) kcal")
            }

            Section("Daily Macros") {
                ForEach(Macro.allCases) { macro in
                    let grams = macro.value(in: targets)
                    let share = targets.calories > 0 ? grams * macro.kcalPerGram / targets.calories : 0
                    LabeledContent {
                        Text("\(grams.wholeNumber) g · \(share.formatted(.percent.precision(.fractionLength(0))))")
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

            Section {
                EmptyView()
            } footer: {
                Text("These are estimates from the Mifflin–St Jeor equation. You can fine-tune targets anytime in Settings. Consult a healthcare professional before making significant changes to your diet.")
            }
        }
    }
}

#if DEBUG
#Preview {
    OnboardingView()
        .modelContainer(PreviewData.container)
        .environment(HealthKitManager())
}
#endif

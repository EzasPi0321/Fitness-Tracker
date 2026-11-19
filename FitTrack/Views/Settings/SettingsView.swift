import SwiftData
import SwiftUI

struct SettingsView: View {
    @Bindable var profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var healthKit
    @AppStorage(SettingsKey.healthKitEnabled) private var healthKitEnabled = false
    @AppStorage(SettingsKey.addActiveEnergyToBudget) private var addActiveEnergy = false

    @State private var showRecalculate = false
    @State private var confirmDeleteLogs = false
    @State private var healthError: String?

    private var macroCalories: Double {
        profile.proteinTarget * 4 + profile.carbsTarget * 4 + profile.fatTarget * 9
    }

    var body: some View {
        NavigationStack {
            Form {
                targetsSection
                healthSection
                AIProviderSettingsSection()

                Section("Units") {
                    Picker("Measurement System", selection: $profile.usesMetric) {
                        Text("Metric").tag(true)
                        Text("Imperial").tag(false)
                    }
                }

                Section {
                    Button("Delete All Food Logs", role: .destructive) { confirmDeleteLogs = true }
                } footer: {
                    Text("Removes logs from this device. Entries already written to Apple Health can be removed in the Health app.")
                }

                Section("About") {
                    Link(destination: URL(string: "https://world.openfoodfacts.org")!) {
                        Label("Product data: Open Food Facts (ODbL)", systemImage: "link")
                    }
                    LabeledContent("Version",
                                   value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.interactively)
            .sheet(isPresented: $showRecalculate) { OnboardingView(existingProfile: profile) }
            .confirmationDialog("Delete all food logs?", isPresented: $confirmDeleteLogs, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) {
                    try? modelContext.delete(model: FoodEntry.self)
                    try? modelContext.save()
                }
            } message: {
                Text("This can't be undone.")
            }
            .alert("Apple Health", isPresented: Binding(get: { healthError != nil }, set: { if !$0 { healthError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(healthError ?? "")
            }
        }
    }

    private var targetsSection: some View {
        Section {
            TargetField(title: "Calories", value: $profile.calorieTarget, unit: "kcal")
            TargetField(title: "Protein", value: $profile.proteinTarget, unit: "g")
            TargetField(title: "Carbs", value: $profile.carbsTarget, unit: "g")
            TargetField(title: "Fat", value: $profile.fatTarget, unit: "g")
            Button("Recalculate from Profile…") { showRecalculate = true }
        } header: {
            Text("Daily Targets")
        } footer: {
            let difference = macroCalories - profile.calorieTarget
            if abs(difference) > 50 {
                Text("Your macros add up to \(macroCalories.wholeNumber) kcal, \(abs(difference).wholeNumber) kcal \(difference > 0 ? "over" : "under") your calorie target.")
                    .foregroundStyle(.orange)
            } else {
                Text("Macros add up to \(macroCalories.wholeNumber) kcal.")
            }
        }
    }

    private var healthSection: some View {
        Section {
            if healthKit.isAvailable {
                Toggle("Sync with Apple Health", isOn: $healthKitEnabled)
                    .onChange(of: healthKitEnabled) { _, enabled in
                        guard enabled else { return }
                        Task {
                            do {
                                try await healthKit.requestAuthorization()
                            } catch {
                                healthKitEnabled = false
                                healthError = error.localizedDescription
                            }
                        }
                    }
                Toggle("Add Active Energy to Budget", isOn: $addActiveEnergy)
                    .disabled(!healthKitEnabled)
                if let message = healthKit.lastErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } else {
                Text("Apple Health isn't available on this device.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text("Reads active energy, workouts and weight. Logged meals are saved as Dietary Energy, Protein, Carbohydrates and Fat. Manage access in Settings › Health › Data Access & Devices.")
        }
    }
}

private struct TargetField: View {
    let title: String
    @Binding var value: Double
    let unit: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: $value, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
                    .monospacedDigit()
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }
}

/// Provider, model and Keychain-backed API key for AI photo estimates.
struct AIProviderSettingsSection: View {
    @AppStorage(SettingsKey.visionProvider) private var providerRaw = VisionProvider.gemini.rawValue
    @AppStorage(SettingsKey.visionModel) private var model = VisionProvider.gemini.defaultModel
    @State private var apiKey = ""
    @State private var loaded = false

    private var provider: VisionProvider { VisionProvider(rawValue: providerRaw) ?? .gemini }

    var body: some View {
        Section {
            Picker("Provider", selection: $providerRaw) {
                ForEach(VisionProvider.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            LabeledContent("Model") {
                TextField(provider.defaultModel, text: $model)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            SecureField("API Key", text: $apiKey)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("AI Photo Estimates")
        } footer: {
            Text("Your key is stored in the iOS Keychain on this device only. For App Store builds, route requests through your own server so no provider key ships with the app.")
        }
        .onAppear {
            guard !loaded else { return }
            apiKey = KeychainStore.string(for: provider.keychainAccount) ?? ""
            loaded = true
        }
        .onChange(of: providerRaw) { _, _ in
            model = provider.defaultModel
            apiKey = KeychainStore.string(for: provider.keychainAccount) ?? ""
        }
        .onChange(of: apiKey) { _, newValue in
            guard loaded else { return }
            KeychainStore.set(newValue, for: provider.keychainAccount)
        }
    }
}

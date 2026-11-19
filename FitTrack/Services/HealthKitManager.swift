import Foundation
import HealthKit
import Observation

struct WorkoutSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let symbolName: String
    let start: Date
    let duration: TimeInterval
    let activeCalories: Double?
}

struct WeightSample: Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let kilograms: Double
}

/// Characteristics and latest measurements used to prefill onboarding.
struct HealthProfileSnapshot: Sendable {
    var sex: BiologicalSex?
    var birthDate: Date?
    var heightCm: Double?
    var weightKg: Double?
}

enum HealthKitError: LocalizedError {
    case unavailable
    case nothingToSave

    var errorDescription: String? {
        switch self {
        case .unavailable: "Health data isn't available on this device."
        case .nothingToSave: "This entry has no nutrition values to save."
        }
    }
}

/// Wraps `HKHealthStore` using the async query descriptors (iOS 15.4+).
@MainActor
@Observable
final class HealthKitManager {
    @ObservationIgnored private let store = HKHealthStore()
    private(set) var lastErrorMessage: String?

    // MARK: Types

    private static let activeEnergy = HKQuantityType(.activeEnergyBurned)
    private static let bodyMass = HKQuantityType(.bodyMass)
    private static let height = HKQuantityType(.height)
    private static let dietaryEnergy = HKQuantityType(.dietaryEnergyConsumed)
    private static let dietaryProtein = HKQuantityType(.dietaryProtein)
    private static let dietaryCarbs = HKQuantityType(.dietaryCarbohydrates)
    private static let dietaryFat = HKQuantityType(.dietaryFatTotal)
    private static let foodCorrelation = HKCorrelationType(.food)

    /// Metadata key linking Health samples back to a `FoodEntry`.
    static let entryIDMetadataKey = "FitTrackEntryID"

    private static var readTypes: Set<HKObjectType> {
        [
            activeEnergy, bodyMass, height, dietaryEnergy,
            HKObjectType.workoutType(),
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex),
        ]
    }

    /// Correlation types can't be requested directly — authorise their member quantity types.
    private static var shareTypes: Set<HKSampleType> {
        [dietaryEnergy, dietaryProtein, dietaryCarbs, dietaryFat, bodyMass]
    }

    // MARK: Authorization

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Write status is knowable; read status is intentionally hidden by HealthKit for privacy.
    var canWriteNutrition: Bool {
        isAvailable && store.authorizationStatus(for: Self.dietaryEnergy) == .sharingAuthorized
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
        lastErrorMessage = nil
    }

    func report(_ error: Error) {
        lastErrorMessage = error.localizedDescription
    }

    // MARK: Reading

    func activeEnergyBurned(on day: Date) async throws -> Double {
        let bounds = day.dayBounds
        let predicate = HKSamplePredicate.quantitySample(
            type: Self.activeEnergy,
            predicate: HKQuery.predicateForSamples(withStart: bounds.start, end: bounds.end)
        )
        let descriptor = HKStatisticsQueryDescriptor(predicate: predicate, options: .cumulativeSum)
        do {
            let statistics = try await descriptor.result(for: store)
            return statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
        } catch let error as HKError where error.code == .errorNoData {
            return 0
        }
    }

    /// Active energy per calendar day, keyed by start of day.
    func dailyActiveEnergy(from start: Date, to end: Date) async throws -> [Date: Double] {
        let anchor = start.startOfDay
        let predicate = HKSamplePredicate.quantitySample(
            type: Self.activeEnergy,
            predicate: HKQuery.predicateForSamples(withStart: anchor, end: end)
        )
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: predicate,
            options: .cumulativeSum,
            anchorDate: anchor,
            intervalComponents: DateComponents(day: 1)
        )
        let collection: HKStatisticsCollection
        do {
            collection = try await descriptor.result(for: store)
        } catch let error as HKError where error.code == .errorNoData {
            return [:]
        }
        var result: [Date: Double] = [:]
        collection.enumerateStatistics(from: anchor, to: end) { statistics, _ in
            result[statistics.startDate] = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
        }
        return result
    }

    func workouts(on day: Date) async throws -> [WorkoutSummary] {
        let bounds = day.dayBounds
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: bounds.start, end: bounds.end))],
            sortDescriptors: [SortDescriptor(\HKWorkout.startDate, order: .reverse)]
        )
        let workouts = try await descriptor.result(for: store)
        return workouts.map { workout in
            WorkoutSummary(
                id: workout.uuid,
                name: workout.workoutActivityType.displayName,
                symbolName: workout.workoutActivityType.symbolName,
                start: workout.startDate,
                duration: workout.duration,
                activeCalories: workout.statistics(for: Self.activeEnergy)?
                    .sumQuantity()?.doubleValue(for: .kilocalorie())
            )
        }
    }

    func bodyMassHistory(since start: Date) async throws -> [WeightSample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: Self.bodyMass,
                                         predicate: HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        return samples.map {
            WeightSample(id: $0.uuid, date: $0.startDate, kilograms: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)))
        }
    }

    func profileSnapshot() async -> HealthProfileSnapshot {
        var snapshot = HealthProfileSnapshot()
        if let sex = try? store.biologicalSex().biologicalSex {
            switch sex {
            case .male: snapshot.sex = .male
            case .female: snapshot.sex = .female
            default: break
            }
        }
        if let components = try? store.dateOfBirthComponents() {
            snapshot.birthDate = Calendar.current.date(from: components)
        }
        snapshot.heightCm = try? await latestValue(of: Self.height, unit: .meterUnit(with: .centi))
        snapshot.weightKg = try? await latestValue(of: Self.bodyMass, unit: .gramUnit(with: .kilo))
        return snapshot
    }

    private func latestValue(of type: HKQuantityType, unit: HKUnit) async throws -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type)],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .reverse)],
            limit: 1
        )
        return try await descriptor.result(for: store).first?.quantity.doubleValue(for: unit)
    }

    // MARK: Writing

    /// Saves a logged food as an `HKCorrelation` of type `.food`, which is how Apple Health
    /// groups the energy and macro samples of a single food. Returns the correlation UUID.
    func saveFood(name: String, nutrients: Nutrients, date: Date, entryID: UUID) async throws -> UUID {
        guard isAvailable else { throw HealthKitError.unavailable }
        let metadata: [String: Any] = [
            HKMetadataKeyFoodType: name,
            Self.entryIDMetadataKey: entryID.uuidString,
        ]

        var samples = Set<HKSample>()
        func add(_ type: HKQuantityType, _ unit: HKUnit, _ value: Double) {
            guard value > 0, value.isFinite else { return }
            samples.insert(HKQuantitySample(type: type,
                                            quantity: HKQuantity(unit: unit, doubleValue: value),
                                            start: date, end: date, metadata: metadata))
        }
        add(Self.dietaryEnergy, .kilocalorie(), nutrients.calories)
        add(Self.dietaryProtein, .gram(), nutrients.protein)
        add(Self.dietaryCarbs, .gram(), nutrients.carbs)
        add(Self.dietaryFat, .gram(), nutrients.fat)
        guard !samples.isEmpty else { throw HealthKitError.nothingToSave }

        let correlation = HKCorrelation(type: Self.foodCorrelation, start: date, end: date,
                                        objects: samples, metadata: metadata)
        try await store.save(correlation)
        return correlation.uuid
    }

    /// Deletes a previously saved food correlation together with its member samples.
    func deleteFood(correlationID: UUID) async throws {
        guard isAvailable else { return }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.correlation(type: Self.foodCorrelation,
                                      predicate: HKQuery.predicateForObject(with: correlationID))],
            sortDescriptors: [],
            limit: 1
        )
        guard let correlation = try await descriptor.result(for: store).first else { return }
        let objects: [HKObject] = correlation.objects.map { $0 as HKObject } + [correlation]
        try await store.delete(objects)
    }

    @discardableResult
    func saveBodyMass(kilograms: Double, date: Date) async throws -> UUID {
        guard isAvailable else { throw HealthKitError.unavailable }
        let sample = HKQuantitySample(type: Self.bodyMass,
                                      quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms),
                                      start: date, end: date)
        try await store.save(sample)
        return sample.uuid
    }
}

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running: "Run"
        case .walking: "Walk"
        case .cycling: "Cycling"
        case .swimming: "Swim"
        case .hiking: "Hike"
        case .yoga: "Yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength Training"
        case .highIntensityIntervalTraining: "HIIT"
        case .elliptical: "Elliptical"
        case .rowing: "Rowing"
        case .dance: "Dance"
        case .pilates: "Pilates"
        case .coreTraining: "Core Training"
        case .stairClimbing: "Stair Climbing"
        default: "Workout"
        }
    }

    var symbolName: String {
        switch self {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .hiking: "figure.hiking"
        case .yoga: "figure.yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "figure.strengthtraining.traditional"
        case .highIntensityIntervalTraining: "figure.highintensity.intervaltraining"
        case .elliptical: "figure.elliptical"
        case .rowing: "figure.rower"
        case .dance: "figure.dance"
        case .pilates: "figure.pilates"
        case .coreTraining: "figure.core.training"
        case .stairClimbing: "figure.stair.stepper"
        default: "figure.mixed.cardio"
        }
    }
}

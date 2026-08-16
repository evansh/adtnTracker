import Foundation
import HealthKit

actor HealthKitServiceImpl: HealthKitService {
    private let healthStore = HKHealthStore()
    private let workoutTypes: Set<HKSampleType> = [
        HKWorkoutType.workoutType(),
        HKQuantityType.quantityType(forIdentifier: .dietaryWater)!
    ]
    private let readTypes: Set<HKObjectType> = [
        HKWorkoutType.workoutType(),
        HKQuantityType.quantityType(forIdentifier: .dietaryWater)!,
        HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
    ]

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        try await healthStore.requestAuthorization(toShare: workoutTypes, read: readTypes)
    }

    func isAuthorized() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let status = healthStore.authorizationStatus(for: HKWorkoutType.workoutType())
        return status == .sharingAuthorized
    }

    func fetchWorkouts(since: Date) async throws -> [ExternalWorkout] {
        guard await isAuthorized() else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKWorkoutType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error { continuation.resume(throwing: error); return }
                let workouts = (samples as? [HKWorkout] ?? []).map { self.mapWorkout($0) }
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }
    }

    func fetchHydration(since: Date) async throws -> [ExternalWorkout] {
        guard await isAuthorized() else { return [] }
        guard let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: waterType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error { continuation.resume(throwing: error); return }
                let samples = samples as? [HKQuantitySample] ?? []
                continuation.resume(returning: samples.map { self.mapHydration($0) })
            }
            healthStore.execute(query)
        }
    }

    func fetchSleep(since: Date) async throws -> [ExternalWorkout] {
        guard await isAuthorized() else { return [] }
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error { continuation.resume(throwing: error); return }
                continuation.resume(returning: [])
            }
            healthStore.execute(query)
        }
    }

    private func mapWorkout(_ workout: HKWorkout) -> ExternalWorkout {
        let typeName = workout.workoutActivityType.name
        let isOutdoor = workout.workoutActivityType.isOutdoor
        let distance = workout.totalDistance?.doubleValue(for: .meter())
        let elevation = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())

        return ExternalWorkout(
            source: .healthKit,
            externalID: workout.uuid.uuidString,
            type: typeName,
            startDate: workout.startDate,
            endDate: workout.endDate,
            durationMinutes: Int(workout.duration / 60),
            distanceMeters: distance,
            isOutdoor: isOutdoor,
            routeCoordinates: nil,
            elevationGainMeters: elevation,
            sourceData: try? JSONEncoder().encode(["hkUUID": workout.uuid.uuidString])
        )
    }

    private func mapHydration(_ sample: HKQuantitySample) -> ExternalWorkout {
        let milliliters = sample.quantity.doubleValue(for: .literUnit(with: .milli))
        return ExternalWorkout(
            source: .healthKit,
            externalID: sample.uuid.uuidString,
            type: "Water",
            startDate: sample.startDate,
            endDate: sample.endDate,
            durationMinutes: 0,
            distanceMeters: nil,
            isOutdoor: false,
            routeCoordinates: nil,
            elevationGainMeters: nil,
            sourceData: try? JSONEncoder().encode(["ml": milliliters, "hkUUID": sample.uuid.uuidString])
        )
    }
}

enum HealthKitError: Error, LocalizedError {
    case notAvailable
    var errorDescription: String? {
        switch self {
        case .notAvailable: "HealthKit is not available on this device"
        }
    }
}

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .functionalStrengthTraining: return "Strength Training"
        case .traditionalStrengthTraining: return "Weightlifting"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .highIntensityIntervalTraining: return "HIIT"
        case .crossTraining: return "Cross Training"
        case .mixedCardio: return "Mixed Cardio"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stair Climbing"
        default: return "Workout"
        }
    }

    var isOutdoor: Bool {
        switch self {
        case .running, .cycling, .swimming, .walking, .hiking, .rowing, .crossCountrySkiing, .downhillSkiing, .snowboarding, .skatingSports:
            return true
        default:
            return false
        }
    }
}
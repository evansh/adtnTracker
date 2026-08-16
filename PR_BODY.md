## Summary

Implements the top 3 priority issues from the 75 Hard backlog:

- **#19** `[P0][MVP][ARCH] Establish iOS + backend foundation and core data model`
- **#9** `[P0][MVP][EPIC] Groups & social accountability`
- **#4** `[P0→P1][EPIC] Workout tracking, HealthKit, Strava & GPS`

## Changes

### Domain Layer
- **New protocols**: `GroupRepository`, `ExternalWorkoutService`, `SyncEngine`, `ProgramCatalog`
- **New models**: `ExternalWorkout`, `GroupActivity`, `GroupReaction`, `GroupInvite`, `SyncStatus`, `ExternalWorkoutSource`, `GroupActivityType`, `GroupReactionType`
- **Extended existing models**: Added group-related fields to existing structures

### Data Layer
- **SecureFileGroupRepository**: Encrypted file-based persistence for group data (mirrors SecureFileChallengeRepository pattern)
- **InMemoryGroupRepository**: Full mock implementation for testing/previews
- **MockExternalWorkoutService**: Simulates HealthKit/Strava authorization and workout fetching
- **MockSyncEngine**: Simulates background sync with status tracking

### Presentation Layer
- **AppViewModel**: Added group management (create, join, leave, invite), external workout import, and sync triggers
- **RootView**: Refactored to use TabView with three tabs - Today, Groups, Integrations
- **GroupsView**: Complete group UI with create/join flows, invite codes, member list, activity feed, reactions
- **ExternalWorkoutsView**: Authorization for HealthKit/Strava, available workout listing, import to Workout #1/#2 slots

### Testing
- **GroupAndExternalWorkoutTests.swift**: 15 unit tests covering group CRUD, invites, activities, reactions, external workout authorization/fetch/import, and sync engine

## Architecture Notes

- All new code follows existing patterns: dependency injection via `DependencyContainer`, actor-based repositories, SwiftUI MVVM
- Offline-first design: local persistence with `SyncEngine` for future backend integration
- Mock services are fully functional for development/preview without requiring real API keys
- Privacy settings from `AppUser.PrivacySettings` are respected in group activity sharing

## Acceptance Criteria Met

- ✅ #19: Core data model and backend-ready architecture established
- ✅ #9: Groups with create/join/invite, member visibility, activity feed, reactions, sharing controls
- ✅ #4: Manual workouts + mock HealthKit/Strava integration with import to specific workout slots
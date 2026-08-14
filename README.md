# 75Hard

Privacy-first, offline-capable iOS tracking for the 75 Hard challenge.

## Current MVP foundation

The first implementation slice covers the shared foundation for the MVP backlog:

- Data-driven, versioned program requirements
- Time-zone-aware challenge scheduling
- Provider-neutral evidence and rule evaluation
- Immutable attempt history with failure/restart support
- Secure local persistence using iOS complete file protection
- SwiftUI onboarding and daily dashboard scaffolding
- Unit tests for business rules, validation, dates, persistence, and restart behavior

## Architecture

The app uses dependency inversion across three layers:

- `Domain`: entities, repository contracts, rules, and use cases; no SwiftUI or storage dependencies
- `Data`: secure repository implementations
- `Presentation`: view models and SwiftUI views

The challenge engine consumes normalized evidence rather than UI state or provider-specific models. This keeps manual entry, HealthKit, Strava, and future integrations interchangeable.

## Build and test

Open `75Hard.xcodeproj` in Xcode, select an iPhone simulator, and run the `75Hard` scheme. From Terminal:

```sh
xcodebuild -project 75Hard.xcodeproj \
  -scheme 75Hard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

The project requires Xcode 26 or newer and targets iOS 18 or newer.

## Security notes

- No tokens, credentials, or progress-photo bytes are stored in the challenge-state file.
- The state file uses atomic writes and `Data.WritingOptions.completeFileProtection`.
- Progress photos are represented only by private metadata IDs in the domain.
- External evidence sources are normalized and never silently replace user evidence.
- Secrets, provisioning profiles, and local environment files are ignored by Git.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Position is a Swift 6-ready, actor-based location positioning library for iOS and macOS with modern async/await APIs and AsyncSequence support. The library provides thread-safe location services with Swift concurrency.

## Commands

### Build
```bash
swift build
```

### Build for Release
```bash
swift build -c release
```

### Run Tests
```bash
swift test
```

### Clean Build
```bash
swift package clean
```

### Lint (SwiftLint must be installed)
```bash
swiftlint lint Sources/
```

### Fix Linting Issues
```bash
swiftlint --fix Sources/
```

### Build with Xcode
```bash
xcodebuild -scheme Position -destination 'platform=iOS Simulator,name=iPhone 15'
xcodebuild -scheme Position -destination 'platform=macOS'
```

## Architecture

### Core Components

1. **Position.swift** (Sources/Position.swift:77-900+)
   - Main actor-based class that manages all location services
   - Provides async/await APIs for one-shot location requests
   - Implements AsyncSequence streams for continuous updates (location, heading, authorization, floor, visit, errors)
   - Maintains backwards compatibility with deprecated observer pattern

2. **DeviceLocationManager.swift** (Sources/DeviceLocationManager.swift)
   - Internal actor that wraps CLLocationManager
   - Handles platform-specific location services
   - Manages delegation from CoreLocation to Position actor
   - Implements battery and background state monitoring

3. **CoreLocation+Additions.swift** (Sources/CoreLocation+Additions.swift)
   - Extensions for CLLocation, CLPlacemark, CLLocationCoordinate2D
   - Geospatial calculation utilities (distance, bearing, coordinate at bearing)
   - vCard generation for location sharing
   - Pretty formatting methods for locations and addresses

### Concurrency Model

- Position is an actor, ensuring thread-safe access to all location services
- All public methods are async and must be called with await
- AsyncSequence continuations provide reactive streams for:
  - `locationUpdates`: Location changes
  - `headingUpdates`: Compass heading (iOS only)
  - `authorizationUpdates`: Permission status changes
  - `floorUpdates`: Indoor floor level changes
  - `visitUpdates`: Significant location visits
  - `errorUpdates`: Location errors

### Platform Support

- iOS 15.0+ / macOS 11.0+
- Swift 6.0+ (also supports Swift 5 mode)
- Xcode 16.0+
- Platform-specific features:
  - Heading updates: iOS only
  - Battery monitoring: iOS only
  - Background updates: Full on iOS, limited on macOS

### Swift 6 Compatibility

The codebase is fully Swift 6 compatible with:
- Actor isolation for thread safety
- @preconcurrency imports where needed
- Proper Sendable conformance
- No data races or concurrency issues

## Key Implementation Patterns

1. **Async/Await for One-Shot Requests**
   ```swift
   let location = try await position.currentLocation()
   ```

2. **AsyncSequence for Continuous Updates**
   ```swift
   for await location in position.locationUpdates {
       // Handle location
   }
   ```

3. **Actor Method Calls**
   ```swift
   await position.startUpdating()
   let status = await position.locationServicesStatus
   ```

4. **Error Handling**
   - All location requests can throw errors
   - Separate errorUpdates stream for continuous error monitoring
   - Proper error types defined in Position.Error enum

## Testing Considerations

- Location services require proper simulator/device setup
- Info.plist must include usage descriptions (NSLocationWhenInUseUsageDescription, etc.)
- Use iOS Simulator's Debug > Location menu for testing
- Consider mocking CLLocationManager for unit tests

## SwiftLint Configuration

The project uses SwiftLint with custom rules (.swiftlint.yml):
- Disabled: identifier_name, line_length, function_body_length, file_length
- Enabled opt-in rules: empty_count, empty_string, modifier_order, convenience_type
- Sources directory is included for linting
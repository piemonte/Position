# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ⚠️ CRITICAL: Never Use Force Unwrap (!)

**Force unwrapping with `!` is prohibited in this codebase. ALWAYS use safe optional handling:**

### ❌ NEVER Do This:
```swift
let location = locationManager.location!  // Crash if nil
let coordinate = location.coordinate!     // Crash if nil
```

### ✅ ALWAYS Do This Instead:

**Use guard let for early returns:**
```swift
guard let location = locationManager.location else {
    print("Location unavailable")
    return
}
// Safe to use location here
```

**Use optional chaining:**
```swift
if let coordinate = location?.coordinate {
    // Use coordinate safely
}
```

**Use nil coalescing for defaults:**
```swift
let accuracy = location?.horizontalAccuracy ?? 0.0
```

**Why this matters:** Force unwraps cause immediate crashes when encountering nil values. Safe optional handling ensures the library remains stable and provides better error handling for consumers.

## Project Overview

Position is a Swift 6-ready, actor-based location positioning library for iOS and macOS with modern async/await APIs and AsyncSequence support. The library provides thread-safe location services with Swift concurrency.

## Requirements

- iOS 16.0+ / macOS 13.0+
- Swift 6.0+ (also supports Swift 5 mode)
- Xcode 16.0+

## Commands

### Build Commands
```bash
# Build for debug
swift build

# Build for release
swift build -c release

# Run tests
swift test

# Clean build
swift package clean
```

### Linting (SwiftLint must be installed)
```bash
# Lint sources
swiftlint lint Sources/

# Auto-fix linting issues
swiftlint --fix Sources/
```

### Build with Xcode
```bash
# iOS Simulator
xcodebuild -scheme Position -destination 'platform=iOS Simulator,name=iPhone 15'

# macOS
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

### Swift 6 Concurrency Model

Position follows strict Swift 6 concurrency patterns:

- **Actor Isolation**: Position is an actor, ensuring thread-safe access to all location services
- **Async/Await**: All public methods are async and must be called with await
- **AsyncSequence**: Reactive streams for continuous updates without callbacks
- **@preconcurrency**: Used for CoreLocation imports to handle API evolution
- **Sendable**: All data types passed across actors conform to Sendable

**AsyncSequence Streams:**
- `locationUpdates`: Location changes
- `headingUpdates`: Compass heading (iOS only)
- `authorizationUpdates`: Permission status changes
- `floorUpdates`: Indoor floor level changes
- `visitUpdates`: Significant location visits
- `errorUpdates`: Location errors

### Platform Support

- iOS 16.0+ / macOS 13.0+
- Swift 6.0+ (also supports Swift 5 mode)
- Xcode 16.0+
- Platform-specific features:
  - Heading updates: iOS only
  - Battery monitoring: iOS only
  - Background updates: Full on iOS, limited on macOS

## Swift 6 Concurrency Best Practices

### Actor Usage

**Position as an actor:**
```swift
public actor Position {
    // All methods are actor-isolated
    public func currentLocation() async throws -> CLLocation {
        // Thread-safe by default
    }
}
```

**Calling actor methods:**
```swift
let position = Position()
let location = try await position.currentLocation()  // Must use await
```

### Async/Await Patterns

**One-shot location request:**
```swift
do {
    let location = try await position.currentLocation()
    print("Location: \(location.coordinate)")
} catch {
    print("Error: \(error)")
}
```

**AsyncSequence for continuous updates:**
```swift
Task {
    for await location in position.locationUpdates {
        print("New location: \(location.coordinate)")
    }
}
```

**Authorization handling:**
```swift
let status = try await position.requestWhenInUseLocationAuthorization()
switch status {
case .allowedWhenInUse:
    print("Authorized")
case .denied:
    print("Access denied")
default:
    print("Other status: \(status)")
}
```

### Task Cancellation Pattern

**CRITICAL: All long-running tasks MUST be cancellable to prevent memory leaks.**

```swift
class LocationViewModel {
    private var locationTask: Task<Void, Never>?

    deinit {
        locationTask?.cancel()  // Critical: Cancel on deinit
    }

    func startMonitoring() {
        locationTask?.cancel()  // Cancel previous task
        locationTask = Task {
            for await location in position.locationUpdates {
                guard !Task.isCancelled else { return }
                // Handle location update
            }
        }
    }
}
```

### Error Handling

**Position uses domain-specific errors:**

```swift
public enum Error: Swift.Error, Sendable {
    case restricted
    case notDetermined
    case denied
    case authorizationFailure
    case locationFailure
}
```

**Error handling pattern:**
```swift
do {
    let location = try await position.currentLocation()
} catch Position.Error.denied {
    print("Location access denied")
} catch Position.Error.restricted {
    print("Location access restricted")
} catch {
    print("Other error: \(error)")
}
```

## Key Implementation Patterns

### 1. Async/Await for One-Shot Requests

```swift
let location = try await position.currentLocation()
```

### 2. AsyncSequence for Continuous Updates

```swift
for await location in position.locationUpdates {
    // Handle location
}
```

### 3. Actor Method Calls

```swift
await position.startUpdating()
let status = await position.locationServicesStatus
```

### 4. Authorization Requests

```swift
// Request authorization and wait for result
let status = try await position.requestWhenInUseLocationAuthorization()

// Or request without waiting
await position.requestWhenInUseLocationAuthorization()
```

### 5. Multiple Concurrent Operations

```swift
Task {
    async let location = position.currentLocation()
    async let heading = position.currentHeading()

    let (loc, head) = try await (location, heading)
    print("Location: \(loc), Heading: \(head)")
}
```

## Common Pitfalls to Avoid

### ❌ DON'T: Use force unwrapping
```swift
let location = locationManager.location!  // Will crash if nil
```

### ✅ DO: Use safe optional handling
```swift
guard let location = locationManager.location else { return }
```

### ❌ DON'T: Call actor methods without await
```swift
position.startUpdating()  // Compiler error
```

### ✅ DO: Always await actor methods
```swift
await position.startUpdating()  // Correct
```

### ❌ DON'T: Use completion handlers
```swift
position.getCurrentLocation { location in
    // Old callback pattern
}
```

### ✅ DO: Use async/await
```swift
let location = try await position.currentLocation()
```

### ❌ DON'T: Forget to cancel long-running tasks
```swift
func startMonitoring() {
    Task {
        for await location in position.locationUpdates {
            // Memory leak if task never cancelled
        }
    }
}
```

### ✅ DO: Store and cancel tasks properly
```swift
private var task: Task<Void, Never>?

func startMonitoring() {
    task = Task { ... }
}

deinit {
    task?.cancel()
}
```

## Testing Considerations

### Simulator Setup
- Location services require proper simulator/device setup
- Use iOS Simulator's Debug > Location menu for testing
- Available test locations: Apple, City Run, Freeway Drive, etc.

### Info.plist Requirements
Required usage descriptions:
- `NSLocationWhenInUseUsageDescription`: "We need your location to..."
- `NSLocationAlwaysAndWhenInUseUsageDescription`: "We need your location always to..."
- `UIBackgroundModes`: Include `location` for background updates

### Unit Testing
- Consider mocking CLLocationManager for unit tests
- Test authorization state transitions
- Verify AsyncSequence behavior
- Test error handling paths

## SwiftLint Configuration

The project uses SwiftLint with custom rules (.swiftlint.yml):

**Disabled rules:**
- `identifier_name` - Allows short variable names like `id`
- `line_length` - No line length restrictions
- `function_body_length` - Large functions allowed for actor implementations
- `file_length` - Large files allowed

**Enabled opt-in rules:**
- `empty_count` - Use `.isEmpty` instead of `count == 0`
- `empty_string` - Use `.isEmpty` instead of `== ""`
- `modifier_order` - Consistent modifier ordering
- `convenience_type` - Detect types that should be enums

## Making Changes

### Adding New Features

1. **Maintain actor isolation** - All public API must be actor-safe
2. **Use async/await** - No completion handlers
3. **Provide AsyncSequence** - For continuous data streams
4. **Add error cases** - To Position.Error enum if needed
5. **Update deprecations** - Mark old observer pattern methods as deprecated
6. **Test on both platforms** - iOS and macOS if applicable

### Modifying Existing Code

1. **Never break actor isolation** - Don't add non-isolated methods
2. **Preserve async/await APIs** - Don't revert to callbacks
3. **Maintain Sendable conformance** - All types crossing actors must be Sendable
4. **Keep @preconcurrency imports** - For CoreLocation compatibility
5. **Test authorization flows** - Especially edge cases like .allowedWhenInUse

### Code Quality Checklist

- [ ] No force unwrapping (!)
- [ ] All actor methods use async/await
- [ ] Long-running tasks are cancellable
- [ ] Error handling uses Position.Error enum
- [ ] Optional handling is safe (guard let, if let, ??)
- [ ] SwiftLint passes with no warnings
- [ ] Both iOS and macOS builds succeed
- [ ] Authorization edge cases handled (.allowedWhenInUse vs .allowedAlways)

## Security and Privacy

### Location Privacy
- Request minimum necessary authorization (WhenInUse vs Always)
- Provide clear usage descriptions in Info.plist
- Stop location updates when not needed to save battery
- Handle authorization changes gracefully

### Background Location
- Only request if absolutely necessary
- Explain clearly to users why always-on location is needed
- Implement battery-aware accuracy adjustments
- Respect user's authorization downgrades (Always → WhenInUse)

## Performance Optimization

### Battery Efficiency
- Use appropriate accuracy for use case
- Stop updates when not needed
- Use significant location changes for background
- Implement battery-aware accuracy reduction

### Memory Management
- Cancel AsyncSequence iterations when done
- Store Task references and cancel in deinit
- Use weak self in long-running closures
- Clean up continuations properly

### Best Practices
- Prefer `distanceFilter` over processing every update
- Use `pausesLocationUpdatesAutomatically` where appropriate
- Consider `activityType` for better system optimization
- Batch location updates when possible

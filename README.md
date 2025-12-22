# Position

`Position` is a Swift 6-ready, actor-based location positioning library for iOS and macOS with modern async/await APIs and AsyncSequence support.

[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg?style=flat)](https://developer.apple.com/swift)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2015.0+%20|%20macOS%2011.0+-blue.svg?style=flat)](https://developer.apple.com/swift)
[![Swift Package Manager](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg?style=flat)](https://swift.org/package-manager)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg?style=flat)](https://github.com/piemonte/Position/blob/main/LICENSE)

## Features

| Feature | Description |
|:-------:|:------------|
| 🚀 | **Swift 6** - Full concurrency support with actor isolation |
| ⚡ | **Modern async/await** - One-shot location requests with async/await |
| 🔄 | **AsyncSequence** - Reactive updates for location, heading, and authorization |
| 🎭 | **Actor-based** - Thread-safe by design with Swift concurrency |
| 📍 | Customizable location accuracy and filtering |
| 🌍 | Distance and time-based location filtering |
| 📡 | Continuous location tracking with configurable accuracy |
| 🧭 | Device heading and compass support (iOS only) |
| 🔐 | Permission management with async authorization requests |
| 📐 | Geospatial utilities for distance and bearing calculations |
| 🔋 | Battery-aware location accuracy adjustments |
| 📍 | Visit monitoring for significant location changes |
| 🏢 | Floor level detection in supported venues |
| 🏢 | Place data formatting and geocoding utilities |
| 📍 | vCard location sharing support |

## Requirements

- iOS 16.0+ / macOS 13.0+
- Swift 6.0+ (also supports Swift 5 mode)
- Xcode 16.0+

## Installation

### Swift Package Manager (Recommended)

Add Position to your project using Swift Package Manager:

1. In Xcode, select **File > Add Package Dependencies...**
2. Enter the repository URL: `https://github.com/piemonte/Position`
3. Select version `1.0.0` or later

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/piemonte/Position", from: "1.0.0")
]
```

## Quick Start

### 1. Configure Info.plist

Add the appropriate location usage descriptions to your app's `Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Your app needs location access to provide location-based features.</string>

<!-- Optional: For always authorization -->
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Your app needs location access even in the background.</string>
```

### 2. Basic Usage - Swift 6 Style

```swift
import Position

class LocationManager {
    let position = Position()
    
    func setup() async {
        // Check and request permissions
        let status = await position.locationServicesStatus
        
        switch status {
        case .notDetermined:
            let newStatus = await position.requestWhenInUseLocationAuthorization()
            print("Authorization result: \(newStatus)")
            
        case .allowedWhenInUse, .allowedAlways:
            await requestLocation()
            
        case .denied, .notAvailable:
            print("Location services unavailable")
        }
    }
    
    func requestLocation() async {
        do {
            // One-shot location request with async/await
            let location = try await position.currentLocation()
            print("📍 Location: \(location.coordinate)")
            
            // Or with custom accuracy
            let preciseLocation = try await position.currentLocation(
                desiredAccuracy: kCLLocationAccuracyBest
            )
            print("📍 Precise location: \(preciseLocation.coordinate)")
        } catch {
            print("❌ Location error: \(error)")
        }
    }
}
```

### 3. Continuous Updates with AsyncSequence

```swift
import Position

class LocationTracker {
    let position = Position()
    
    func startTracking() async {
        // Configure tracking parameters
        await position.setDistanceFilter(10) // meters
        position.trackingDesiredAccuracyWhenActive = kCLLocationAccuracyBest
        
        // Start location updates
        await position.startUpdating()
        
        // Consume location updates
        Task {
            for await location in position.locationUpdates {
                print("📍 New location: \(location.coordinate)")
                updateUI(with: location)
            }
        }
        
        // Monitor authorization changes
        Task {
            for await status in position.authorizationUpdates {
                print("🔐 Authorization changed: \(status)")
                handleAuthorizationChange(status)
            }
        }
        
        // Track heading updates (iOS only)
        Task {
            for await heading in position.headingUpdates {
                print("🧭 Heading: \(heading.trueHeading)°")
            }
        }
    }
    
    func stopTracking() async {
        await position.stopUpdating()
    }
}
```

### 4. SwiftUI Integration

```swift
import SwiftUI
import Position

@MainActor
class LocationViewModel: ObservableObject {
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: Position.LocationAuthorizationStatus = .notDetermined
    
    private let position = Position()
    private var locationTask: Task<Void, Never>?
    
    func startLocationUpdates() {
        locationTask = Task {
            await position.startUpdating()
            
            for await location in position.locationUpdates {
                currentLocation = location
            }
        }
    }
    
    func stopLocationUpdates() async {
        locationTask?.cancel()
        await position.stopUpdating()
    }
}

struct LocationView: View {
    @StateObject private var viewModel = LocationViewModel()
    
    var body: some View {
        VStack {
            if let location = viewModel.currentLocation {
                Text("📍 \(location.coordinate.latitude), \(location.coordinate.longitude)")
            } else {
                Text("No location available")
            }
        }
        .task {
            viewModel.startLocationUpdates()
        }
    }
}
```

## Advanced Features

### All Available AsyncSequences

```swift
let position = Position()

// Location updates
for await location in position.locationUpdates {
    print("Location: \(location)")
}

// Heading updates (iOS only)
for await heading in position.headingUpdates {
    print("Heading: \(heading)")
}

// Authorization status changes
for await status in position.authorizationUpdates {
    print("Auth status: \(status)")
}

// Floor changes (when available)
for await floor in position.floorUpdates {
    print("Floor: \(floor.level)")
}

// Visit monitoring
for await visit in position.visitUpdates {
    print("Visit at: \(visit.coordinate)")
}

// Error handling
for await error in position.errorUpdates {
    print("Location error: \(error)")
}
```

### Geospatial Calculations

```swift
import Position
import CoreLocation

let location1 = CLLocation(latitude: 37.7749, longitude: -122.4194) // San Francisco
let location2 = CLLocation(latitude: 34.0522, longitude: -118.2437) // Los Angeles

// Calculate distance
let distance = location1.distance(from: location2)
print("Distance: \(distance / 1000) km")

// Or use Measurement API for type-safe conversions
let measurement = Measurement(value: distance, unit: UnitLength.meters)
let km = measurement.converted(to: .kilometers).value
print("Distance: \(km) km")

// Calculate bearing
let bearing = location1.bearing(toLocation: location2)
print("Bearing: \(bearing)°")

// Calculate coordinate at bearing and distance
let coordinate = location1.locationCoordinate(withBearing: 45, distanceMeters: 1000)
print("New coordinate: \(coordinate)")

// Pretty distance description (localized)
let description = location1.prettyDistanceDescription(fromLocation: location2)
print("Distance: \(description)")
```

### Battery-Aware Tracking

```swift
let position = Position()

// Enable automatic battery management
await position.setAdjustLocationUseFromBatteryLevel(true)

// Manual accuracy adjustment based on app state
await position.setAdjustLocationUseWhenBackgrounded(true)

// Configure accuracy levels
position.trackingDesiredAccuracyWhenActive = kCLLocationAccuracyBest
position.trackingDesiredAccuracyWhenInBackground = kCLLocationAccuracyKilometer

// The library will automatically adjust accuracy when:
// - Battery level drops below 20% (switches to reduced accuracy)
// - App enters background (uses trackingDesiredAccuracyWhenInBackground)
// - App becomes active again (restores trackingDesiredAccuracyWhenActive)
```

### vCard Location Sharing

```swift
import Position
import CoreLocation

let location = CLLocation(latitude: 37.7749, longitude: -122.4194)

// Create vCard for sharing location (async version)
do {
    let vCardURL = try await location.vCard(name: "Golden Gate Bridge")
    // Share the vCard file URL
    print("vCard created at: \(vCardURL)")
} catch {
    print("Failed to create vCard: \(error)")
}
```

### Placemark Utilities

```swift
import Position
import CoreLocation

// Format address components
let address = CLPlacemark.shortStringFromAddressElements(
    address: "1 Infinite Loop",
    locality: "Cupertino",
    administrativeArea: "CA"
)
print("Formatted address: \(address ?? "")")

// Pretty descriptions from placemarks
if let placemark = somePlacemark {
    // Simple pretty description
    let description = placemark.prettyDescription()
    print("Location: \(description)")
    
    // Zoom-level aware description
    let zoomDescription = placemark.prettyDescription(withZoomLevel: 14)
    print("Location at zoom 14: \(zoomDescription)")
    
    // Full address string
    let fullAddress = placemark.stringFromPlacemark()
    print("Full address: \(fullAddress ?? "")")
}
```

## Migration Guide from 0.x to 1.0

### Major Changes

1. **No More Singleton**
   ```swift
   // Old
   Position.shared.performOneShotLocationUpdate(...)
   
   // New
   let position = Position()
   try await position.currentLocation()
   ```

2. **Async/Await Instead of Callbacks**
   ```swift
   // Old
   Position.shared.performOneShotLocationUpdate(withDesiredAccuracy: 100) { result in
       switch result {
       case .success(let location):
           print(location)
       case .failure(let error):
           print(error)
       }
   }
   
   // New
   do {
       let location = try await position.currentLocation(desiredAccuracy: 100)
       print(location)
   } catch {
       print(error)
   }
   ```

3. **AsyncSequence Instead of Observers**
   ```swift
   // Old
   Position.shared.addObserver(self)
   
   func position(_ position: Position, didUpdateTrackingLocations locations: [CLLocation]?) {
       // Handle update
   }
   
   // New
   for await location in position.locationUpdates {
       // Handle update
   }
   ```

4. **Actor-Based API**
   ```swift
   // Most Position methods are now async
   await position.startUpdating()
   await position.stopUpdating()
   let status = await position.locationServicesStatus
   ```

### Backward Compatibility

The observer pattern is maintained but deprecated. Update your code to use AsyncSequence for future compatibility.

## Platform Differences

| Feature | iOS | macOS |
|---------|-----|-------|
| Location Updates | ✅ | ✅ |
| Heading Updates | ✅ | ❌ |
| Visit Monitoring | ✅ | ✅ |
| Battery Monitoring | ✅ | ❌ |
| Background Updates | ✅ | ⚠️ Limited |
| Floor Detection | ✅ | ✅ |

## Best Practices

1. **Concurrency**: Position is an actor - use `await` when calling its methods
2. **Lifecycle**: Create Position instances as needed, no singleton required
3. **AsyncSequence**: Prefer AsyncSequence over deprecated observer pattern
4. **Error Handling**: Always handle errors in location requests
5. **Permissions**: Check authorization status before requesting location

## Documentation

Complete API documentation is available in the source code with comprehensive DocC comments.

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

## License

Position is available under the MIT license. See the [LICENSE](LICENSE) file for more information.
# Position

`Position` is a lightweight, modern location positioning library for iOS and macOS, built with Swift.

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg?style=flat)](https://developer.apple.com/swift)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2015.0+%20|%20macOS%2012.0+-blue.svg?style=flat)](https://developer.apple.com/swift)
[![Swift Package Manager](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg?style=flat)](https://swift.org/package-manager)
[![CocoaPods](https://img.shields.io/cocoapods/v/Position.svg?style=flat)](https://cocoapods.org/pods/Position)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg?style=flat)](https://github.com/piemonte/Position/blob/main/LICENSE)

## Features

| Feature | Description |
|:-------:|:------------|
| 📍 | One-shot customizable location requests with completion handlers |
| 🌍 | Distance and time-based location filtering for efficient tracking |
| 📡 | Continuous location tracking with configurable accuracy |
| 🧭 | Device heading and compass support (iOS only) |
| 🔐 | Permission management with status monitoring |
| 📐 | Geospatial math utilities for distance and bearing calculations |
| 🏢 | Place data formatting and geocoding utilities |
| 🔋 | Automatic battery-aware location accuracy adjustments (iOS only) |
| 📍 | vCard location sharing support |
| 👥 | Observer pattern for multiple listeners |
| 🏃 | Motion activity detection and tracking |
| 📱 | Visit monitoring for significant location changes |

## Requirements

- iOS 15.0+ / macOS 12.0+
- Swift 5.9+
- Xcode 15.0+

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

### CocoaPods

Add Position to your `Podfile`:

```ruby
pod 'Position', '~> 1.0.0'
```

Then run:
```bash
pod install
```

## Quick Start

### 1. Configure Info.plist

Add the appropriate location usage descriptions to your app's `Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Your app needs location access to provide location-based features.</string>

<!-- Optional: For always authorization -->
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Your app needs location access even in the background to provide continuous tracking.</string>
```

### 2. Basic Usage

```swift
import Position

class LocationViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Check permission status
        switch Position.shared.locationServicesStatus {
        case .allowed, .allowedWhenInUse, .allowedAlways:
            requestLocation()
        case .notDetermined:
            Position.shared.requestWhenInUseLocationAuthorization()
        case .denied, .restricted:
            showLocationServicesAlert()
        @unknown default:
            break
        }
    }
    
    func requestLocation() {
        // One-shot location request
        Position.shared.performOneShotLocationUpdate(withDesiredAccuracy: 100) { location, error in
            if let location = location {
                print("📍 Location: \(location.coordinate)")
            } else if let error = error {
                print("❌ Error: \(error)")
            }
        }
    }
}
```

### 3. Continuous Tracking

```swift
import Position

class TrackingViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configure tracking parameters
        Position.shared.distanceFilter = 10 // meters
        Position.shared.desiredAccuracy = .bestForNavigation
        Position.shared.activityType = .fitness
        
        // Add observer
        Position.shared.addObserver(self)
        
        // Start tracking
        Position.shared.startUpdatingLocation()
    }
    
    deinit {
        Position.shared.stopUpdatingLocation()
        Position.shared.removeObserver(self)
    }
}

// MARK: - PositionObserver
extension TrackingViewController: PositionObserver {
    func position(_ position: Position, didUpdateLocation location: CLLocation) {
        print("📍 New location: \(location.coordinate)")
    }
    
    func position(_ position: Position, didUpdateHeading heading: CLHeading) {
        print("🧭 Heading: \(heading.trueHeading)°")
    }
    
    func position(_ position: Position, didChangeAuthorizationStatus status: LocationAuthorizationStatus) {
        print("🔐 Authorization changed: \(status)")
    }
    
    func position(_ position: Position, didFailWithError error: Error) {
        print("❌ Error: \(error)")
    }
}
```

## Advanced Features

### Geospatial Calculations

```swift
import Position
import CoreLocation

let location1 = CLLocation(latitude: 37.7749, longitude: -122.4194) // San Francisco
let location2 = CLLocation(latitude: 34.0522, longitude: -118.2437) // Los Angeles

// Calculate distance
let distance = location1.distance(from: location2)
print("Distance: \(distance.metersToKilometers) km")

// Calculate bearing
let bearing = location1.bearing(to: location2)
print("Bearing: \(bearing)°")

// Calculate midpoint
let midpoint = location1.midpoint(to: location2)
print("Midpoint: \(midpoint.coordinate)")
```

### Visit Monitoring

```swift
// Start monitoring visits (significant location changes)
Position.shared.startMonitoringVisits()

// Handle visits in observer
func position(_ position: Position, didVisit visit: CLVisit) {
    print("📍 Visit at: \(visit.coordinate)")
    print("⏰ Arrival: \(visit.arrivalDate)")
    print("⏱️ Departure: \(visit.departureDate ?? Date())")
}
```

### Location Sharing

```swift
// Create vCard from location
if let vCardURL = currentLocation.vCard(withTitle: "My Location") {
    // Share via UIActivityViewController (iOS)
    let activityVC = UIActivityViewController(
        activityItems: [vCardURL],
        applicationActivities: nil
    )
    present(activityVC, animated: true)
}
```

### Battery-Aware Tracking (iOS)

Position automatically adjusts location accuracy based on battery level:

```swift
// Enable automatic battery management
Position.shared.adjustLocationUpdateAccuracyForBatteryLevel = true

// Or manually adjust based on battery
if UIDevice.current.batteryLevel < 0.2 {
    Position.shared.desiredAccuracy = .hundredMeters
}
```

## Platform Differences

| Feature | iOS | macOS |
|---------|-----|-------|
| Location Updates | ✅ | ✅ |
| Heading Updates | ✅ | ❌ |
| Visit Monitoring | ✅ | ✅ |
| Battery Monitoring | ✅ | ❌ |
| Background Updates | ✅ | ⚠️ Limited |
| Activity Type | ✅ | ❌ |

## Best Practices

1. **Privacy First**: Always respect user privacy and request only the permissions you need
2. **Battery Life**: Use appropriate accuracy levels and stop updates when not needed
3. **Background Usage**: Only request always authorization if truly necessary
4. **Error Handling**: Always handle location errors gracefully
5. **Testing**: Test with various permission states and location availability

## Documentation

Complete API documentation is available at [piemonte.github.io/Position](https://piemonte.github.io/Position).

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Support

- 🐛 Found a bug? Open an [issue](https://github.com/piemonte/Position/issues)
- 💡 Feature idea? Open an [issue](https://github.com/piemonte/Position/issues)
- 📖 Questions? Check our [documentation](https://piemonte.github.io/Position) or use [Stack Overflow](https://stackoverflow.com/questions/tagged/position-swift) with tag `position-swift`

## License

Position is available under the MIT license. See the [LICENSE](LICENSE) file for more information.

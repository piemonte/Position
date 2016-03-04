![Position](https://raw.githubusercontent.com/piemonte/Position/master/Position.png)

`Position` is a [Swift](https://developer.apple.com/swift/) and efficient location positioning library for iOS. The library is a simple wrapper around CoreLocation that offers a variety of functionality and offers a path for potentially more interesting features in the future. Contributions are welcome.

### Features
- [x] simple [Swift](https://developer.apple.com/swift/) API
- [x] multi-delegate observer support
- [x] “one shot” block-based location requesting (more robust than iOS 9 Core Location API)
- [x] distance and time based location filtering
- [x] automatic low-power location adjustment when backgrounded setting
- [x] automatic low-power location adjustment from battery monitoring setting
- [x] automatic motion-based location adjustment
- [ ] low-power geo-fenced based background location updating (future)

[![Pod Version](https://img.shields.io/cocoapods/v/Position.svg?style=flat)](http://cocoadocs.org/docsets/Position/) [![Build Status](https://travis-ci.org/piemonte/Position.svg?branch=master)](https://travis-ci.org/piemonte/Position)

## Installation

### CocoaPods

`Position` is available for installation using the Cocoa dependency manager [CocoaPods](http://cocoapods.org/).

To integrate, add the following to your `Podfile`:

```ruby
source ‘https://github.com/CocoaPods/Specs.git'
platform :iOS, ‘9.0’
use_frameworks!

pod ‘Position’
```	

### Carthage

Installation is also available using the dependency manager [Carthage](https://github.com/Carthage/Carthage).

To integrate, add the following line to your `Cartfile`:

```ogdl
github “piemonte/Position” >= 0.0.1
```

### Swift Package Manager

Installation is available using the [Swift Package Manager](https://swift.org/package-manager/), add the following in your `Package.swift` :

```Swift
import PackageDescription

let package = Package(
    name: "HelloWorld",
    dependencies: [
        .Package(url: "https://github.com/piemonte/Position.git", majorVersion: 0),
    ]
)
```

### Manual

You can also simply copy the `Position.swift` file into your Xcode project.

## Usage

The sample project provides an example of how to integrate `Position`, otherwise you can follow these steps.

Ensure your app’s Info.plist file includes both a location usage description, required device capability “location-services”, and  required background mode (if necessary).

See sample project for examples too.

Import the file and setup your component to be a PositionObserver, if you’d like it to be a delegate.

```swift
import Position

class ViewController: UIViewController, PositionObserver {
	// ...
```

Have the component add itself as an observer and configure the appropriate settings.

```swift
    override func viewDidLoad() {
        super.viewDidLoad()

        // ...
        
        Position.sharedPosition.addObserver(self)
        Position.sharedPosition.distanceFilter = 20
        
        if Position.sharedPosition.locationServicesStatus == .AllowedWhenInUse ||
           Position.sharedPosition.locationServicesStatus == .AllowedAlways {
            Position.sharedPosition.performOneShotLocationUpdateWithDesiredAccuracy(250) { (location, error) -> () in
                print(location, error)
            }
        } else {
            // request permissions based on the type of location support required.
            Position.sharedPosition.requestWhenInUseLocationAuthorization()
            // Position.sharedPosition.requestAlwaysLocationAuthorization()
        }
    }
```

If desired, begin tracking changes in motion activity.

```swift
    if Position.sharedPosition.motionActivityStatus == .Allowed {
        Position.sharedPosition.startUpdatingActivity()
    } else {
        Position.sharedPosition.requestMotionActivityAuthorization()
    }
```

Observe delegation, if necessary.

```swift
    func position(position: Position, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus) {
        // location authorization did change, often this may even be triggered on application resume if the user updated settings
    }

    func position(position: Position, didChangeMotionAuthorizationStatus status: MotionAuthorizationStatus) {
        // motion authorization did change, often this may even be triggered on application resume if the user updated settings
    }

    // error handling
    func position(position: Position, didFailWithError error: NSError?) {
    }

    // location
    func position(position: Position, didUpdateOneShotLocation location: CLLocation?) {
    }

    func position(position: Position, didUpdateTrackingLocation locations: [CLLocation]?) {
    }

    func position(position: Position, didUpdateFloor floor: CLFloor) {
    }

    func position(position: Position, didVisit visit: CLVisit?) {
    }

    func position(position: Position, didChangeDesiredAccurary desiredAccuracy: Double) {
    }
    
    // motion
    func position(position: Position, didChangeActivity activity: MotionActivityType) {
    }
```

**Remember** when creating location-based apps, respect the privacy of your users and be responsible for how you use their location. This is especially true if your application requires location permission `kCLAuthorizationStatusAuthorizedAlways`.

## Community

- Need help? Use [Stack Overflow](http://stackoverflow.com/questions/tagged/position-swift) with the tag ‘position-swift’.
- Questions? Use [Stack Overflow](http://stackoverflow.com/questions/tagged/position-swift) with the tag ‘position-swift’.
- Found a bug? Open an [issue](https://github.com/piemonte/position/issues).
- Feature idea? Open an [issue](https://github.com/piemonte/position/issues).
- Want to contribute? Submit a [pull request](https://github.com/piemonte/position/pulls).

## Resources

* [Location and Maps Programming Guide](https://developer.apple.com/library/ios/documentation/UserExperience/Conceptual/LocationAwarenessPG/Introduction/Introduction.html)
* [Core Location Framework Reference](https://developer.apple.com/library/ios/documentation/CoreLocation/Reference/CoreLocation_Framework/index.html)
* [Core Location in iOS 8](http://nshipster.com/core-location-in-ios-8/)
* [objc.io Issue #8, The Quadcopter Navigator App](https://www.objc.io/issues/8-quadcopter/the-quadcopter-navigator-app/)

## License

Position is available under the MIT license, see the [LICENSE](https://github.com/piemonte/position/blob/master/LICENSE) file for more information.


![Position](https://raw.githubusercontent.com/piemonte/Position/master/Position.png)

`Position` is a [Swift](https://developer.apple.com/swift/) and efficient location positioning library for iOS. The library is just a simple start but has potential for more interesting features in the future. Contributions are welcome.

### Features
- [x] simple [Swift](https://developer.apple.com/swift/) API
- [x] “one shot” block-based location requesting (more robust than iOS 9 Core Location API)
- [x] distance and time based location filtering
- [x] automatic low-power location adjustment when backgrounded setting
- [x] automatic low-power location adjustment from battery monitoring setting
- [ ] low-power geo-fenced based background location updating (future)
- [ ] automatic motion-based location adjustment (future)

[![Pod Version](https://img.shields.io/cocoapods/v/Position.svg?style=flat)](http://cocoadocs.org/docsets/Position/)

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
    name: “HelloWorld”,
    dependencies: [
        .Package(url: “https://github.com/piemonte/Position.git”, majorVersion: 0),
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
    override fun viewDidLoad() {
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
            //Position.sharedPosition.requestAlwaysLocationAuthorization()
        }
    }
```

Observe delegation, if necessary.

```swift
    fun position(position: Position, didChangeLocationAuthorizationStatus status: AuthorizationStatus) {
        // location authorization did change, often this may even be triggered on application resume if the user updated settings
    }
    
    // error handling
    fun position(position: Position, didFailWithError error: NSError?) {
    }

    // location
    fun position(position: Position, didUpdateOneShotLocation location: CLLocation?) {
    }
    
    fun position(position: Position, didUpdateTrackingLocation locations: [CLLocation]?) {
    }
    
    fun position(position: Position, didUpdateFloor floor: CLFloor) {
    }

    fun position(position: Position, didVisit visit: CLVisit?) {
    }
    
    fun position(position: Position, didChangeDesiredAccurary desiredAccuracy: Double) {
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


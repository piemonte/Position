`Position` is a [Swift](https://developer.apple.com/swift/) and efficient location positioning library for iOS.

[![Pod Version](https://img.shields.io/cocoapods/v/Position.svg?style=flat)](http://cocoadocs.org/docsets/Position/) [![Build Status](https://travis-ci.org/piemonte/Position.svg?branch=master)](https://travis-ci.org/piemonte/Position) [![Swift Version](https://img.shields.io/badge/language-swift%205.0-brightgreen.svg)](https://developer.apple.com/swift) [![GitHub license](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://github.com/piemonte/Position/blob/master/LICENSE)


|  | Features |
|:---------:|:---------------------------------------------------------------|
| &#9732; | “one shot” closure based location requests |
| &#128274; | authorization check and response support |
| &#127756; | distance and time-based filtering |
| &#127745; | automatic low-power location tracking adjustment when backgrounded setting |
| &#128267; | automatic low-power location tracking adjustment from battery monitoring setting |
| &#128038; | [Swift 5](https://developer.apple.com/swift/) |

Need a different version of Swift?
* `5.0` - Target your Podfile to the latest release or master
* `4.2` - Target your Podfile to the `swift4.2` branch
* `4.0` - Target your Podfile to the `swift4.0` branch

## Quick Start

`Position` is available for installation using the Cocoa dependency manager [CocoaPods](http://cocoapods.org/). Alternatively, you can simply copy the `Position` source files into your Xcode project.

```ruby
# CocoaPods
pod "Position", "~> 0.7.0"

# Carthage
github "piemonte/Position" ~> 0.7.0

# SwiftPM
let package = Package(
    dependencies: [
        .Package(url: "https://github.com/piemonte/Position", majorVersion: 0)
    ]
)
```

## Usage

The sample project provides an example of how to integrate `Position`, otherwise you can follow these steps.

Ensure your app’s `Info.plist` file includes both a location usage description, required device capability “location-services”, and  required background mode (if necessary).

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

        Position.shared.addObserver(self)
        Position.shared.distanceFilter = 20

        if Position.shared.locationServicesStatus == .allowedWhenInUse ||
           Position.shared.locationServicesStatus == .allowedAlways {
            Position.shared.performOneShotLocationUpdate(withDesiredAccuracy: 250) { (location, error) -> () in
                print(location, error)
            }
        } else {
            // request permissions based on the type of location support required.
            Position.shared.requestWhenInUseLocationAuthorization()
            // Position.shared.requestAlwaysLocationAuthorization()
        }
    }
```

Observe delegation, if necessary.

```swift
    func position(position: Position, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus) {
        // location authorization did change, often this may even be triggered on application resume if the user updated settings
    }
```

**Remember** when creating location-based apps, respect the privacy of your users and be responsible for how you use their location. This is especially true if your application requires location permission `kCLAuthorizationStatusAuthorizedAlways`.

## Documentation

You can find [the docs here](https://piemonte.github.io/Position). Documentation is generated with [jazzy](https://github.com/realm/jazzy) and hosted on [GitHub-Pages](https://pages.github.com).

## Community

- Need help? Use [Stack Overflow](http://stackoverflow.com/questions/tagged/position-swift) with the tag ‘position-swift’.
- Questions? Use [Stack Overflow](http://stackoverflow.com/questions/tagged/position-swift) with the tag ‘position-swift’.
- Found a bug? Open an [issue](https://github.com/piemonte/position/issues).
- Feature idea? Open an [issue](https://github.com/piemonte/position/issues).
- Want to contribute? Submit a [pull request](https://github.com/piemonte/position/pulls).

## Resources

* [Swift Evolution](https://github.com/apple/swift-evolution)
* [Location and Maps Programming Guide](https://developer.apple.com/library/ios/documentation/UserExperience/Conceptual/LocationAwarenessPG/Introduction/Introduction.html)
* [Core Location Framework Reference](https://developer.apple.com/library/ios/documentation/CoreLocation/Reference/CoreLocation_Framework/index.html)
* [Core Location in iOS 8](http://nshipster.com/core-location-in-ios-8/)

## License

Position is available under the MIT license, see the [LICENSE](https://github.com/piemonte/Position/blob/master/LICENSE) file for more information.

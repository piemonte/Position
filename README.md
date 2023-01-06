`Position` is a lightweight location positioning library for iOS.

[![Build Status](https://travis-ci.com/piemonte/Position.svg?branch=master)](https://travis-ci.com/piemonte/Position) [![Pod Version](https://img.shields.io/cocoapods/v/Position.svg?style=flat)](http://cocoadocs.org/docsets/Position/) [![Swift Version](https://img.shields.io/badge/language-swift%205.0-brightgreen.svg)](https://developer.apple.com/swift) [![GitHub license](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://github.com/piemonte/Position/blob/master/LICENSE)


|  | Features |
|:---------:|:---------------------------------------------------------------|
| &#9732; | “one shot” customizable location requests |
| &#127756; | distance and time-based location filtering |
| &#128752; | location tracking support |
| &#129517; | device heading support |
| &#128274; | permission check and response support |
| &#127760; | geospatial math utilities |
| &#127961; | place data formatting utilities |
| &#128202; | automatic low-battery location modes |
| &#128205; | vCard location creation |
| &#128301; | multiple component observer-based architecture |

## Quick Start

`Position` is available for installation using the [Swift Package Manager](https://www.swift.org/package-manager/) or the Cocoa dependency manager [CocoaPods](http://cocoapods.org/). Alternatively, you can simply copy the `Position` source files into your Xcode project.

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

See sample project for examples.

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

To share a location using a vCard, simply call the vCard function on any location object instance.

```swift
   let fileURL = location.vCard()
```

## Core Location Additions

Position is bundled with a variety of [additions to Core Location](https://github.com/piemonte/Position/blob/main/Sources/CoreLocation%2BAdditions.swift), such as geospatial math utilities. For example, one can calculation the direction between two coordinate points enabling [directional views](https://gist.github.com/piemonte/e7876775f43e73e30b09f0fc1a77cad0) and other waypoint representations. 

## Documentation

You can find [the docs here](https://piemonte.github.io/Position). Documentation is generated with [jazzy](https://github.com/realm/jazzy) and hosted on [GitHub-Pages](https://pages.github.com).

## Community

- Need help? Use [Stack Overflow](http://stackoverflow.com/questions/tagged/position-swift) with the tag ‘position-swift’.
- Questions? Use [Stack Overflow](http://stackoverflow.com/questions/tagged/position-swift) with the tag ‘position-swift’.
- Found a bug? Open an [issue](https://github.com/piemonte/position/issues).
- Feature idea? Open an [issue](https://github.com/piemonte/position/issues).
- Want to contribute? Submit a [pull request](https://github.com/piemonte/position/pulls).

## Resources

* [Location and Maps Programming Guide](https://developer.apple.com/library/ios/documentation/UserExperience/Conceptual/LocationAwarenessPG/Introduction/Introduction.html)
* [Core Location Framework Reference](https://developer.apple.com/library/ios/documentation/CoreLocation/Reference/CoreLocation_Framework/index.html)
* [Core Location – NSHipster](http://nshipster.com/core-location-in-ios-8/)

## License

Position is available under the MIT license, see the [LICENSE](https://github.com/piemonte/Position/blob/master/LICENSE) file for more information.

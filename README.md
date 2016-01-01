## Position

`Position` is a [Swift](https://developer.apple.com/swift/) and efficient location positioning library for iOS.

### Features
- [x] one shot block-based location requesting (more robust than iOS 9 API)
- [x] low-power location use when backgrounding
- [ ] low-power activity-based location use
- [ ] low-power geo-fenced based location tracking
- [x] simple API

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

// TODO

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


//
//  Position+CLLocation.swift
//
//  Created by patrick piemonte on 3/1/15.
//
//  The MIT License (MIT)
//
//  Copyright (c) 2015-present patrick piemonte (http://patrickpiemonte.com/)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation
import CoreLocation
import Contacts
import simd

extension CLLocationManager {

    public static var backgroundCapabilitiesEnabled: Bool {
         guard let capabilities = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] else {
             return false
         }
         return capabilities.contains("location")
     }

}

extension CLLocation {

    /// Calculates the location coordinate for a given bearing and distance from this location as origin.
    /// https://www.movable-type.co.uk/scripts/latlong.html
    ///
    /// - Parameters:
    ///   - bearingDegrees: Bearing in degrees
    ///   - distanceMeters: Distance in meters
    ///   - origin: Coordinate from which the result is calculated
    /// - Returns: Location coordinate at the bearing and distance from origin coordinate.
    public func locationCoordinate(withBearing bearingDegrees: Double, distanceMeters: Double) -> CLLocationCoordinate2D {
        let sigma = distanceMeters / coordinate.earthRadiusInMeters

        let bearingRadians = Measurement(value: bearingDegrees, unit: UnitAngle.degrees).converted(to: .radians).value

        let lat1 = Measurement(value: self.coordinate.latitude, unit: UnitAngle.degrees).converted(to: .radians).value
        let lon1 = Measurement(value: self.coordinate.longitude, unit: UnitAngle.degrees).converted(to: .radians).value

        let lat2 = asin(sin(lat1) * cos(sigma) + cos(lat1) * sin(sigma) * cos(bearingRadians))
        let lon2 = lon1 + atan2(sin(bearingRadians) * sin(sigma) * cos(lat1), cos(sigma) - sin(lat1) * sin(lat2))

        let lat3 = Measurement(value: lat2, unit: UnitAngle.radians).converted(to: .degrees).value
        let lon3 = Measurement(value: lon2, unit: UnitAngle.radians).converted(to: .degrees).value

        return CLLocationCoordinate2D(latitude: lat3, longitude: lon3)
    }

    /// Calculate the bearing from this location object to another
    ///
    /// - Parameter toLocation: target location
    /// - Returns: Bearing in degrees.
    public func bearing(toLocation: CLLocation) -> CLLocationDirection {
        let fromLat = Measurement(value: coordinate.latitude, unit: UnitAngle.degrees).converted(to: .radians).value
        let fromLon = Measurement(value: coordinate.longitude, unit: UnitAngle.degrees).converted(to: .radians).value

        let toLat = Measurement(value: toLocation.coordinate.latitude, unit: UnitAngle.degrees).converted(to: .radians).value
        let toLon = Measurement(value: toLocation.coordinate.longitude, unit: UnitAngle.degrees).converted(to: .radians).value

        let y = sin(toLon - fromLon) * cos(toLat)
        let x = cos(fromLat) * sin(toLat) - sin(fromLat) * cos(toLat) * cos(toLon - fromLon)

        var bearingInDegrees: CLLocationDirection = Measurement(value: atan2(y, x), unit: UnitAngle.radians).converted(to: .degrees).value as CLLocationDirection
        bearingInDegrees = (bearingInDegrees + 360.0).truncatingRemainder(dividingBy: 360.0)

        return bearingInDegrees
    }

    /// Calcualtes the bearing angle from this location object to another with device heading
    /// - Parameters:
    ///   - toLocation: to location point
    ///   - heading: heading in degrees of device
    /// - Returns: Bearing angle  in radians.
    public func bearingAngleInRadians(toLocation: CLLocation, with heading: CLHeading) -> Double? {
        guard heading.headingAccuracy >= 0 else { return nil }
        let bearing = bearing(toLocation: toLocation)
        let bearingInRadians = Measurement(value: bearing, unit: UnitAngle.degrees).converted(to: .radians).value
        let headingInRadians = Measurement(value: heading.trueHeading, unit: UnitAngle.degrees).converted(to: .radians).value
        return bearingInRadians - headingInRadians
    }
}

extension CLLocationCoordinate2D {

    /// WGS-84 radius of the earth, in meters, at the given point.
    /// https://en.wikipedia.org/wiki/Earth_radius#Geocentric_radius
    public var earthRadiusInMeters: Double {
        let WGS84EquatorialRadius  = 6_378_137.0
        let WGS84PolarRadius = 6_356_752.3
        let a = WGS84EquatorialRadius
        let b = WGS84PolarRadius

        let phi = Measurement(value: self.latitude, unit: UnitAngle.degrees).converted(to: .radians).value

        let numerator = pow(a * a * cos(phi), 2) + pow(b * b * sin(phi), 2)
        let denominator = pow(a * cos(phi), 2) + pow(b * sin(phi), 2)
        let radius = sqrt(numerator/denominator)
        return radius
    }

}

extension CLLocation {

    public func translation(fromLocation location: CLLocation) -> simd_double3 {
        let midPoint = CLLocation(latitude: self.coordinate.latitude, longitude: location.coordinate.longitude)

        let distanceLatitude = location.distance(from: midPoint)
        let translationLatitude = location.coordinate.latitude > midPoint.coordinate.latitude ? distanceLatitude
                                                                                              : -distanceLatitude
        let distanceLongitude = distance(from: midPoint)
        let translationLongitude = coordinate.longitude > midPoint.coordinate.longitude ? -distanceLongitude
                                                                                        : distanceLongitude

        let translationAltitude = location.altitude - self.altitude

        return simd_double3(translationLatitude, translationLongitude, translationAltitude)
    }

    func translate(_ translation: simd_double3) -> CLLocation {
        let coordinateLatitude = self.locationCoordinate(withBearing: 0, distanceMeters: translation.x)
        let coordinateLongitude = self.locationCoordinate(withBearing: 90, distanceMeters: translation.y)
        let coordinate = CLLocationCoordinate2D( latitude: coordinateLatitude.latitude, longitude: coordinateLongitude.longitude)
        let altitude = self.altitude + translation.z
        return CLLocation(coordinate: coordinate,
                          altitude: altitude,
                          horizontalAccuracy: self.horizontalAccuracy,
                          verticalAccuracy: self.verticalAccuracy,
                          timestamp: self.timestamp)
    }

}

// MARK: - vCard

extension CLLocation {

    /// Creates a Virtual Contact File (VCF) or vCard for the location.
    ///
    /// - Returns: Local file path URL.
    public func vCard(name: String = "Location") -> URL? {
        guard let cachesPathString = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first else {
            return nil
        }

        guard CLLocationCoordinate2DIsValid(self.coordinate) else {
            return nil
        }

        let vCardString = [
            "BEGIN:VCARD",
            "VERSION:3.0",
            "N:;\(name);;;",
            "FN:\(name)",
            "item1.URL;type=pref:http://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)",
            "item1.X-ABLabel:map url",
            "END:VCARD"
            ].joined(separator: "\n")

        let vCardFilePath = (cachesPathString as NSString).appendingPathComponent("\(name).loc.vcf")
        do {
            try vCardString.write(toFile: vCardFilePath, atomically: true, encoding: String.Encoding.utf8)
        } catch let error {
            print("error, \(error), saving vCard \(vCardString) to file path \(vCardFilePath)")
        }

        return URL(fileURLWithPath: vCardFilePath)
    }

}

// MARK: - Strings

extension CLLocation {

    /// Pretty description of a distance from the location to another.
    /// - Parameters:
    ///   - location: Location from which to display distance.
    ///   - locale: Locale to display the units of measurement.
    /// - Returns: A pretty description string of a distance in the specified locale.
    public func prettyDistanceDescription(fromLocation location: CLLocation, locale: Locale = Locale.current) -> String {
        let distanceInMeters = self.distance(from: location)
        let formatter = MeasurementFormatter()
        formatter.unitStyle = .medium
        let distance = Measurement(value: distanceInMeters, unit: UnitLength.meters)
        formatter.locale = locale
        return formatter.string(from: distance)
    }

}

extension CLPlacemark {

    /// Short description of a placemark
    /// - Parameters:
    ///   - address: Address of a place
    ///   - locality: Locality of a place
    ///   - administrativeArea: administrative area of a place
    /// - Returns: Short formatted string address
    public static func shortStringFromAddressElements(address: String?,
                                                     locality: String?,
                                                     administrativeArea: String?) -> String? {
        let postalAddress = CNMutablePostalAddress()
        if let address = address {
            postalAddress.street = address
        }
        if let locality = locality {
            postalAddress.city = locality
        }
        if let administrativeArea = administrativeArea {
            postalAddress.state = administrativeArea
        }
        let postalFormatter = CNPostalAddressFormatter()
        return postalFormatter.string(for: postalAddress)
    }

    /// Address description of a placemark
    /// - Returns: Formatted string address
    public func stringFromPlacemark() -> String? {
        if let postalAddress = self.postalAddress {
            let postalFormatter = CNPostalAddressFormatter()
            return postalFormatter.string(for: postalAddress)
        } else {
            return nil
        }
    }

    /// Short and pretty description of the placemark.
    /// - Returns: area of interest, sublocality or locality or subadministrative area, administrative area
    public func prettyDescription() -> String {
        var prettyDescription = ""
        if let areaOfInterest = areasOfInterest?.first {
            prettyDescription += areaOfInterest
        }
        if prettyDescription.isEmpty {
            if let sublocality = self.subLocality {
                prettyDescription += sublocality
            }
        }
        if prettyDescription.isEmpty {
            if let locality = self.locality {
                prettyDescription += locality
            }
        }
        if prettyDescription.isEmpty {
            if let subadministrativeArea = self.subAdministrativeArea {
                prettyDescription += subadministrativeArea
            }
            if let administrativeArea = self.administrativeArea {
                if !prettyDescription.isEmpty {
                    prettyDescription += ", "
                }
                prettyDescription += administrativeArea
            }
        }
        if prettyDescription.isEmpty {
            if let inlandWater = inlandWater {
                prettyDescription += inlandWater
            } else if let ocean = ocean {
                prettyDescription += ocean
            }
        }
        if prettyDescription.isEmpty {
            if let country = country {
                prettyDescription += country
            }
        }
        return prettyDescription
    }

    public func prettyDescription(withZoomLevel zoomLevel: Double) -> String {
        var prettyDescription = ""
        if let areaOfInterest = areasOfInterest?.first, zoomLevel >= 18 {
            prettyDescription += areaOfInterest
        }
        if prettyDescription.isEmpty {
            if let inlandWater = inlandWater {
                prettyDescription += inlandWater
            } else if let ocean = ocean {
                prettyDescription += ocean
            }
        }
        if prettyDescription.isEmpty {
            if let sublocality = self.subLocality {
                prettyDescription += sublocality
            }
        }
        prettyDescription = zoomLevel >= 14 ? prettyDescription : ""
        if prettyDescription.isEmpty {
            if let inlandWater = inlandWater {
                prettyDescription += inlandWater
            } else if let ocean = ocean {
                prettyDescription += ocean
            }
        }
        if prettyDescription.isEmpty {
            if let locality = self.locality {
                prettyDescription += locality
            }
        }
        prettyDescription = zoomLevel >= 10 ? prettyDescription : ""
        if prettyDescription.isEmpty {
            if let inlandWater = inlandWater {
                prettyDescription += inlandWater
            } else if let ocean = ocean {
                prettyDescription += ocean
            }
        }
        if prettyDescription.isEmpty {
            if let subadministrativeArea = self.subAdministrativeArea {
                prettyDescription += subadministrativeArea
            }
        }
        prettyDescription = zoomLevel >= 5 ? prettyDescription : ""
        if prettyDescription.isEmpty {
            if let inlandWater = inlandWater {
                prettyDescription += inlandWater
            } else if let ocean = ocean {
                prettyDescription += ocean
            }
        }
        if prettyDescription.isEmpty {
            if let administrativeArea = self.administrativeArea {
                prettyDescription += administrativeArea
            }
        }
        if prettyDescription.isEmpty {
            if let country = country {
                prettyDescription += country
            }
        }
        return prettyDescription
    }

}

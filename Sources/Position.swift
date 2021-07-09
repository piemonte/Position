//
//  Position.swift
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

import UIKit
import Foundation
import CoreLocation

/// Position location authorization protocol.
public protocol PositionAuthorizationObserver: AnyObject {
    /// Permission change authorization status, this may be triggered on application resume if the app settings have changed
    func position(_ position: Position, didChangeLocationAuthorizationStatus status: Position.LocationAuthorizationStatus)
}

/// Position location updates protocol.
public protocol PositionObserver: AnyObject {

    /// Location positioning one-shot updates
    func position(_ position: Position, didUpdateOneShotLocation location: CLLocation?)

    /// Location positioning tracking updates
    func position(_ position: Position, didUpdateTrackingLocations locations: [CLLocation]?)

    /// Location accuracy updates
    func position(_ position: Position, didChangeDesiredAccurary desiredAccuracy: Double)

    // Location extras
    func position(_ position: Position, didUpdateFloor floor: CLFloor)
    func position(_ position: Position, didVisit visit: CLVisit?)

    /// Error handling
    func position(_ position: Position, didFailWithError error: Error?)

}

/// Position heading updates protocol.
public protocol PositionHeadingObserver: AnyObject {
    func position(_ postiion: Position, didUpdateHeading newHeading: CLHeading)
}

/// 🛰 Position, Swift and efficient location positioning.
open class Position {

    // MARK: - types

    /// Location authorization status
    public enum LocationAuthorizationStatus: Int, CustomStringConvertible {
        case notDetermined = 0
        case notAvailable
        case denied
        case allowedWhenInUse
        case allowedAlways

        public var description: String {
            get {
                switch self {
                case .notDetermined:
                    return "Not Determined"
                case .notAvailable:
                    return "Not Available"
                case .denied:
                    return "Denied"
                case .allowedWhenInUse:
                    return "When In Use"
                case .allowedAlways:
                    return "Allowed Always"
                }
            }
        }
    }

    /// Location accuracy authorization status
    public enum LocationAccuracyAuthorizationStatus: Int {
        case fullAccuracy = 0
        case reducedAccuracy
    }

    /// Possible error types
    public enum ErrorType: Error, CustomStringConvertible {
        case timedOut
        case restricted
        case cancelled

        public var description: String {
            get {
                switch self {
                case .timedOut:
                    return "Timed out"
                case .restricted:
                    return "Restricted"
                case .cancelled:
                    return "Cancelled"
                }
            }
        }
    }

    /// Completion handler for one-shot location requests
    public typealias OneShotCompletionHandler = (Swift.Result<CLLocation, Error>) -> Void

    /// Time based filter constant
    public static let TimeFilterNone: TimeInterval      = 0.0
    /// Time based filter constant
    public static let TimeFilter5Minutes: TimeInterval  = 5.0 * 60.0
    /// Time based filter constant
    public static let TimeFilter10Minutes: TimeInterval = 10.0 * 60.0

    /// A statute mile to be 8 furlongs or 1609.344 meters
    public static let MilesToMetersRatio: Double        = 1609.344

    // MARK: - singleton

    /// Shared singleton
    public static let shared = Position()

    // MARK: - properties

    /// Distance in meters a device must move before updating location.
    public var distanceFilter: Double {
        get {
            _deviceLocationManager.distanceFilter
        }
        set {
            _deviceLocationManager.distanceFilter = newValue
        }
    }

    /// Time that must pass for a device before updating location.
    public var timeFilter: TimeInterval {
        get {
            _deviceLocationManager.timeFilter
        }
        set {
            _deviceLocationManager.timeFilter = newValue
        }
    }

    /// When `true`, location will reduce power usage from adjusted accuracy when backgrounded.
    public var adjustLocationUseWhenBackgrounded: Bool = false {
        didSet {
            if _deviceLocationManager.isUpdatingLowPowerLocation == true {
                _deviceLocationManager.stopLowPowerUpdating()
                _deviceLocationManager.startUpdating()
            }
        }
    }

    /// When `true`, location will reduce power usage from adjusted accuracy based on the current battery level.
    public var adjustLocationUseFromBatteryLevel: Bool = false {
        didSet {
            UIDevice.current.isBatteryMonitoringEnabled = self.adjustLocationUseFromBatteryLevel
        }
    }

    /// Location tracking desired accuracy when the app is active.
    public var trackingDesiredAccuracyWhenActive: Double {
        get {
            _deviceLocationManager.trackingDesiredAccuracyActive
        }
        set {
            _deviceLocationManager.trackingDesiredAccuracyActive = newValue
        }
    }

    /// Location tracking desired accuracy when the app is in the background.
    public var trackingDesiredAccuracyWhenInBackground: Double {
        get {
            _deviceLocationManager.trackingDesiredAccuracyBackground
        }
        set {
            _deviceLocationManager.trackingDesiredAccuracyBackground = newValue
        }
    }

    /// `true` when location services are updating
    public var isUpdatingLocation: Bool {
        _deviceLocationManager.isUpdatingLocation == true || _deviceLocationManager.isUpdatingLowPowerLocation == true
    }

    /// Last determined location
    public var location: CLLocation? {
        _deviceLocationManager.location
    }

    /// Last determined heading
    public var heading: CLHeading? {
        _deviceLocationManager.heading
    }

    // MARK: - ivars

    internal private(set) var _authorizationObservers: NSHashTable<AnyObject>?
    internal private(set) var _observers: NSHashTable<AnyObject>?
    internal private(set) var _headingObservers: NSHashTable<AnyObject>?

    internal private(set) var _deviceLocationManager: DeviceLocationManager = DeviceLocationManager()
    internal private(set) var _updating: Bool = false

    // MARK: - object lifecycle

    public init() {
        _deviceLocationManager.delegate = self

        addBatteryObservers()
        addAppObservers()
    }

    deinit {
        removeAppObservers()
        removeBatteryObservers()
    }
}

// MARK: - observers

extension Position {

    /// Adds an authorization observer.
    ///
    /// - Parameter observer: Observing instance.
    public func addAuthorizationObserver(_ observer: PositionAuthorizationObserver) {
        if _authorizationObservers == nil {
            _authorizationObservers = NSHashTable.weakObjects()
        }

        if _authorizationObservers?.contains(observer) == false {
            _authorizationObservers?.add(observer)
        }
    }

    /// Removes an authorization observer.
    ///
    /// - Parameter observer: Observing instance.
    public func removeAuthorizationObserver(_ observer: PositionAuthorizationObserver) {
        if _authorizationObservers?.contains(observer) == true {
            _authorizationObservers?.remove(observer)
        }
        if _authorizationObservers?.count == 0 {
            _authorizationObservers = nil
        }
    }

    /// Adds a position location observer.
    ///
    /// - Parameter observer: Observing instance.
    public func addObserver(_ observer: PositionObserver) {
        if _observers == nil {
            _observers = NSHashTable.weakObjects()
        }

        if _observers?.contains(observer) == false {
            _observers?.add(observer)
        }
    }

    /// Removes a position location observer.
    ///
    /// - Parameter observer: Observing instance.
    public func removeObserver(_ observer: PositionObserver) {
        if _observers?.contains(observer) == true {
            _observers?.remove(observer)
        }
        if _observers?.count == 0 {
            _observers = nil
        }
    }

    /// Adds a position heading observer.
    ///
    /// - Parameter observer: Observing instance.
    public func addHeadingObserver(_ observer: PositionHeadingObserver) {
        if _headingObservers == nil {
            _headingObservers = NSHashTable.weakObjects()
        }

        if _headingObservers?.contains(observer) == false {
            _headingObservers?.add(observer)
        }
    }

    /// Removes a position heading observer.
    ///
    /// - Parameter observer: Observing instance.
    public func removeHeadingObserver(_ observer: PositionHeadingObserver) {
        if _headingObservers?.contains(observer) == true {
            _headingObservers?.remove(observer)
        }
        if _headingObservers?.count == 0 {
            _headingObservers = nil
        }
    }


}

// MARK: - authorization / permission

extension Position {

    /// Authorization status for location services.
    public var locationServicesStatus: LocationAuthorizationStatus {
        _deviceLocationManager.locationServicesStatus
    }

    /// Request location authorization for in use always.
    public func requestAlwaysLocationAuthorization() {
        _deviceLocationManager.requestAlwaysAuthorization()
    }

    /// Request location authorization for in app use only.
    public func requestWhenInUseLocationAuthorization() {
        _deviceLocationManager.requestWhenInUseAuthorization()
    }

    @available(iOS 14, *)
    public var locationAccuracyAuthorizationStatus: LocationAccuracyAuthorizationStatus {
        _deviceLocationManager.locationAccuracyAuthorizationStatus
    }

    /// Request one time accuracy authorization. Be sure to include "FullAccuracyPurpose" to your Info.plist.
    @available(iOS 14, *)
    public func requestOneTimeFullAccuracyAuthorization(_ completionHandler: ((Bool) -> Void)? = nil) {
        _deviceLocationManager.requestAccuracyAuthorization { completed in
            completionHandler?(completed)
        }
    }

}

// MARK: - location & heading

extension Position {

    /// Triggers a single location request at a specific desired accuracy regardless of any other location tracking configuration or requests.
    ///
    /// - Parameters:
    ///   - desiredAccuracy: Minimum accuracy to meet before for request.
    ///   - completionHandler: Completion handler for when the location is determined.
    public func performOneShotLocationUpdate(withDesiredAccuracy desiredAccuracy: Double, completionHandler: Position.OneShotCompletionHandler? = nil) {
        _deviceLocationManager.performOneShotLocationUpdate(withDesiredAccuracy: desiredAccuracy, completionHandler: completionHandler)
    }

    /// Start positioning updates.
    public func startUpdating() {
        _deviceLocationManager.startUpdating()
        _updating = true
    }

    /// Stop positioning updates.
    public func stopUpdating() {
        _deviceLocationManager.stopUpdating()
        _deviceLocationManager.stopLowPowerUpdating()
        _updating = false
    }
}

// MARK: - heading

extension Position {

    /// Start heading updates.
    public func startUpdatingHeading() {
        _deviceLocationManager.startUpdatingHeading()
    }

    /// Stop heading updates.
    public func stopUpdatingHeading() {
        _deviceLocationManager.stopUpdatingHeading()
    }

}

// MARK: - private functions

extension Position {

    internal func checkAuthorizationStatusForServices() {
        if _deviceLocationManager.locationServicesStatus == .denied {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                for observer in self._observers?.allObjects as? [PositionAuthorizationObserver] ?? [] {
                    observer.position(self, didChangeLocationAuthorizationStatus: .denied)
                }
            }
        }
    }

    internal func updateLocationAccuracyIfNecessary() {
        if adjustLocationUseFromBatteryLevel == true {
            switch UIDevice.current.batteryState {
                case .full,
                     .charging:
                    _deviceLocationManager.trackingDesiredAccuracyActive = kCLLocationAccuracyNearestTenMeters
                    _deviceLocationManager.trackingDesiredAccuracyBackground = kCLLocationAccuracyHundredMeters
                    break
                case .unplugged,
                     .unknown:
                    fallthrough
                @unknown default:
                    let batteryLevel: Float = UIDevice.current.batteryLevel
                    if batteryLevel < 0.15 {
                        _deviceLocationManager.trackingDesiredAccuracyActive = kCLLocationAccuracyThreeKilometers
                        _deviceLocationManager.trackingDesiredAccuracyBackground = kCLLocationAccuracyThreeKilometers
                    } else {
                        _deviceLocationManager.trackingDesiredAccuracyActive = kCLLocationAccuracyHundredMeters
                        _deviceLocationManager.trackingDesiredAccuracyBackground = kCLLocationAccuracyKilometer
                    }
                    break
            }
        }
    }
}

// MARK: - Notifications

extension Position {

    // add / remove

    internal func addAppObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationDidBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: UIApplication.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationWillResignActive(_:)), name: UIApplication.willResignActiveNotification, object: UIApplication.shared)
    }

    internal func removeAppObservers() {
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: UIApplication.shared)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: UIApplication.shared)
    }

    internal func addBatteryObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleBatteryLevelChanged(_:)), name: UIDevice.batteryLevelDidChangeNotification, object: UIApplication.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(handleBatteryStateChanged(_:)), name: UIDevice.batteryStateDidChangeNotification, object: UIApplication.shared)
    }

    internal func removeBatteryObservers() {
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryLevelDidChangeNotification, object: UIApplication.shared)
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryStateDidChangeNotification, object: UIApplication.shared)
    }

    // handlers

    @objc
    private func handleApplicationDidBecomeActive(_ notification: Notification) {
        checkAuthorizationStatusForServices()

        // if position is not updating, don't modify state
        if _updating == false {
            return
        }

        // internally, locationManager will adjust desiredaccuracy to trackingDesiredAccuracyBackground
        if adjustLocationUseWhenBackgrounded == true {
            _deviceLocationManager.stopLowPowerUpdating()
        }
    }

    @objc
    private func handleApplicationWillResignActive(_ notification: Notification) {
        if _updating == true {
            return
        }

        if adjustLocationUseWhenBackgrounded == true {
            _deviceLocationManager.startLowPowerUpdating()
        }

        updateLocationAccuracyIfNecessary()
    }

    @objc
    private func handleBatteryLevelChanged(_ notification: Notification) {
        let batteryLevel = UIDevice.current.batteryLevel
        if batteryLevel < 0 {
            return
        }
        updateLocationAccuracyIfNecessary()
    }

    @objc
    private func handleBatteryStateChanged(_ notification: Notification) {
        updateLocationAccuracyIfNecessary()
    }

}

// MARK: - DeviceLocationManagerDelegate

extension Position: DeviceLocationManagerDelegate {

    internal func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for observer in self._observers?.allObjects as? [PositionAuthorizationObserver] ?? [] {
                observer.position(self, didChangeLocationAuthorizationStatus: status)
            }
        }
    }

    internal func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didFailWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for observer in self._observers?.allObjects as? [PositionObserver] ?? [] {
                observer.position(self, didFailWithError: error)
            }
        }
    }

    internal func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didUpdateOneShotLocation location: CLLocation?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for observer in self._observers?.allObjects as? [PositionObserver] ?? [] {
                observer.position(self, didUpdateOneShotLocation: location)
            }
        }
    }

    internal func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didUpdateTrackingLocations locations: [CLLocation]?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for observer in self._observers?.allObjects as? [PositionObserver] ?? [] {
                observer.position(self, didUpdateTrackingLocations: locations)
            }
        }
    }

    func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didUpdateHeading newHeading: CLHeading) {
       for observer in self._observers?.allObjects as? [PositionHeadingObserver] ?? [] {
            observer.position(self, didUpdateHeading: newHeading)
        }
    }

    internal func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didUpdateFloor floor: CLFloor) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for observer in self._observers?.allObjects as? [PositionObserver] ?? [] {
                observer.position(self, didUpdateFloor: floor)
            }
        }
    }

    internal func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didVisit visit: CLVisit?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let observers = self._observers?.allObjects as? [PositionObserver] {
                observers.forEach({ observer in
                    observer.position(self, didVisit: visit)
                })
            }
        }
    }

}

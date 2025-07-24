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

import Foundation
import CoreLocation
import Combine
#if canImport(UIKit)
import UIKit
#endif

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
            #if os(iOS)
            UIDevice.current.isBatteryMonitoringEnabled = self.adjustLocationUseFromBatteryLevel
            #endif
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

    internal private(set) var _authorizationObservers: NSMapTable<AnyObject, AnyObject> = NSMapTable.strongToWeakObjects()
    internal private(set) var _observers: NSMapTable<AnyObject, AnyObject> = NSMapTable.strongToWeakObjects()
    internal private(set) var _headingObservers: NSMapTable<AnyObject, AnyObject> = NSMapTable.strongToWeakObjects()

    internal private(set) var _deviceLocationManager: DeviceLocationManager = DeviceLocationManager()
    internal private(set) var _updating: Bool = false
    
    // MARK: - Combine Publishers
    
    private lazy var _locationPublisherSubject = PassthroughSubject<CLLocation, Never>()
    
    private lazy var _headingPublisherSubject = PassthroughSubject<CLHeading, Never>()
    
    private lazy var _authorizationPublisherSubject = PassthroughSubject<LocationAuthorizationStatus, Never>()
    
    /// Publisher for location updates
    @available(iOS 15.0, *)
    public var locationPublisher: AnyPublisher<CLLocation, Never> {
        _locationPublisherSubject.eraseToAnyPublisher()
    }
    
    /// Publisher for heading updates
    @available(iOS 15.0, *)
    public var headingPublisher: AnyPublisher<CLHeading, Never> {
        _headingPublisherSubject.eraseToAnyPublisher()
    }
    
    /// Publisher for authorization status changes
    @available(iOS 15.0, *)
    public var authorizationPublisher: AnyPublisher<LocationAuthorizationStatus, Never> {
        _authorizationPublisherSubject.eraseToAnyPublisher()
    }
    
    // MARK: - AsyncSequence Support
    
    /// AsyncSequence for continuous location updates
    @available(iOS 15.0, *)
    public var locationUpdates: AsyncStream<CLLocation> {
        AsyncStream { continuation in
            var cancellable: AnyCancellable?
            
            cancellable = locationPublisher
                .sink { location in
                    continuation.yield(location)
                }
            
            continuation.onTermination = { _ in
                cancellable?.cancel()
            }
        }
    }
    
    /// AsyncSequence for continuous heading updates
    @available(iOS 15.0, *)
    public var headingUpdates: AsyncStream<CLHeading> {
        AsyncStream { continuation in
            var cancellable: AnyCancellable?
            
            cancellable = headingPublisher
                .sink { heading in
                    continuation.yield(heading)
                }
            
            continuation.onTermination = { _ in
                cancellable?.cancel()
            }
        }
    }
    
    /// AsyncSequence for authorization status changes
    @available(iOS 15.0, *)
    public var authorizationUpdates: AsyncStream<LocationAuthorizationStatus> {
        AsyncStream { continuation in
            var cancellable: AnyCancellable?
            
            cancellable = authorizationPublisher
                .sink { status in
                    continuation.yield(status)
                }
            
            continuation.onTermination = { _ in
                cancellable?.cancel()
            }
        }
    }

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
        let key = ObjectIdentifier(observer)
        _authorizationObservers.setObject(observer, forKey: key as AnyObject)
    }

    /// Removes an authorization observer.
    ///
    /// - Parameter observer: Observing instance.
    public func removeAuthorizationObserver(_ observer: PositionAuthorizationObserver) {
        let key = ObjectIdentifier(observer)
        _authorizationObservers.removeObject(forKey: key as AnyObject)
    }

    /// Adds a position location observer.
    ///
    /// - Parameter observer: Observing instance.
    public func addObserver(_ observer: PositionObserver) {
        let key = ObjectIdentifier(observer)
        _observers.setObject(observer, forKey: key as AnyObject)
    }

    /// Removes a position location observer.
    ///
    /// - Parameter observer: Observing instance.
    public func removeObserver(_ observer: PositionObserver) {
        let key = ObjectIdentifier(observer)
        _observers.removeObject(forKey: key as AnyObject)
    }

    /// Adds a position heading observer.
    ///
    /// - Parameter observer: Observing instance.
    public func addHeadingObserver(_ observer: PositionHeadingObserver) {
        let key = ObjectIdentifier(observer)
        _headingObservers.setObject(observer, forKey: key as AnyObject)
    }

    /// Removes a position heading observer.
    ///
    /// - Parameter observer: Observing instance.
    public func removeHeadingObserver(_ observer: PositionHeadingObserver) {
        let key = ObjectIdentifier(observer)
        _headingObservers.removeObject(forKey: key as AnyObject)
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
    
    /// Async version that requests always authorization and waits for the result
    /// - Returns: The resulting authorization status after the request
    @available(iOS 15.0, *)
    public func requestAlwaysLocationAuthorization() async -> LocationAuthorizationStatus {
        await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            
            // Subscribe to authorization changes
            cancellable = authorizationPublisher
                .first()
                .sink { status in
                    continuation.resume(returning: status)
                    cancellable?.cancel()
                }
            
            // Request authorization
            _deviceLocationManager.requestAlwaysAuthorization()
            
            // If already authorized, return immediately
            let currentStatus = locationServicesStatus
            if currentStatus == .allowedAlways || currentStatus == .denied {
                cancellable?.cancel()
                continuation.resume(returning: currentStatus)
            }
        }
    }

    /// Request location authorization for in app use only.
    public func requestWhenInUseLocationAuthorization() {
        _deviceLocationManager.requestWhenInUseAuthorization()
    }
    
    /// Async version that requests when-in-use authorization and waits for the result
    /// - Returns: The resulting authorization status after the request
    @available(iOS 15.0, *)
    public func requestWhenInUseLocationAuthorization() async -> LocationAuthorizationStatus {
        await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            
            // Subscribe to authorization changes
            cancellable = authorizationPublisher
                .first()
                .sink { status in
                    continuation.resume(returning: status)
                    cancellable?.cancel()
                }
            
            // Request authorization
            _deviceLocationManager.requestWhenInUseAuthorization()
            
            // If already authorized, return immediately
            let currentStatus = locationServicesStatus
            if currentStatus == .allowedWhenInUse || currentStatus == .allowedAlways || currentStatus == .denied {
                cancellable?.cancel()
                continuation.resume(returning: currentStatus)
            }
        }
    }

    public var locationAccuracyAuthorizationStatus: LocationAccuracyAuthorizationStatus {
        _deviceLocationManager.locationAccuracyAuthorizationStatus
    }

    /// Request one time accuracy authorization. Be sure to include "FullAccuracyPurpose" to your Info.plist.
    public func requestOneTimeFullAccuracyAuthorization(_ completionHandler: ((Bool) -> Void)? = nil) {
        _deviceLocationManager.requestAccuracyAuthorization { completed in
            completionHandler?(completed)
        }
    }
    
    /// Async version of requestOneTimeFullAccuracyAuthorization
    /// - Returns: true if full accuracy was granted, false otherwise
    @available(iOS 15.0, *)
    public func requestOneTimeFullAccuracyAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            requestOneTimeFullAccuracyAuthorization { completed in
                continuation.resume(returning: completed)
            }
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
    
    /// Async version of performOneShotLocationUpdate
    ///
    /// - Parameter desiredAccuracy: Minimum accuracy to meet before for request.
    /// - Returns: The location if successful
    /// - Throws: Position.ErrorType if the request fails
    @available(iOS 15.0, *)
    public func performOneShotLocationUpdate(withDesiredAccuracy desiredAccuracy: Double) async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            performOneShotLocationUpdate(withDesiredAccuracy: desiredAccuracy) { result in
                switch result {
                case .success(let location):
                    continuation.resume(returning: location)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
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
    
    private func getObservers<T>() -> [T] {
        var observers: [T] = []
        if let enumerator = _observers.objectEnumerator() {
            while let observer = enumerator.nextObject() as? T {
                observers.append(observer)
            }
        }
        return observers
    }
    
    private func getHeadingObservers<T>() -> [T] {
        var observers: [T] = []
        if let enumerator = _headingObservers.objectEnumerator() {
            while let observer = enumerator.nextObject() as? T {
                observers.append(observer)
            }
        }
        return observers
    }

    internal func checkAuthorizationStatusForServices() {
        if _deviceLocationManager.locationServicesStatus == .denied {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                for observer in self.getObservers() as [PositionAuthorizationObserver] {
                    observer.position(self, didChangeLocationAuthorizationStatus: .denied)
                }
            }
        }
    }

    internal func updateLocationAccuracyIfNecessary() {
        if adjustLocationUseFromBatteryLevel == true {
            #if os(iOS)
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
            #endif
        }
    }
}

// MARK: - Notifications

extension Position {

    // add / remove

    internal func addAppObservers() {
        #if os(iOS)
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationDidBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: UIApplication.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationWillResignActive(_:)), name: UIApplication.willResignActiveNotification, object: UIApplication.shared)
        #endif
    }

    internal func removeAppObservers() {
        #if os(iOS)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: UIApplication.shared)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: UIApplication.shared)
        #endif
    }

    internal func addBatteryObservers() {
        #if os(iOS)
        NotificationCenter.default.addObserver(self, selector: #selector(handleBatteryLevelChanged(_:)), name: UIDevice.batteryLevelDidChangeNotification, object: UIApplication.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(handleBatteryStateChanged(_:)), name: UIDevice.batteryStateDidChangeNotification, object: UIApplication.shared)
        #endif
    }

    internal func removeBatteryObservers() {
        #if os(iOS)
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryLevelDidChangeNotification, object: UIApplication.shared)
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryStateDidChangeNotification, object: UIApplication.shared)
        #endif
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
        #if os(iOS)
        let batteryLevel = UIDevice.current.batteryLevel
        if batteryLevel < 0 {
            return
        }
        updateLocationAccuracyIfNecessary()
        #endif
    }

    @objc
    private func handleBatteryStateChanged(_ notification: Notification) {
        #if os(iOS)
        updateLocationAccuracyIfNecessary()
        #endif
    }

}

// MARK: - DeviceLocationManagerDelegate

extension Position: DeviceLocationManagerDelegate {

    internal func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for observer in self.getObservers() as [PositionAuthorizationObserver] {
                observer.position(self, didChangeLocationAuthorizationStatus: status)
            }
            if #available(iOS 15.0, *) {
                self._authorizationPublisherSubject.send(status)
            }
        }
    }

    internal func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didFailWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for observer in self.getObservers() as [PositionObserver] {
                observer.position(self, didFailWithError: error)
            }
        }
    }

    internal func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didUpdateOneShotLocation location: CLLocation?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for observer in self.getObservers() as [PositionObserver] {
                observer.position(self, didUpdateOneShotLocation: location)
            }
        }
    }

    internal func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didUpdateTrackingLocations locations: [CLLocation]?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for observer in self.getObservers() as [PositionObserver] {
                observer.position(self, didUpdateTrackingLocations: locations)
            }
            if #available(iOS 15.0, *), let location = locations?.first {
                self._locationPublisherSubject.send(location)
            }
        }
    }

    func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didUpdateHeading newHeading: CLHeading) {
       for observer in self.getHeadingObservers() as [PositionHeadingObserver] {
            observer.position(self, didUpdateHeading: newHeading)
        }
        if #available(iOS 15.0, *) {
            _headingPublisherSubject.send(newHeading)
        }
    }

    internal func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didUpdateFloor floor: CLFloor) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for observer in self.getObservers() as [PositionObserver] {
                observer.position(self, didUpdateFloor: floor)
            }
        }
    }

    internal func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didVisit visit: CLVisit?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let observers = self.getObservers() as [PositionObserver]
            observers.forEach({ observer in
                observer.position(self, didVisit: visit)
            })
        }
    }

}

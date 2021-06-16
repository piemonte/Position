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

/// Possible error types
public enum PositionErrorType: Error, CustomStringConvertible {
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

/// Position location authorization protocol.
public protocol PositionAuthorizationObserver: AnyObject {
    /// Permission change authorization status, this may be triggered on application resume if the app settings have changed
    func position(_ position: Position, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus)
}

/// Position location updates protocol.
public protocol PositionObserver: AnyObject {

    /// Location positioning one-shot updates
    func position(_ position: Position, didUpdateOneShotLocation location: CLLocation?)

    /// Location positioning tracking updates
    func position(_ position: Position, didUpdateTrackingLocations locations: [CLLocation]?)
    func position(_ position: Position, didUpdateFloor floor: CLFloor)
    func position(_ position: Position, didVisit visit: CLVisit?)

    /// Location accuracy updates
    func position(_ position: Position, didChangeDesiredAccurary desiredAccuracy: Double)

    /// Error handling
    func position(_ position: Position, didFailWithError error: Error?)

}

/// 🛰 Position, Swift and efficient location positioning.
open class Position {

    // MARK: - types

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
            _positionLocationManager.distanceFilter
        }
        set {
            _positionLocationManager.distanceFilter = newValue
        }
    }

    /// Time that must pass for a device before updating location.
    public var timeFilter: TimeInterval {
        get {
            _positionLocationManager.timeFilter
        }
        set {
            _positionLocationManager.timeFilter = newValue
        }
    }

    /// When `true`, location will reduce power usage from adjusted accuracy when backgrounded.
    public var adjustLocationUseWhenBackgrounded: Bool = false {
        didSet {
            if _positionLocationManager.isUpdatingLowPowerLocation == true {
                _positionLocationManager.stopLowPowerUpdating()
                _positionLocationManager.startUpdating()
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
            _positionLocationManager.trackingDesiredAccuracyActive
        }
        set {
            _positionLocationManager.trackingDesiredAccuracyActive = newValue
        }
    }

    /// Location tracking desired accuracy when the app is in the background.
    public var trackingDesiredAccuracyWhenInBackground: Double {
        get {
            _positionLocationManager.trackingDesiredAccuracyBackground
        }
        set {
            _positionLocationManager.trackingDesiredAccuracyBackground = newValue
        }
    }

    /// `true` when location services are updating
    public var isUpdatingLocation: Bool {
        _positionLocationManager.isUpdatingLocation == true || self._positionLocationManager.isUpdatingLowPowerLocation == true
    }

    /// Last determined location
    public var location: CLLocation? {
        _positionLocationManager.location
    }

    // MARK: - ivars

    internal private(set) var _authorizationObservers: NSHashTable<AnyObject>?
    internal private(set) var _observers: NSHashTable<AnyObject>?

    internal private(set) var _positionLocationManager: PositionLocationManager = PositionLocationManager()
    internal private(set) var _updating: Bool = false

    // MARK: - object lifecycle

    public init() {
        self._positionLocationManager.delegate = self

        self.addBatteryObservers()
        self.addAppObservers()
    }

    deinit {
        self.removeAppObservers()
        self.removeBatteryObservers()
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

    /// Adds a position observer.
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

    /// Removes a position observer.
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

}

// MARK: - authorization / permission

extension Position {

    /// Authorization status for location services.
    public var locationServicesStatus: LocationAuthorizationStatus {
        _positionLocationManager.locationServicesStatus
    }

    /// Request location authorization for in use always.
    public func requestAlwaysLocationAuthorization() {
        _positionLocationManager.requestAlwaysAuthorization()
    }

    /// Request location authorization for in app use only.
    public func requestWhenInUseLocationAuthorization() {
        _positionLocationManager.requestWhenInUseAuthorization()
    }

}

// MARK: - location

extension Position {

    /// Triggers a single location request at a specific desired accuracy regardless of any other location tracking configuration or requests.
    ///
    /// - Parameters:
    ///   - desiredAccuracy: Minimum accuracy to meet before for request.
    ///   - completionHandler: Completion handler for when the location is determined.
    public func performOneShotLocationUpdate(withDesiredAccuracy desiredAccuracy: Double, completionHandler: Position.OneShotCompletionHandler? = nil) {
        _positionLocationManager.performOneShotLocationUpdate(withDesiredAccuracy: desiredAccuracy, completionHandler: completionHandler)
    }

    /// Start positioning updates.
    public func startUpdating() {
        _positionLocationManager.startUpdating()
        _updating = true
    }

    /// Stop positioning updates.
    public func stopUpdating() {
        _positionLocationManager.stopUpdating()
        _positionLocationManager.stopLowPowerUpdating()
        _updating = false
    }
}

// MARK: - private functions

extension Position {

    internal func checkAuthorizationStatusForServices() {
        if self._positionLocationManager.locationServicesStatus == .denied {
            DispatchQueue.main.async {
                for observer in self._observers?.allObjects as? [PositionAuthorizationObserver] ?? [] {
                    observer.position(self, didChangeLocationAuthorizationStatus: .denied)
                }
            }
        }
    }

    internal func updateLocationAccuracyIfNecessary() {
        if self.adjustLocationUseFromBatteryLevel == true {
            switch UIDevice.current.batteryState {
                case .full,
                     .charging:
                    _positionLocationManager.trackingDesiredAccuracyActive = kCLLocationAccuracyNearestTenMeters
                    _positionLocationManager.trackingDesiredAccuracyBackground = kCLLocationAccuracyHundredMeters
                    break
                case .unplugged,
                     .unknown:
                    fallthrough
                @unknown default:
                    let batteryLevel: Float = UIDevice.current.batteryLevel
                    if batteryLevel < 0.15 {
                        _positionLocationManager.trackingDesiredAccuracyActive = kCLLocationAccuracyThreeKilometers
                        _positionLocationManager.trackingDesiredAccuracyBackground = kCLLocationAccuracyThreeKilometers
                    } else {
                        _positionLocationManager.trackingDesiredAccuracyActive = kCLLocationAccuracyHundredMeters
                        _positionLocationManager.trackingDesiredAccuracyBackground = kCLLocationAccuracyKilometer
                    }
                    break
            }
        }
    }
}

// MARK: - NSNotifications

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
            _positionLocationManager.stopLowPowerUpdating()
        }
    }

    @objc
    private func handleApplicationWillResignActive(_ notification: Notification) {
        if _updating == true {
            return
        }

        if adjustLocationUseWhenBackgrounded == true {
            _positionLocationManager.startLowPowerUpdating()
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

// MARK: - PositionLocationManagerDelegate

extension Position: PositionLocationManagerDelegate {

    internal func positionLocationManager(_ positionLocationManager: PositionLocationManager, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus) {
        DispatchQueue.main.async {
            for observer in self._observers?.allObjects as? [PositionAuthorizationObserver] ?? [] {
                observer.position(self, didChangeLocationAuthorizationStatus: status)
            }
        }
    }

    internal func positionLocationManager(_ positionLocationManager: PositionLocationManager, didFailWithError error: Error?) {
        DispatchQueue.main.async {
            for observer in self._observers?.allObjects as? [PositionObserver] ?? [] {
                observer.position(self, didFailWithError: error)
            }
        }
    }

    internal func positionLocationManager(_ positionLocationManager: PositionLocationManager, didUpdateOneShotLocation location: CLLocation?) {
        DispatchQueue.main.async {
            for observer in self._observers?.allObjects as? [PositionObserver] ?? [] {
                observer.position(self, didUpdateOneShotLocation: location)
            }
        }
    }

    internal func positionLocationManager(_ positionLocationManager: PositionLocationManager, didUpdateTrackingLocations locations: [CLLocation]?) {
        DispatchQueue.main.async {
            for observer in self._observers?.allObjects as? [PositionObserver] ?? [] {
                observer.position(self, didUpdateTrackingLocations: locations)
            }
        }
    }

    internal func positionLocationManager(_ positionLocationManager: PositionLocationManager, didUpdateFloor floor: CLFloor) {
        DispatchQueue.main.async {
            for observer in self._observers?.allObjects as? [PositionObserver] ?? [] {
                observer.position(self, didUpdateFloor: floor)
            }
        }
    }

    internal func positionLocationManager(_ positionLocationManager: PositionLocationManager, didVisit visit: CLVisit?) {
        DispatchQueue.main.async {
            if let observers = self._observers?.allObjects as? [PositionObserver] {
                observers.forEach({ observer in
                    observer.position(self, didVisit: visit)
                })
            }
        }
    }

}

// MARK: -
// MARK: - Internal

// MARK: - PositionLocationManagerDelegate

internal protocol PositionLocationManagerDelegate: AnyObject {
    func positionLocationManager(_ positionLocationManager: PositionLocationManager, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus)
    func positionLocationManager(_ positionLocationManager: PositionLocationManager, didFailWithError error: Error?)

    func positionLocationManager(_ positionLocationManager: PositionLocationManager, didUpdateOneShotLocation location: CLLocation?)
    func positionLocationManager(_ positionLocationManager: PositionLocationManager, didUpdateTrackingLocations location: [CLLocation]?)
    func positionLocationManager(_ positionLocationManager: PositionLocationManager, didUpdateFloor floor: CLFloor)
    func positionLocationManager(_ positionLocationManager: PositionLocationManager, didVisit visit: CLVisit?)
}

// MARK: - PositionLocationManager

internal class PositionLocationManager: NSObject {

    // MARK: - types

    internal static let OneShotRequestDefaultTimeOut: TimeInterval = 0.5 * 60.0
    internal static let RequestQueueSpecificKey = DispatchSpecificKey<()>()

    // MARK: - properties

    internal weak var delegate: PositionLocationManagerDelegate?

    internal var distanceFilter: Double = 0.0 {
        didSet {
            updateLocationManagerStateIfNeeded()
        }
    }

    internal var timeFilter: TimeInterval = 0.0

    internal var trackingDesiredAccuracyActive: Double = kCLLocationAccuracyHundredMeters {
        didSet {
            updateLocationManagerStateIfNeeded()
        }
    }

    internal var trackingDesiredAccuracyBackground: Double = kCLLocationAccuracyKilometer {
        didSet {
            updateLocationManagerStateIfNeeded()
        }
    }

    internal var location: CLLocation? {
        _locationManager.location
    }

    internal var isUpdatingLocation: Bool = false
    internal var isUpdatingLowPowerLocation: Bool = false

    // MARK: - ivars

    internal var _locationManager: CLLocationManager = CLLocationManager()
    internal var _locationRequests: [PositionLocationRequest] = []
    internal var _requestQueue: DispatchQueue
    internal var _locations: [CLLocation]?

    // MARK: - object lifecycle

    override public init() {
        self._requestQueue = DispatchQueue(label: "PositionLocationManagerRequestQueue", autoreleaseFrequency: .workItem, target: DispatchQueue.global())
        self._requestQueue.setSpecific(key: PositionLocationManager.RequestQueueSpecificKey, value: ())

        super.init()

        self._locationManager.delegate = self
        self._locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self._locationManager.pausesLocationUpdatesAutomatically = false
        if #available(iOSApplicationExtension 9.0, *) {
            if CLLocationManager.backgroundCapabilitiesEnabled {
                self._locationManager.allowsBackgroundLocationUpdates = true
            }
        }
    }
}

// MARK: - permissions

extension PositionLocationManager {

    internal var locationServicesStatus: LocationAuthorizationStatus {
        get {
            guard CLLocationManager.locationServicesEnabled() == true else {
                return .notAvailable
            }

            if #available(iOS 14.0, *) {
                switch _locationManager.authorizationStatus {
                    case .authorizedAlways:
                        return .allowedAlways
                    case .authorizedWhenInUse:
                        return .allowedWhenInUse
                    case .denied, .restricted:
                        return .denied
                    case .notDetermined:
                        fallthrough
                    @unknown default:
                        return .notDetermined
                }
            } else {
                switch CLLocationManager.authorizationStatus() {
                    case .authorizedAlways:
                        return .allowedAlways
                    case .authorizedWhenInUse:
                        return .allowedWhenInUse
                    case .denied, .restricted:
                        return .denied
                    case .notDetermined:
                        fallthrough
                    @unknown default:
                        return .notDetermined
                }
            }
        }
    }

        }
    }

    internal func requestAlwaysAuthorization() {
        _locationManager.requestAlwaysAuthorization()
    }

    internal func requestWhenInUseAuthorization() {
        _locationManager.requestWhenInUseAuthorization()
    }

    }

}

// MARK: - location services

extension PositionLocationManager {

    internal func performOneShotLocationUpdate(withDesiredAccuracy desiredAccuracy: Double, completionHandler: Position.OneShotCompletionHandler? = nil) {
        if self.locationServicesStatus == .allowedAlways ||
            self.locationServicesStatus == .allowedWhenInUse {

            self.executeClosureAsyncOnRequestQueueIfNecessary {
                let request = PositionLocationRequest()
                request.desiredAccuracy = desiredAccuracy
                request.lifespan = PositionLocationManager.OneShotRequestDefaultTimeOut
                request.timeOutHandler = {
                    self.processLocationRequests()
                }
                request.completionHandler = completionHandler

                self._locationRequests.append(request)

                self.startLowPowerUpdating()
                self._locationManager.desiredAccuracy = kCLLocationAccuracyBest
                self._locationManager.distanceFilter = kCLDistanceFilterNone

                // activate location to process request
                if self.isUpdatingLocation == false {
                    self.startUpdating()
                    // flag signals to turn off updating once complete
                    self.isUpdatingLocation = false
                }
            }

        } else {
            DispatchQueue.main.async {
                completionHandler?(.failure(PositionErrorType.restricted))
            }
        }
    }

    internal func startUpdating() {
        switch self.locationServicesStatus {
            case .allowedAlways,
                 .allowedWhenInUse:
                _locationManager.startUpdatingLocation()
                _locationManager.startMonitoringVisits()
                isUpdatingLocation = true
                updateLocationManagerStateIfNeeded()
                fallthrough
            default:
                break
        }
    }

    internal func stopUpdating() {
        switch self.locationServicesStatus {
            case .allowedAlways,
                 .allowedWhenInUse:
                if self.isUpdatingLocation == true {
                    _locationManager.stopUpdatingLocation()
                    _locationManager.stopMonitoringVisits()
                    isUpdatingLocation = false
                    updateLocationManagerStateIfNeeded()
                }
                fallthrough
            default:
                break
        }
    }

    internal func startLowPowerUpdating() {
        let status: LocationAuthorizationStatus = self.locationServicesStatus
        switch status {
            case .allowedAlways, .allowedWhenInUse:
                _locationManager.startMonitoringSignificantLocationChanges()
                isUpdatingLowPowerLocation = true
                updateLocationManagerStateIfNeeded()
                fallthrough
            default:
                break
        }
    }

    internal func stopLowPowerUpdating() {
        let status: LocationAuthorizationStatus = self.locationServicesStatus
        switch status {
            case .allowedAlways, .allowedWhenInUse:
                _locationManager.stopMonitoringSignificantLocationChanges()
                isUpdatingLowPowerLocation = false
                updateLocationManagerStateIfNeeded()
                fallthrough
            default:
                break
        }
    }

}

// MARK: - private methods

extension PositionLocationManager {

    // only called from the request queue
    internal func processLocationRequests() {
        guard self._locationRequests.count > 0 else {
            DispatchQueue.main.async {
                self.delegate?.positionLocationManager(self, didUpdateTrackingLocations: self._locations)
            }
            return
        }

        let completeRequests: [PositionLocationRequest] = self._locationRequests.filter { request -> Bool in
            // check if a request completed, meaning expired or met horizontal accuracy
            // print("desiredAccuracy \(request.desiredAccuracy) horizontal \(self.location?.horizontalAccuracy)")
            if let location = self._locations?.first {
                guard request.isExpired == true || location.horizontalAccuracy < request.desiredAccuracy else {
                    return false
                }
                return true
            }
            return false
        }

        for request in completeRequests {
            guard request.isCompleted == false else {
                continue
            }
            request.isCompleted = true
            if request.isExpired {
                self.executeClosureSyncOnMainQueueIfNecessary {
                    request.completionHandler?(.failure(PositionErrorType.timedOut))
                }
            } else {
                if let location = self._locations?.first {
                    self.executeClosureSyncOnMainQueueIfNecessary {
                        request.completionHandler?(.success(location))
                    }
                } else {
                    self.executeClosureSyncOnMainQueueIfNecessary {
                        request.completionHandler?(.failure(PositionErrorType.timedOut))
                    }
                }
            }
        }

        let pendingRequests: [PositionLocationRequest] = _locationRequests.filter { request -> Bool in
            request.isCompleted == false
        }
        _locationRequests = pendingRequests

        if _locationRequests.count == 0 {
            self.updateLocationManagerStateIfNeeded()

            if isUpdatingLocation == false {
                stopUpdating()
            }

            if isUpdatingLowPowerLocation == false {
                stopLowPowerUpdating()
            }
        }
    }

    internal func completeLocationRequests(withError error: Error?) {
        for locationRequest in _locationRequests {
            locationRequest.cancelRequest()
            guard let handler = locationRequest.completionHandler else {
                continue
            }

            self.executeClosureSyncOnMainQueueIfNecessary {
                handler(.failure(error ?? PositionErrorType.cancelled))
            }
        }
    }

    internal func updateLocationManagerStateIfNeeded() {
        // when not processing requests, set desired accuracy appropriately
        if self._locationRequests.count > 0 {
            if self.isUpdatingLocation == true {
                self._locationManager.desiredAccuracy = self.trackingDesiredAccuracyActive
            } else if self.isUpdatingLowPowerLocation == true {
                self._locationManager.desiredAccuracy = self.trackingDesiredAccuracyBackground
            }

            self._locationManager.distanceFilter = self.distanceFilter
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension PositionLocationManager: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.executeClosureAsyncOnRequestQueueIfNecessary {
            // update last location
            self._locations = locations
            // update one-shot requests
            self.processLocationRequests()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.executeClosureAsyncOnRequestQueueIfNecessary {
            self.completeLocationRequests(withError: error)
            DispatchQueue.main.async {
                self.delegate?.positionLocationManager(self, didFailWithError: error)
            }
        }
    }

    @available(iOS 14, *)
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.executeClosureAsyncOnRequestQueueIfNecessary {
            switch manager.authorizationStatus {
            case .denied, .restricted:
                self.completeLocationRequests(withError: PositionErrorType.restricted)
            default: break
            }
            DispatchQueue.main.async {
                self.delegate?.positionLocationManager(self, didChangeLocationAuthorizationStatus: self.locationServicesStatus)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        self.executeClosureAsyncOnRequestQueueIfNecessary {
            switch status {
            case .denied, .restricted:
                self.completeLocationRequests(withError: PositionErrorType.restricted)
            default: break
            }
            DispatchQueue.main.async {
                self.delegate?.positionLocationManager(self, didChangeLocationAuthorizationStatus: self.locationServicesStatus)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        delegate?.positionLocationManager(self, didVisit: visit)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    }

    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        delegate?.positionLocationManager(self, didFailWithError: error)
    }

}

// MARK: - queues

extension PositionLocationManager {

    internal func executeClosureSyncOnMainQueueIfNecessary(withClosure closure: @escaping () -> Void) {
        if Thread.isMainThread {
            closure()
        } else {
            DispatchQueue.main.sync(execute: closure)
        }
    }

    internal func executeClosureAsyncOnRequestQueueIfNecessary(withClosure closure: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: PositionLocationManager.RequestQueueSpecificKey) != nil {
            closure()
        } else {
            self._requestQueue.async(execute: closure)
        }
    }

}

// MARK: - PositionLocationRequest

internal class PositionLocationRequest {

    // MARK: - types

    internal typealias TimeOutCompletionHandler = () -> Void

    // MARK: - properties

    internal var desiredAccuracy: Double = kCLLocationAccuracyBest
    internal var lifespan: TimeInterval = PositionLocationManager.OneShotRequestDefaultTimeOut {
        didSet {
            isExpired = false
            _expirationTimer?.invalidate()
            _expirationTimer = Timer.scheduledTimer(timeInterval: self.lifespan,
                                                    target: self,
                                                    selector: #selector(handleTimerFired(_:)),
                                                    userInfo: nil,
                                                    repeats: false)
        }
    }
    internal var isCompleted: Bool = false
    internal var isExpired: Bool = false

    internal var timeOutHandler: TimeOutCompletionHandler?
    internal var completionHandler: Position.OneShotCompletionHandler?

    // MARK: - ivars

    internal var _expirationTimer: Timer?

    // MARK: - object lifecycle

    deinit {
        isExpired = true
        _expirationTimer?.invalidate()
        _expirationTimer = nil

        timeOutHandler = nil
        completionHandler = nil
    }

    // MARK: - funcs

    internal func cancelRequest() {
        isExpired = true
        _expirationTimer?.invalidate()
        _expirationTimer = nil

        timeOutHandler = nil
        // Note: completion handler will be processed on the request process loop
    }
}

// MARK: - Timer

extension PositionLocationRequest {

    @objc
    internal func handleTimerFired(_ timer: Timer) {
        DispatchQueue.main.async {
            self.isExpired = true
            self._expirationTimer?.invalidate()
            self._expirationTimer = nil

            if let timeOutHandler = self.timeOutHandler {
                timeOutHandler()
            }
            self.timeOutHandler = nil
        }
    }

}

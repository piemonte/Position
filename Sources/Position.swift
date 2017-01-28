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

/// Completion handler for one-shot location requests
public typealias OneShotCompletionHandler = (_: CLLocation?, _: Error?) -> ()

/// Time based filter constant
public let TimeFilterNone: TimeInterval = 0.0
/// Time based filter constant
public let TimeFilter5Minutes: TimeInterval = 5.0 * 60.0
/// Time based filter constant
public let TimeFilter10Minutes: TimeInterval = 10.0 * 60.0

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

/// Position error domain
public let ErrorDomain = "PositionErrorDomain"

/// Possible error types
public enum ErrorType: Int, CustomStringConvertible {
    case timedOut = 0
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

/// Position observer protocol.
public protocol PositionObserver: NSObjectProtocol {
    /// Permission change authorization status, this may be triggered on application resume if the app settings have changed
    func position(_ position: Position, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus)
    
    /// Location positioning updates
    func position(_ position: Position, didUpdateOneShotLocation location: CLLocation?)
    func position(_ position: Position, didUpdateTrackingLocations locations: [CLLocation]?)
    func position(_ position: Position, didUpdateFloor floor: CLFloor)
    func position(_ position: Position, didVisit visit: CLVisit?)
    
    /// Location accuracy updates
    func position(_ position: Position, didChangeDesiredAccurary desiredAccuracy: Double)

    /// Error handling
    func position(_ position: Position, didFailWithError error: Error?)
}

/// 🛰 Position, Swift and efficient location positioning.
public class Position: NSObject {
    
    // MARK: - properties
    
    /// Distance in meters a device must move before updating location.
    public var distanceFilter: Double {
        get {
            return self._positionLocationManager.distanceFilter
        }
        set {
            self._positionLocationManager.distanceFilter = newValue
        }
    }
    
    /// Time that must pass for a device before updating location.
    public var timeFilter: TimeInterval {
        get {
            return self._positionLocationManager.timeFilter
        }
        set {
            self._positionLocationManager.timeFilter = newValue
        }
    }
    
    /// When `true`, location will reduce power usage from adjusted accuracy when backgrounded.
    public var adjustLocationUseWhenBackgrounded: Bool {
        didSet {
            if self._positionLocationManager.updatingLowPowerLocation == true {
                self._positionLocationManager.stopLowPowerUpdating()
                self._positionLocationManager.startUpdating()
            }
        }
    }
    
    /// When `true`, location will reduce power usage from adjusted accuracy based on the current battery level.
    public var adjustLocationUseFromBatteryLevel: Bool {
        didSet {
            UIDevice.current.isBatteryMonitoringEnabled = self.adjustLocationUseFromBatteryLevel
        }
    }
    
    /// Location tracking desired accuracy when the app is active.
    public var trackingDesiredAccuracyWhenActive: Double {
        get {
            return self._positionLocationManager.trackingDesiredAccuracyActive
        }
        set {
            self._positionLocationManager.trackingDesiredAccuracyActive = newValue
        }
    }
    
    /// Location tracking desired accuracy when the app is in the background.
    public var trackingDesiredAccuracyWhenInBackground: Double {
        get {
            return self._positionLocationManager.trackingDesiredAccuracyBackground
        }
        set {
            self._positionLocationManager.trackingDesiredAccuracyBackground = newValue
        }
    }
    
    // MARK: - ivars
    
    internal var _observers: NSHashTable<AnyObject>?
    internal var _positionLocationManager: PositionLocationManager
    internal var _updating: Bool
    
    // MARK: - singleton
    
    /// Shared singleton
    static let shared = Position()

    // MARK: - object lifecycle
    
    override init() {
        self.adjustLocationUseWhenBackgrounded = false
        self.adjustLocationUseFromBatteryLevel = false
        self._positionLocationManager = PositionLocationManager()
        self._updating = false
        super.init()
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
    
    /// Adds a position observer.
    ///
    /// - Parameter observer: Observing instance.
    public func addObserver(_ observer: PositionObserver?) {
        if self._observers == nil {
            self._observers = NSHashTable(options: .strongMemory)
        }
        
        if self._observers?.contains(observer) == false {
            self._observers?.add(observer)
        }
    }
    
    /// Removes a position observer.
    ///
    /// - Parameter observer: Observing instance.
    public func removeObserver(_ observer: PositionObserver?) {
        if self._observers?.contains(observer) == true {
            self._observers?.remove(observer)
        }
        if self._observers?.count == 0 {
            self._observers = nil
        }
    }
    
}

// MARK: - permissions and access

extension Position {

    /// Authorization status for location services.
    public var locationServicesStatus: LocationAuthorizationStatus {
        get {
            return self._positionLocationManager.locationServicesStatus
        }
    }
    
    /// Request location authorization for in use always.
    public func requestAlwaysLocationAuthorization() {
        self._positionLocationManager.requestAlwaysAuthorization()
    }

    /// Request location authorization for in app use only.
    public func requestWhenInUseLocationAuthorization() {
        self._positionLocationManager.requestWhenInUseAuthorization()
    }
    
}

// MARK: - location

extension Position {
    
    /// Last determined location
    public var location: CLLocation? {
        get {
            return self._positionLocationManager.locations?.first
        }
    }
    
    /// `true` when location services are updating
    public var updatingLocation: Bool {
        get {
            return self._positionLocationManager.updatingLocation == true || self._positionLocationManager.updatingLowPowerLocation == true
        }
    }
    
    /// Triggers a single location request at a specific desired accuracy regardless of any other location tracking configuration or requests.
    ///
    /// - Parameters:
    ///   - desiredAccuracy: Minimum accuracy to meet before for request.
    ///   - completionHandler: Completion handler for when the location is determined.
    public func performOneShotLocationUpdate(withDesiredAccuracy desiredAccuracy: Double, completionHandler: @escaping OneShotCompletionHandler) {
        self._positionLocationManager.performOneShotLocationUpdate(withDesiredAccuracy: desiredAccuracy, completionHandler: completionHandler)
    }

    /// Start positioning updates.
    public func startUpdating() {
        self._positionLocationManager.startUpdating()
        self._updating = true
    }

    /// Stop positioning updates.
    public func stopUpdating() {
        self._positionLocationManager.stopUpdating()
        self._positionLocationManager.stopLowPowerUpdating()
        self._updating = false
    }
}

// MARK: - private functions

extension Position {
    
    internal func checkAuthorizationStatusForServices() {
        if self._positionLocationManager.locationServicesStatus == .denied {
            let enumerator = self._observers?.objectEnumerator()
            while let observer = enumerator?.nextObject() as? PositionObserver {
                observer.position(self, didChangeLocationAuthorizationStatus: .denied)
            }
        }
    }
    
    internal func updateLocationAccuracyIfNecessary() {
        if self.adjustLocationUseFromBatteryLevel == true {
            switch UIDevice.current.batteryState {
                case .full,
                     .charging:
                    self._positionLocationManager.trackingDesiredAccuracyActive = kCLLocationAccuracyNearestTenMeters
                    self._positionLocationManager.trackingDesiredAccuracyBackground = kCLLocationAccuracyHundredMeters
                    break
                case .unplugged,
                     .unknown:
                    let batteryLevel: Float = UIDevice.current.batteryLevel
                    if batteryLevel < 0.15 {
                        self._positionLocationManager.trackingDesiredAccuracyActive = kCLLocationAccuracyThreeKilometers
                        self._positionLocationManager.trackingDesiredAccuracyBackground = kCLLocationAccuracyThreeKilometers
                    } else {
                        self._positionLocationManager.trackingDesiredAccuracyActive = kCLLocationAccuracyHundredMeters
                        self._positionLocationManager.trackingDesiredAccuracyBackground = kCLLocationAccuracyKilometer
                    }
                    break
            }
        }
    }
}

// MARK: - NSNotifications

extension Position {
    
    // application
    
    internal func addAppObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationDidBecomeActive(_:)), name: NSNotification.Name.UIApplicationDidBecomeActive, object: UIApplication.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationWillResignActive(_:)), name: NSNotification.Name.UIApplicationWillResignActive, object: UIApplication.shared)
    }
    
    internal func removeAppObservers() {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIApplicationDidBecomeActive, object: UIApplication.shared)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIApplicationWillResignActive, object: UIApplication.shared)
    }
    
    internal func addBatteryObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleBatteryLevelChanged(_:)), name:NSNotification.Name.UIDeviceBatteryLevelDidChange, object: UIApplication.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(handleBatteryStateChanged(_:)), name:NSNotification.Name.UIDeviceBatteryStateDidChange, object: UIApplication.shared)
    }
    
    internal func removeBatteryObservers() {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIDeviceBatteryLevelDidChange, object: UIApplication.shared)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIDeviceBatteryStateDidChange, object: UIApplication.shared)
    }
    
    internal func handleApplicationDidBecomeActive(_ notification: Notification) {
        self.checkAuthorizationStatusForServices()
        
        // if position is not updating, don't modify state
        if self._updating == false {
            return
        }
        
        // internally, locationManager will adjust desiredaccuracy to trackingDesiredAccuracyBackground
        if self.adjustLocationUseWhenBackgrounded == true {
            self._positionLocationManager.stopLowPowerUpdating()
        }        
    }

    internal func handleApplicationWillResignActive(_ notification: Notification) {
        if self._updating == true {
            return
        }

        if self.adjustLocationUseWhenBackgrounded == true {
            self._positionLocationManager.startLowPowerUpdating()
        }
        
        self.updateLocationAccuracyIfNecessary()
    }

    internal func handleBatteryLevelChanged(_ notification: Notification) {
        let batteryLevel = UIDevice.current.batteryLevel
        if batteryLevel < 0 {
            return
        }
        self.updateLocationAccuracyIfNecessary()
    }

    internal func handleBatteryStateChanged(_ notification: Notification) {
        self.updateLocationAccuracyIfNecessary()
    }
    
}

// MARK: - PositionLocationManagerDelegate

extension Position: PositionLocationManagerDelegate {

    internal func positionLocationManager(_ positionLocationManager: PositionLocationManager, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus) {
        let enumerator = self._observers?.objectEnumerator()
        while let observer = enumerator?.nextObject() as? PositionObserver {
            observer.position(self, didChangeLocationAuthorizationStatus: status)
        }
    }
    
    internal func positionLocationManager(_ positionLocationManager: PositionLocationManager, didFailWithError error: Error?) {
        let enumerator = self._observers?.objectEnumerator()
        while let observer = enumerator?.nextObject() as? PositionObserver {
            observer.position(self, didFailWithError : error)
        }
    }
    
    internal func positionLocationManager(_ positionLocationManager: PositionLocationManager, didUpdateOneShotLocation location: CLLocation?) {
        let enumerator = self._observers?.objectEnumerator()
        while let observer = enumerator?.nextObject() as? PositionObserver {
            observer.position(self, didUpdateOneShotLocation: location)
        }
    }
    
    internal func positionLocationManager(_ positionLocationManager: PositionLocationManager, didUpdateTrackingLocations locations: [CLLocation]?) {
        let enumerator = self._observers?.objectEnumerator()
        while let observer = enumerator?.nextObject() as? PositionObserver {
            observer.position(self, didUpdateTrackingLocations: locations)
        }
    }
    
    internal func positionLocationManager(_ positionLocationManager: PositionLocationManager, didUpdateFloor floor: CLFloor) {
        let enumerator = self._observers?.objectEnumerator()
        while let observer = enumerator?.nextObject() as? PositionObserver {
            observer.position(self, didUpdateFloor: floor)
        }
    }

    internal func positionLocationManager(_ positionLocationManager: PositionLocationManager, didVisit visit: CLVisit?) {
        let enumerator = self._observers?.objectEnumerator()
        while let observer = enumerator?.nextObject() as? PositionObserver {
            observer.position(self, didVisit: visit)
        }
    }
    
}

// MARK: - types

internal let OneShotRequestTimeOut: TimeInterval = 0.5 * 60.0

// MARK: - PositionlocationManagerDelegate

internal protocol PositionLocationManagerDelegate: NSObjectProtocol {
    func positionLocationManager(_ positionLocationManager: PositionLocationManager, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus)
    func positionLocationManager(_ positionLocationManager: PositionLocationManager, didFailWithError error: Error?)

    func positionLocationManager(_ positionLocationManager: PositionLocationManager, didUpdateOneShotLocation location: CLLocation?)
    func positionLocationManager(_ positionLocationManager: PositionLocationManager, didUpdateTrackingLocations location: [CLLocation]?)
    func positionLocationManager(_ positionLocationManager: PositionLocationManager, didUpdateFloor floor: CLFloor)
    func positionLocationManager(_ positionLocationManager: PositionLocationManager, didVisit visit: CLVisit?)
}

// MARK: - PositionLocationManager

internal class PositionLocationManager: NSObject {

    internal weak var delegate: PositionLocationManagerDelegate?
    
    internal var distanceFilter: Double {
        didSet {
            self.updateLocationManagerStateIfNeeded()
        }
    }
    
    internal var timeFilter: TimeInterval
    
    internal var trackingDesiredAccuracyActive: Double {
        didSet {
            self.updateLocationManagerStateIfNeeded()
        }
    }
    
    internal var trackingDesiredAccuracyBackground: Double {
        didSet {
            self.updateLocationManagerStateIfNeeded()
        }
    }
    
    internal var locations: [CLLocation]?

    internal var updatingLocation: Bool
    internal var updatingLowPowerLocation: Bool

    // MARK: - ivars
    
    internal var _locationManager: CLLocationManager
    internal var _locationRequests: [PositionLocationRequest]?
    
    // MARK: - object lifecycle
    
    override init() {
        self.distanceFilter = 0
        self.timeFilter = 0
        
        self.trackingDesiredAccuracyActive = kCLLocationAccuracyHundredMeters
        self.trackingDesiredAccuracyBackground = kCLLocationAccuracyKilometer

        self.updatingLocation = false
        self.updatingLowPowerLocation = false

        self._locationManager = CLLocationManager()
        super.init()
        
        self._locationManager.delegate = self
        self._locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self._locationManager.pausesLocationUpdatesAutomatically = false
    }
}

// MARK: - permissions

extension PositionLocationManager {
    
    internal var locationServicesStatus: LocationAuthorizationStatus {
        get {
            guard CLLocationManager.locationServicesEnabled() == true else {
                return .notAvailable
            }
            
            var status: LocationAuthorizationStatus = .notDetermined
            switch CLLocationManager.authorizationStatus() {
                case .authorizedAlways:
                    status = .allowedAlways
                    break
                case .authorizedWhenInUse:
                    status = .allowedWhenInUse
                    break
                case .denied, .restricted:
                    status = .denied
                    break
                case .notDetermined:
                    status = .notDetermined
                    break
            }
            return status
        }
    }
    
    internal func requestAlwaysAuthorization() {
        self._locationManager.requestAlwaysAuthorization()
    }
    
    internal func requestWhenInUseAuthorization() {
        self._locationManager.requestWhenInUseAuthorization()
    }
    
}

// MARK: - location services

extension PositionLocationManager {
   
    internal func performOneShotLocationUpdate(withDesiredAccuracy desiredAccuracy: Double, completionHandler: @escaping OneShotCompletionHandler) {
        if self.locationServicesStatus == .allowedAlways ||
            self.locationServicesStatus == .allowedWhenInUse {
            
            let request = PositionLocationRequest()
            request.desiredAccuracy = desiredAccuracy
            request.lifespan = OneShotRequestTimeOut
            request.timeOutHandler = {
                self.processLocationRequests()
            }
            request.completionHandler = completionHandler

            if self._locationRequests == nil {
                self._locationRequests = []
            }
            self._locationRequests?.append(request)

            self.startLowPowerUpdating()
            self._locationManager.desiredAccuracy = kCLLocationAccuracyBest
            self._locationManager.distanceFilter = kCLDistanceFilterNone

            if self.updatingLocation == false {
                self.startUpdating()
                
                // flag signals to turn off updating once complete
                self.updatingLocation = false
            }
            
        } else {
            self.executeClosureAsyncOnMainQueueIfNecessary {
                let error = NSError(domain: ErrorDomain, code: ErrorType.restricted.rawValue, userInfo: nil)
                completionHandler(nil, error)
            }
        }
    }
    
    internal func startUpdating() {
        switch self.locationServicesStatus {
            case .allowedAlways,
                 .allowedWhenInUse:
                self._locationManager.startUpdatingLocation()
                self._locationManager.startMonitoringVisits()
                self.updatingLocation = true
                self.updateLocationManagerStateIfNeeded()
                fallthrough
            default:
                break
        }
    }

    internal func stopUpdating() {
        switch self.locationServicesStatus {
            case .allowedAlways,
                 .allowedWhenInUse:
                if self.updatingLocation == true {
                    self._locationManager.stopUpdatingLocation()
                    self._locationManager.stopMonitoringVisits()
                    self.updatingLocation = false
                    self.updateLocationManagerStateIfNeeded()
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
                self._locationManager.startMonitoringSignificantLocationChanges()
                self.updatingLowPowerLocation = true
                self.updateLocationManagerStateIfNeeded()
                fallthrough
            default:
                break
        }
    }

    internal func stopLowPowerUpdating() {
        let status: LocationAuthorizationStatus = self.locationServicesStatus
        switch status {
            case .allowedAlways, .allowedWhenInUse:
                self._locationManager.stopMonitoringSignificantLocationChanges()
                self.updatingLowPowerLocation = false
                self.updateLocationManagerStateIfNeeded()
                fallthrough
            default:
                break
        }
    }
    
    // MARK - private methods
    
    // only called from the request queue
    internal func processLocationRequests() {
        if let locationRequests = self._locationRequests {
            guard
                locationRequests.count > 0
            else {
                self.delegate?.positionLocationManager(self, didUpdateTrackingLocations: self.locations)
                return
            }
        
            let completeRequests: [PositionLocationRequest] = locationRequests.filter { (request) -> Bool in
                // check if a request completed, meaning expired or met horizontal accuracy
                //print("desiredAccuracy \(request.desiredAccuracy) horizontal \(self.location?.horizontalAccuracy)")
                if let location = self.locations?.first {
                    guard
                        request.expired == true || location.horizontalAccuracy < request.desiredAccuracy
                    else {
                        return false
                    }
                    return true
                }
                return false
            }
            
            for request in completeRequests {
                if let handler = request.completionHandler {
                    if request.expired == true {
                        let error = NSError(domain: ErrorDomain, code: ErrorType.timedOut.rawValue, userInfo: nil)
                        handler(nil, error)
                    } else {
                        handler(self.locations?.first, nil)
                    }
                }
                if let index = locationRequests.index(of: request) {
                    self._locationRequests?.remove(at: index)
                }
            }
            
            if locationRequests.count == 0 {
                self._locationRequests = nil
                self.updateLocationManagerStateIfNeeded()
                
                if self.updatingLocation == false {
                    self.stopUpdating()
                }
                
                if self.updatingLowPowerLocation == false {
                    self.stopLowPowerUpdating()
                }
            }
        }
    }
    
    internal func completeLocationRequestsWithError(_ error: Error?) {
        if let locationRequests = self._locationRequests {
            for locationRequest in locationRequests {
                locationRequest.cancelRequest()
                guard let handler = locationRequest.completionHandler else { continue }
                if let resultingError = error {
                    handler(nil, resultingError)
                } else {
                    handler(nil, NSError(domain: ErrorDomain, code: ErrorType.cancelled.rawValue, userInfo: nil))
                }
            }
        }
    }

    internal func updateLocationManagerStateIfNeeded() {
        // when not processing requests, set desired accuracy appropriately
        if let locationRequests = self._locationRequests {
            if locationRequests.count > 0 {
                if self.updatingLocation == true {
                    self._locationManager.desiredAccuracy = self.trackingDesiredAccuracyActive
                } else if self.updatingLowPowerLocation == true {
                    self._locationManager.desiredAccuracy = self.trackingDesiredAccuracyBackground
                }
                
                self._locationManager.distanceFilter = self.distanceFilter
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension PositionLocationManager: CLLocationManagerDelegate {
    
    @objc(locationManager:didUpdateLocations:)
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.locations = locations
    
        // update one-shot requests
        self.processLocationRequests()
    }
    
    @objc(locationManager:didFailWithError:)
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.completeLocationRequestsWithError(error)
        self.delegate?.positionLocationManager(self, didFailWithError: error)
    }
    
    @objc(locationManager:didChangeAuthorizationStatus:)
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
            case .denied, .restricted:
                self.completeLocationRequestsWithError(NSError(domain: ErrorDomain, code: ErrorType.restricted.rawValue, userInfo: nil))
                break
            default:
                break
        }
        self.delegate?.positionLocationManager(self, didChangeLocationAuthorizationStatus: self.locationServicesStatus)
    }
    
    @objc(locationManager:didDetermineState:forRegion:)
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
    }
    
    @objc(locationManager:didVisit:)
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        self.delegate?.positionLocationManager(self, didVisit: visit)
    }

    @objc(locationManager:didEnterRegion:)
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        // TODO low power geofence tracking
    }
    
    @objc(locationManager:didExitRegion:)
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        // TODO low power geofence tracking
    }
    
    @objc(locationManager:didStartMonitoringForRegion:)
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
    }

    @objc(locationManager:monitoringDidFailForRegion:withError:)
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        self.delegate?.positionLocationManager(self, didFailWithError: error)
    }
    
}

// MARK: - queues

extension PositionLocationManager {
    
    internal func executeClosureAsyncOnMainQueueIfNecessary(withClosure closure: @escaping () -> Void) {
        if Thread.isMainThread {
            closure()
        } else {
            DispatchQueue.main.async(execute: closure)
        }
    }
    
    internal func executeClosureSyncOnMainQueueIfNecessary(withClosure closure: @escaping () -> Void) {
        if Thread.isMainThread {
            closure()
        } else {
            DispatchQueue.main.sync(execute: closure)
        }
    }
    
}

// MARK: - PositionLocationRequest

internal class PositionLocationRequest: NSObject {

    // MARK: - types
    
    internal typealias TimeOutCompletionHandler = () -> (Void)

    // MARK: - properties
    
    internal var desiredAccuracy: Double
    internal var lifespan: TimeInterval {
        didSet {
            self.expired = false
            self._expirationTimer?.invalidate()
            self._expirationTimer = Timer.scheduledTimer(timeInterval: self.lifespan, target: self, selector: #selector(handleTimerFired(_:)), userInfo: nil, repeats: false)
        }
    }
    
    internal var completed: Bool
    internal var expired: Bool

    internal var timeOutHandler: TimeOutCompletionHandler?
    internal var completionHandler: OneShotCompletionHandler?
    
    // MARK: - ivars

    internal var _expirationTimer: Timer?
    
    // MARK: - object lifecycle
    
    override init() {
        self.desiredAccuracy = kCLLocationAccuracyBest
        self.lifespan = OneShotRequestTimeOut
        self.completed = false
        self.expired = false
        super.init()
    }
    
    deinit {
        self.expired = true
        self._expirationTimer?.invalidate()
        self._expirationTimer = nil
        
        self.timeOutHandler = nil
        self.completionHandler = nil
    }

    // MARK: - funcs

    internal func cancelRequest() {
        self.expired = true
        self._expirationTimer?.invalidate()
        self._expirationTimer = nil

        self.timeOutHandler = nil
        // Note: completion handler will be processed on the request process loop
    }
}

// MARK: - Timer

extension PositionLocationRequest {
    
    internal func handleTimerFired(_ timer: Timer) {
        DispatchQueue.main.async(execute: {
            self.expired = true
            self._expirationTimer?.invalidate()
            self._expirationTimer = nil
            
            if let timeOutHandler = self.timeOutHandler {
                timeOutHandler()
                self.timeOutHandler = nil
            }
        })
    }
    
}

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
public class Position {
    
    // MARK: - types
    
    /// Completion handler for one-shot location requests
    public typealias OneShotCompletionHandler = (Swift.Result<CLLocation, Error>) -> Void

    /// Time based filter constant
    public static let TimeFilterNone: TimeInterval = 0.0
    /// Time based filter constant
    public static let TimeFilter5Minutes: TimeInterval = 5.0 * 60.0
    /// Time based filter constant
    public static let TimeFilter10Minutes: TimeInterval = 10.0 * 60.0

    // MARK: - singleton
    
    /// Shared singleton
    public static let shared = Position()
    
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
    public var adjustLocationUseWhenBackgrounded: Bool = false {
        didSet {
            if self._positionLocationManager.isUpdatingLowPowerLocation == true {
                self._positionLocationManager.stopLowPowerUpdating()
                self._positionLocationManager.startUpdating()
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
    
    /// `true` when location services are updating
    public var isUpdatingLocation: Bool {
        get {
            return self._positionLocationManager.isUpdatingLocation == true || self._positionLocationManager.isUpdatingLowPowerLocation == true
        }
    }

    /// Last determined location
    public var location: CLLocation? {
        get {
            return self._positionLocationManager.locations?.first
        }
    }
    
    // MARK: - ivars
    
    internal var _authorizationObservers: NSHashTable<AnyObject>?
    internal var _observers: NSHashTable<AnyObject>?
    internal var _positionLocationManager: PositionLocationManager
    internal var _updating: Bool = false
    
    // MARK: - object lifecycle

    init() {
        self._positionLocationManager = PositionLocationManager()
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
    public func addAuthorizationObserver(_ observer: PositionAuthorizationObserver?) {
        if self._authorizationObservers == nil {
            self._authorizationObservers = NSHashTable.weakObjects()
        }
        
        if self._authorizationObservers?.contains(observer) == false {
            self._authorizationObservers?.add(observer)
        }
    }
    
    /// Removes an authorization observer.
    ///
    /// - Parameter observer: Observing instance.
    public func removeAuthorizationObserver(_ observer: PositionAuthorizationObserver?) {
        if self._authorizationObservers?.contains(observer) == true {
            self._authorizationObservers?.remove(observer)
        }
        if self._authorizationObservers?.count == 0 {
            self._authorizationObservers = nil
        }
    }
    
    /// Adds a position observer.
    ///
    /// - Parameter observer: Observing instance.
    public func addObserver(_ observer: PositionObserver?) {
        if self._observers == nil {
            self._observers = NSHashTable.weakObjects()
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

// MARK: - authorization / permission

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
    public func performOneShotLocationUpdate(withDesiredAccuracy desiredAccuracy: Double, completionHandler: Position.OneShotCompletionHandler? = nil) {
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
                    self._positionLocationManager.trackingDesiredAccuracyActive = kCLLocationAccuracyNearestTenMeters
                    self._positionLocationManager.trackingDesiredAccuracyBackground = kCLLocationAccuracyHundredMeters
                    break
                case .unplugged,
                     .unknown:
                    fallthrough
                @unknown default:
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
    
    @objc internal func handleApplicationDidBecomeActive(_ notification: Notification) {
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

    @objc internal func handleApplicationWillResignActive(_ notification: Notification) {
        if self._updating == true {
            return
        }

        if self.adjustLocationUseWhenBackgrounded == true {
            self._positionLocationManager.startLowPowerUpdating()
        }
        
        self.updateLocationAccuracyIfNecessary()
    }

    @objc internal func handleBatteryLevelChanged(_ notification: Notification) {
        let batteryLevel = UIDevice.current.batteryLevel
        if batteryLevel < 0 {
            return
        }
        self.updateLocationAccuracyIfNecessary()
    }

    @objc internal func handleBatteryStateChanged(_ notification: Notification) {
        self.updateLocationAccuracyIfNecessary()
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
                observer.position(self, didFailWithError : error)
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
            for observer in self._observers?.allObjects as? [PositionObserver] ?? [] {
                observer.position(self, didVisit: visit)
            }
        }
    }
    
}

// MARK: - PositionlocationManagerDelegate

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
    
    internal static let OneShotRequestTimeOut: TimeInterval = 0.5 * 60.0
    internal static let RequestQueueIdentifier = "PositionRequestQueueIdentifier"
    internal static let RequestQueueSpecificKey = DispatchSpecificKey<()>()

    internal weak var delegate: PositionLocationManagerDelegate?
    
    internal var distanceFilter: Double = 0.0 {
        didSet {
            self.updateLocationManagerStateIfNeeded()
        }
    }
    
    internal var timeFilter: TimeInterval = 0.0
    
    internal var trackingDesiredAccuracyActive: Double = kCLLocationAccuracyHundredMeters {
        didSet {
            self.updateLocationManagerStateIfNeeded()
        }
    }
    
    internal var trackingDesiredAccuracyBackground: Double = kCLLocationAccuracyKilometer {
        didSet {
            self.updateLocationManagerStateIfNeeded()
        }
    }
    
    internal var locations: [CLLocation]?

    internal var updatingLocation: Bool = false
    internal var updatingLowPowerLocation: Bool = false

    // MARK: - ivars
    
    internal var _locationManager: CLLocationManager 
    internal var _locationRequests: [PositionLocationRequest] = []
    internal var _requestQueue: DispatchQueue
    
    // MARK: - object lifecycle
    
    override init() {
        self._requestQueue = DispatchQueue(label: PositionRequestQueueIdentifier, autoreleaseFrequency: .workItem, target: DispatchQueue.global())
        self._requestQueue.setSpecific(key: PositionRequestQueueSpecificKey, value: ())
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
                    fallthrough
                @unknown default:
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
   
    internal func performOneShotLocationUpdate(withDesiredAccuracy desiredAccuracy: Double, completionHandler: Position.OneShotCompletionHandler? = nil) {
        if self.locationServicesStatus == .allowedAlways ||
            self.locationServicesStatus == .allowedWhenInUse {
            
            self.executeClosureAsyncOnRequestQueueIfNecessary {
                let request = PositionLocationRequest()
                request.desiredAccuracy = desiredAccuracy
                request.lifespan = PositionLocationManager.OneShotRequestTimeOut
                request.timeOutHandler = {
                    self.processLocationRequests()
                }
                request.completionHandler = completionHandler
                
                self._locationRequests.append(request)
                
                self.startLowPowerUpdating()
                self._locationManager.desiredAccuracy = kCLLocationAccuracyBest
                self._locationManager.distanceFilter = kCLDistanceFilterNone
                
                // activate location to process request
                if self.updatingLocation == false {
                    self.startUpdating()
                    // flag signals to turn off updating once complete
                    self.updatingLocation = false
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
    
}

// MARK - private methods

extension PositionLocationManager {
    
    // only called from the request queue
    internal func processLocationRequests() {
        guard self._locationRequests.count > 0 else {
            DispatchQueue.main.async {
                self.delegate?.positionLocationManager(self, didUpdateTrackingLocations: self.locations)
            }
            return
        }
    
        let completeRequests: [PositionLocationRequest] = self._locationRequests.filter { (request) -> Bool in
            // check if a request completed, meaning expired or met horizontal accuracy
            //print("desiredAccuracy \(request.desiredAccuracy) horizontal \(self.location?.horizontalAccuracy)")
            if let location = self.locations?.first {
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
                if let location = self.locations?.first {
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
        
        let pendingRequests: [PositionLocationRequest] = self._locationRequests.filter { (request) -> Bool in
            request.completed == false
        }
        self._locationRequests = pendingRequests

        if self._locationRequests.count == 0 {
            self.updateLocationManagerStateIfNeeded()
            
            if self.updatingLocation == false {
                self.stopUpdating()
            }
            
            if self.updatingLowPowerLocation == false {
                self.stopLowPowerUpdating()
            }
        }
    }
    
    internal func completeLocationRequests(withError error: Error?) {
        for locationRequest in self._locationRequests {
            locationRequest.cancelRequest()
            guard let handler = locationRequest.completionHandler else {
                continue
            }
            
            self.executeClosureSyncOnMainQueueIfNecessary {
                handler(nil, error ?? PositionErrorType.cancelled)
            }
        }
    }

    internal func updateLocationManagerStateIfNeeded() {
        // when not processing requests, set desired accuracy appropriately
        if self._locationRequests.count > 0 {
            if self.updatingLocation == true {
                self._locationManager.desiredAccuracy = self.trackingDesiredAccuracyActive
            } else if self.updatingLowPowerLocation == true {
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
            self.locations = locations
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
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        self.executeClosureAsyncOnRequestQueueIfNecessary {
            switch status {
            case .denied, .restricted:
                self.completeLocationRequests(withError: PositionErrorType.restricted)
                break
            default:
                break
            }
            DispatchQueue.main.async {
                self.delegate?.positionLocationManager(self, didChangeLocationAuthorizationStatus: self.locationServicesStatus)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
    }
    
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        self.delegate?.positionLocationManager(self, didVisit: visit)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        // TODO low power geofence tracking
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        // TODO low power geofence tracking
    }
    
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        self.delegate?.positionLocationManager(self, didFailWithError: error)
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
        if DispatchQueue.getSpecific(key: PositionRequestQueueSpecificKey) != nil {
            closure()
        } else {
            self._requestQueue.async(execute: closure)
        }
    }
    
}

// MARK: - PositionLocationRequest

internal class PositionLocationRequest {

    // MARK: - types
    
    internal typealias TimeOutCompletionHandler = () -> (Void)

    // MARK: - properties
    
    internal var desiredAccuracy: Double = kCLLocationAccuracyBest
    internal var lifespan: TimeInterval = OneShotRequestTimeOut {
        didSet {
            self.expired = false
            self._expirationTimer?.invalidate()
            self._expirationTimer = Timer.scheduledTimer(timeInterval: self.lifespan, target: self, selector: #selector(handleTimerFired(_:)), userInfo: nil, repeats: false)
        }
    }
    
    internal var completed: Bool = false
    internal var expired: Bool = false

    internal var timeOutHandler: TimeOutCompletionHandler?
    internal var completionHandler: Position.OneShotCompletionHandler?
    
    // MARK: - ivars

    internal var _expirationTimer: Timer?
    
    // MARK: - object lifecycle
    
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
    
    @objc internal func handleTimerFired(_ timer: Timer) {
        DispatchQueue.main.async {
            self.expired = true
            self._expirationTimer?.invalidate()
            self._expirationTimer = nil
            
            if let timeOutHandler = self.timeOutHandler {
                timeOutHandler()
                self.timeOutHandler = nil
            }
        }
    }
    
}

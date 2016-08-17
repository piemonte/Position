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
import CoreMotion

// MARK: - Position Types

public enum LocationAuthorizationStatus: CustomStringConvertible {
    case notDetermined
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

public enum MotionAuthorizationStatus: CustomStringConvertible {
    case notDetermined
    case notAvailable
    case allowed
    
    public var description: String {
        get {
            switch self {
            case .notDetermined:
                return "Not Determined"
            case .notAvailable:
                return "Not Available"
            case .allowed:
                return "Allowed"
            }
        }
    }
}

public enum MotionActivityType: CustomStringConvertible {
    case unknown
    case walking
    case running
    case automotive
    case cycling
    
    init(activity: CMMotionActivity) {
        if activity.walking {
            self = .walking
        } else if activity.running {
            self = .running
        } else if activity.automotive {
            self = .automotive
        } else if activity.cycling {
            self = .cycling
        } else {
            self = .unknown
        }
    }
    
    public var description: String {
        get {
            switch self {
                case .unknown:
                    return "Unknown"
                case .walking:
                    return "Walking"
                case .running:
                    return "Running"
                case .automotive:
                    return "Automotive"
                case .cycling:
                    return "Cycling"
            }
        }
    }
    
    public var locationActivityType: CLActivityType {
        switch self {
        case .automotive:
            return .automotiveNavigation
        case .walking, .running, .cycling:
            return .fitness
        default:
            return .other
        }
    }
}

// MARK: - Position Errors

public let ErrorDomain = "PositionErrorDomain"

public enum ErrorType: Int, CustomStringConvertible {
    case timedOut = 0
    case restricted = 1
    case cancelled = 2
    
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

// MARK: - constants

public let TimeFilterNone: TimeInterval = 0.0
public let TimeFilter5Minutes: TimeInterval = 5.0 * 60.0
public let TimeFilter10Minutes: TimeInterval = 10.0 * 60.0

public typealias OneShotCompletionHandler = (_: CLLocation?, _: Error?) -> ()

// MARK: - PositionObserver

public protocol PositionObserver: NSObjectProtocol {
    // permission
    func position(_ position: Position, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus)
    func position(_ position: Position, didChangeMotionAuthorizationStatus status: MotionAuthorizationStatus)
    
    // error handling
    func position(_ position: Position, didFailWithError error: Error?)
    
    // location
    func position(_ position: Position, didUpdateOneShotLocation location: CLLocation?)
    func position(_ position: Position, didUpdateTrackingLocations locations: [CLLocation]?)
    func position(_ position: Position, didUpdateFloor floor: CLFloor)
    func position(_ position: Position, didVisit visit: CLVisit?)
    
    func position(_ position: Position, didChangeDesiredAccurary desiredAccuracy: Double)
    
    // motion
    func position(_ position: Position, didChangeActivity activity: MotionActivityType)
}

// MARK: - Position

public class Position: NSObject {

    internal var observers: NSHashTable<AnyObject>?
    
    // location types
    internal let locationCenter: PositionLocationCenter
    internal var updatingPosition: Bool
    
    // motion types
    private let activityManager: CMMotionActivityManager
    private let activityQueue: OperationQueue
    private var lastActivity: MotionActivityType
    private var updatingActivity: Bool

    // MARK: - singleton

    static let sharedPosition: Position = Position()

    // MARK: - object lifecycle
    
    override init() {
        self.locationCenter = PositionLocationCenter()
        
        self.updatingPosition = false
        self.updatingActivity = false
        self.adjustLocationUseWhenBackgrounded = false
        self.adjustLocationUseFromBatteryLevel = false
        self.adjustLocationUseFromActivity = false
        
        self.activityManager = CMMotionActivityManager()
        self.activityQueue = OperationQueue()
        self.motionActivityStatus = CMMotionActivityManager.isActivityAvailable() ? .notDetermined : .notAvailable
        self.lastActivity = .unknown
                
        super.init()
        
        self.locationCenter.delegate = self
        
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        NotificationCenter.default.addObserver(self, selector: #selector(UIApplicationDelegate.applicationDidEnterBackground(_:)), name: NSNotification.Name.UIApplicationDidEnterBackground, object: UIApplication.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(UIApplicationDelegate.applicationDidBecomeActive(_:)), name: NSNotification.Name.UIApplicationDidBecomeActive, object: UIApplication.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(UIApplicationDelegate.applicationWillResignActive(_:)), name: NSNotification.Name.UIApplicationWillResignActive, object: UIApplication.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(Position.batteryLevelChanged(_:)), name:NSNotification.Name.UIDeviceBatteryLevelDidChange, object: UIApplication.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(Position.batteryStateChanged(_:)), name:NSNotification.Name.UIDeviceBatteryStateDidChange, object: UIApplication.shared)
    }

    // MARK: - Position permissions and access

    public var locationServicesStatus: LocationAuthorizationStatus? {
        get {
            return self.locationCenter.locationServicesStatus
        }
    }

    public func requestAlwaysLocationAuthorization() {
        self.locationCenter.requestAlwaysAuthorization()
    }

    public func requestWhenInUseLocationAuthorization() {
        self.locationCenter.requestWhenInUseAuthorization()
    }
    
    public func requestMotionActivityAuthorization() {
        guard self.motionActivityStatus == .allowed else {
            self.activityManager.startActivityUpdates(to: OperationQueue()) { (activity) in
                self.activityManager.stopActivityUpdates()
                
                let enumerator = self.observers?.objectEnumerator()
                while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
                    self.motionActivityStatus = .allowed
                    observer.position(self, didChangeMotionAuthorizationStatus: self.motionActivityStatus)
                }
            }
            return;
        }
    }
    
    // MARK: - Position observers

    public func addObserver(_ observer: PositionObserver?) {
        if self.observers == nil {
            self.observers = NSHashTable.weakObjects()
        }
         
        if self.observers?.contains(observer) == false {
            self.observers?.add(observer)
        }
    }
    
    public func removeObserver(_ observer: PositionObserver?) {
        if self.observers?.contains(observer) == true {
            self.observers?.remove(observer)
        }
        if self.observers?.count == 0 {
            self.observers = nil;
        }
    }

    // MARK: - Position properties
    
    public var adjustLocationUseWhenBackgrounded: Bool {
        didSet {
            if self.locationCenter.updatingLowPowerLocation == true {
                self.locationCenter.stopLowPowerUpdating()
                self.locationCenter.startUpdating()
            }
        }
    }

    public var adjustLocationUseFromBatteryLevel: Bool
    
    public var updatingLocation: Bool {
        get {
            return self.locationCenter.updatingLocation == true || self.locationCenter.updatingLowPowerLocation == true
        }
    }

    // MARK: - location lookup
    
    public var location: CLLocation? {
        get {
            return locationCenter.location
        }
    }
    
    public func performOneShotLocationUpdateWithDesiredAccuracy(_ desiredAccuracy: Double, completionHandler: OneShotCompletionHandler) {
        self.locationCenter.performOneShotLocationUpdateWithDesiredAccuracy(desiredAccuracy, completionHandler: completionHandler)
    }

    // MARK: - location tracking

    public var trackingDesiredAccuracyWhenActive: Double {
        get {
            return self.locationCenter.trackingDesiredAccuracyActive
        }
        set {
            self.locationCenter.trackingDesiredAccuracyActive = newValue
        }
    }
    
    public var trackingDesiredAccuracyWhenInBackground: Double {
        get {
            return self.locationCenter.trackingDesiredAccuracyBackground
        }
        set {
            self.locationCenter.trackingDesiredAccuracyBackground = newValue
        }
    }

    public var distanceFilter: Double {
        get {
            return self.locationCenter.distanceFilter
        }
        set {
            self.locationCenter.distanceFilter = newValue
        }
    }

    public var timeFilter: TimeInterval {
        get {
            return self.locationCenter.timeFilter
        }
        set {
            self.locationCenter.timeFilter = newValue
        }
    }

    public func startUpdating() {
        self.locationCenter.startUpdating()
        self.updatingPosition = true
        
        if self.motionActivityStatus == .allowed {
            self.startUpdatingActivity()
        }
    }

    public func stopUpdating() {
        self.locationCenter.stopUpdating()
        self.locationCenter.stopLowPowerUpdating()
        self.updatingPosition = false
        
        if self.updatingActivity {
            self.stopUpdatingActivity()
        }
    }
    
    // MARK: - motion tracking
    
    public var motionActivityStatus: MotionAuthorizationStatus {
        didSet {
            if self.motionActivityStatus == .allowed && self.adjustLocationUseFromActivity {
                self.startUpdatingActivity()
            }
        }
    }
    
    public var adjustLocationUseFromActivity: Bool {
        didSet {
            if self.motionActivityStatus == .allowed {
                if self.adjustLocationUseFromActivity == true {
                    self.startUpdatingActivity()
                } else if self.updatingActivity == true {
                    self.stopUpdatingActivity()
                }
            }
        }
    }
    
    public func startUpdatingActivity() {
        self.updatingActivity = true
        self.activityManager.startActivityUpdates(to: activityQueue) { (activity) in
            DispatchQueue.main.async(execute: {
                let activity = MotionActivityType(activity: activity!)
                if self.adjustLocationUseFromActivity {
                    self.locationCenter.activityType = activity
                    self.updateLocationAccuracyIfNecessary()
                }
                if self.lastActivity != activity {
                    self.lastActivity = activity
                    let enumerator = self.observers?.objectEnumerator()
                    while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
                        observer.position(self, didChangeActivity: activity)
                    }
                }
            })
        }
    }
    
    public func stopUpdatingActivity() {
        self.updatingActivity = false
        self.activityManager.stopActivityUpdates()
    }
    
    // MARK: - private functions
    
    internal func checkAuthorizationStatusForServices() {
        if self.locationCenter.locationServicesStatus == .denied {
            let enumerator = self.observers?.objectEnumerator()
            while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
                observer.position(self, didChangeLocationAuthorizationStatus: .denied)
            }
        }
        
        if self.motionActivityStatus == .notDetermined {
            self.activityManager.startActivityUpdates(to: OperationQueue()) { (activity) in
                self.activityManager.stopActivityUpdates()
                self.motionActivityStatus = .allowed
                
                let enumerator = self.observers?.objectEnumerator()
                while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
                    observer.position(self, didChangeMotionAuthorizationStatus: self.motionActivityStatus)
                }
            }
        }
    }
    
    internal func updateLocationAccuracyIfNecessary() {
        if self.adjustLocationUseFromBatteryLevel == true {
            let currentState: UIDeviceBatteryState = UIDevice.current.batteryState
            
            switch currentState {
                case .full, .charging:
                    self.locationCenter.trackingDesiredAccuracyActive = kCLLocationAccuracyNearestTenMeters
                    self.locationCenter.trackingDesiredAccuracyBackground = kCLLocationAccuracyHundredMeters
                
                    if self.adjustLocationUseFromActivity == true {
                        switch lastActivity {
                            case .automotive, .cycling:
                                self.locationCenter.trackingDesiredAccuracyActive = kCLLocationAccuracyBestForNavigation
                                break
                            default:
                                break
                        }
                    }
                    
                case .unplugged, .unknown:
                    let batteryLevel: Float = UIDevice.current.batteryLevel
                    if batteryLevel < 0.15 {
                        self.locationCenter.trackingDesiredAccuracyActive = kCLLocationAccuracyThreeKilometers
                        self.locationCenter.trackingDesiredAccuracyBackground = kCLLocationAccuracyThreeKilometers
                    } else {
                        self.locationCenter.trackingDesiredAccuracyActive = kCLLocationAccuracyHundredMeters
                        self.locationCenter.trackingDesiredAccuracyBackground = kCLLocationAccuracyKilometer
                        
                        if self.adjustLocationUseFromActivity == true {
                            switch lastActivity {
                                case .walking:
                                    self.locationCenter.trackingDesiredAccuracyActive = kCLLocationAccuracyNearestTenMeters
                                    break
                                default:
                                    break
                            }
                        }
                    }
                    break
            }
        } else if self.adjustLocationUseFromActivity == true {
            switch lastActivity {
                case .automotive, .cycling:
                    self.locationCenter.trackingDesiredAccuracyActive = kCLLocationAccuracyHundredMeters
                    self.locationCenter.trackingDesiredAccuracyBackground = kCLLocationAccuracyKilometer
                    break
                case .running, .walking:
                    self.locationCenter.trackingDesiredAccuracyActive = kCLLocationAccuracyNearestTenMeters
                    self.locationCenter.trackingDesiredAccuracyBackground = kCLLocationAccuracyHundredMeters
                    break
                default:
                    break
            }
        }
    }
}

// MARK: - NSNotifications

extension Position {
    
    func applicationDidEnterBackground(_ notification: Notification) {
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        self.checkAuthorizationStatusForServices()
        
        // if position is not updating, don't modify state
        if self.updatingPosition == false {
            return
        }
        
        // internally, locationCenter will adjust desiredaccuracy to trackingDesiredAccuracyBackground
        if self.adjustLocationUseWhenBackgrounded == true {
            self.locationCenter.stopLowPowerUpdating()
        }        
    }

    func applicationWillResignActive(_ notification: Notification) {
        if self.updatingPosition == true {
            return
        }

        if self.adjustLocationUseWhenBackgrounded == true {
            self.locationCenter.startLowPowerUpdating()
        }
        
        self.updateLocationAccuracyIfNecessary()
    }

    func batteryLevelChanged(_ notification: Notification) {
        let batteryLevel: Float = UIDevice.current.batteryLevel
        if batteryLevel < 0 {
            return
        }
        self.updateLocationAccuracyIfNecessary()
    }

    func batteryStateChanged(_ notification: Notification) {
        self.updateLocationAccuracyIfNecessary()
    }
    
}

// MARK: - PositionLocationCenterDelegate

extension Position: PositionLocationCenterDelegate {

    internal func positionLocationCenter(_ positionLocationCenter: PositionLocationCenter, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus) {
        let enumerator = self.observers?.objectEnumerator()
        while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
            observer.position(self, didChangeLocationAuthorizationStatus: status)
        }
    }
    
    internal func positionLocationCenter(_ positionLocationCenter: PositionLocationCenter, didFailWithError error: Error?) {
        let enumerator = self.observers?.objectEnumerator()
        while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
            observer.position(self, didFailWithError : error)
        }
    }
    
    internal func positionLocationCenter(_ positionLocationCenter: PositionLocationCenter, didUpdateOneShotLocation location: CLLocation?) {
        let enumerator = self.observers?.objectEnumerator()
        while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
            observer.position(self, didUpdateOneShotLocation: location)
        }
    }
    
    internal func positionLocationCenter(_ positionLocationCenter: PositionLocationCenter, didUpdateTrackingLocations locations: [CLLocation]?) {
        let enumerator = self.observers?.objectEnumerator()
        while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
            observer.position(self, didUpdateTrackingLocations: locations)
        }
    }
    
    internal func positionLocationCenter(_ positionLocationCenter: PositionLocationCenter, didUpdateFloor floor: CLFloor) {
        let enumerator = self.observers?.objectEnumerator()
        while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
            observer.position(self, didUpdateFloor: floor)
        }
    }

    internal func positionLocationCenter(_ positionLocationCenter: PositionLocationCenter, didVisit visit: CLVisit?) {
        let enumerator = self.observers?.objectEnumerator()
        while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
            observer.position(self, didVisit: visit)
        }
    }
}

// MARK: - PositionLocationCenter

let PositionOneShotRequestTimeOut: TimeInterval = 0.5 * 60.0

internal protocol PositionLocationCenterDelegate: NSObjectProtocol {
    func positionLocationCenter(_ positionLocationCenter: PositionLocationCenter, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus)
    func positionLocationCenter(_ positionLocationCenter: PositionLocationCenter, didFailWithError error: Error?)

    func positionLocationCenter(_ positionLocationCenter: PositionLocationCenter, didUpdateOneShotLocation location: CLLocation?)
    func positionLocationCenter(_ positionLocationCenter: PositionLocationCenter, didUpdateTrackingLocations location: [CLLocation]?)
    func positionLocationCenter(_ positionLocationCenter: PositionLocationCenter, didUpdateFloor floor: CLFloor)
    func positionLocationCenter(_ positionLocationCenter: PositionLocationCenter, didVisit visit: CLVisit?)
}

internal class PositionLocationCenter: NSObject {

    weak var delegate: PositionLocationCenterDelegate?
    
    var distanceFilter: Double! {
        didSet {
            self.updateLocationManagerStateIfNeeded()
        }
    }
    
    var timeFilter: TimeInterval!
    
    var trackingDesiredAccuracyActive: Double {
        didSet {
            self.updateLocationManagerStateIfNeeded()
        }
    }
    var trackingDesiredAccuracyBackground: Double {
        didSet {
            self.updateLocationManagerStateIfNeeded()
        }
    }
    
    var activityType: MotionActivityType {
        didSet {
            locationManager.activityType = activityType.locationActivityType
        }
    }
    
    var location: CLLocation?
    var locations: [CLLocation]?
    
    private var locationManager: CLLocationManager
    private var locationRequests: [PositionLocationRequest]?
    internal var updatingLocation: Bool
    internal var updatingLowPowerLocation: Bool
    
    // MARK: - object lifecycle
    
    override init() {
        self.locationManager = CLLocationManager()
        self.updatingLocation = false
        self.updatingLowPowerLocation = false
        self.activityType = .unknown
        
        self.trackingDesiredAccuracyActive = kCLLocationAccuracyHundredMeters
        self.trackingDesiredAccuracyBackground = kCLLocationAccuracyKilometer

        super.init()
        
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.pausesLocationUpdatesAutomatically = false
    }
    
    // MARK: - permission
    
    var locationServicesStatus: LocationAuthorizationStatus {
        get {
            if CLLocationManager.locationServicesEnabled() == false {
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
    
    func requestAlwaysAuthorization() {
        self.locationManager.requestAlwaysAuthorization()
    }
    
    func requestWhenInUseAuthorization() {
        self.locationManager.requestWhenInUseAuthorization()
    }
    
    // MARK: - methods
    
    func performOneShotLocationUpdateWithDesiredAccuracy(_ desiredAccuracy: Double, completionHandler: OneShotCompletionHandler) {
    
        if self.locationServicesStatus == .allowedAlways ||
            self.locationServicesStatus == .allowedWhenInUse {
            
            let request: PositionLocationRequest = PositionLocationRequest()
            request.desiredAccuracy = desiredAccuracy
            request.expiration = PositionOneShotRequestTimeOut
            request.timeOutHandler = {
                self.processLocationRequests()
            }
            request.completionHandler = completionHandler

            if (self.locationRequests == nil) {
                self.locationRequests = []
            }
            self.locationRequests!.append(request)

            self.startLowPowerUpdating()
            self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
            self.locationManager.distanceFilter = kCLDistanceFilterNone

            if self.updatingLocation == false {
                self.startUpdating()
                
                // flag signals to turn off updating once complete
                self.updatingLocation = false
            }
            
        } else {
            DispatchQueue.main.async(execute: {
                let handler: OneShotCompletionHandler = completionHandler
                let error = NSError(domain: ErrorDomain, code: ErrorType.restricted.rawValue, userInfo: nil)
                handler(nil, error)
            })
        }

    }
    
    func startUpdating() {
        let status: LocationAuthorizationStatus = self.locationServicesStatus
        switch status {
            case .allowedAlways, .allowedWhenInUse:
                self.locationManager.startUpdatingLocation()
                self.locationManager.startMonitoringVisits()
                self.updatingLocation = true
                self.updateLocationManagerStateIfNeeded()
            default:
                break
        }
    }

    func stopUpdating() {
        let status: LocationAuthorizationStatus = self.locationServicesStatus
        switch status {
            case .allowedAlways, .allowedWhenInUse:
                self.locationManager.stopUpdatingLocation()
                self.locationManager.stopMonitoringVisits()
                self.updatingLocation = false
                self.updateLocationManagerStateIfNeeded()
            default:
                break
        }
    }
    
    func startLowPowerUpdating() {
        let status: LocationAuthorizationStatus = self.locationServicesStatus
        switch status {
            case .allowedAlways, .allowedWhenInUse:
                self.locationManager.startMonitoringSignificantLocationChanges()
                self.updatingLowPowerLocation = true
                self.updateLocationManagerStateIfNeeded()
            default:
                break
        }
    }

    func stopLowPowerUpdating() {
        let status: LocationAuthorizationStatus = self.locationServicesStatus
        switch status {
            case .allowedAlways, .allowedWhenInUse:
                self.locationManager.stopMonitoringSignificantLocationChanges()
                self.updatingLowPowerLocation = false
                self.updateLocationManagerStateIfNeeded()
            default:
                break
        }
    }
    
    // MARK - private methods
    
    internal func processLocationRequests() {
        guard self.locationRequests != nil && self.locationRequests!.count > 0 else {
            self.delegate?.positionLocationCenter(self, didUpdateTrackingLocations: self.locations)
            return
        }
        
        let completeRequests: [PositionLocationRequest] = self.locationRequests!.filter { (request) -> Bool in
            // check if a request completed, meaning expired or met horizontal accuracy
            //print("desiredAccuracy \(request.desiredAccuracy) horizontal \(self.location?.horizontalAccuracy)")
            guard request.expired == true || (self.location != nil && self.location!.horizontalAccuracy < request.desiredAccuracy) else {
                return false
            }
            return true
        }
        
        for request in completeRequests {
            if let handler = request.completionHandler {
                if request.expired == true {
                    let error: NSError = NSError(domain: ErrorDomain, code: ErrorType.timedOut.rawValue, userInfo: nil)
                    handler(nil, error)
                } else {
                    handler(self.location, nil)
                }
            }
            if let index = self.locationRequests!.index(of: request) {
                self.locationRequests!.remove(at: index)
            }
        }
        
        if self.locationRequests!.count == 0 {
            self.locationRequests = nil
            self.updateLocationManagerStateIfNeeded()
            
            if self.updatingLocation == false {
                self.stopUpdating()
            }
            
            if self.updatingLowPowerLocation == false {
                self.stopLowPowerUpdating()
            }
        }
    }
    
    internal func completeLocationRequestsWithError(_ error: Error?) {
        if let locationRequests = self.locationRequests {
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
        if let locationRequests = self.locationRequests {
            if locationRequests.count > 0 {
                if self.updatingLocation == true {
                    self.locationManager.desiredAccuracy = self.trackingDesiredAccuracyActive
                } else if self.updatingLowPowerLocation == true {
                    self.locationManager.desiredAccuracy = self.trackingDesiredAccuracyBackground
                }
                
                self.locationManager.distanceFilter = self.distanceFilter
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension PositionLocationCenter: CLLocationManagerDelegate {
    
    @objc(locationManager:didUpdateLocations:) func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.location = locations.last
        self.locations = locations
    
        // update one-shot requests
        self.processLocationRequests()
    }
    
    @objc(locationManager:didFailWithError:) func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.completeLocationRequestsWithError(error)
        self.delegate?.positionLocationCenter(self, didFailWithError: error)
    }
    
    @objc(locationManager:didChangeAuthorizationStatus:) func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
            case .denied, .restricted:
                self.completeLocationRequestsWithError(NSError(domain: ErrorDomain, code: ErrorType.restricted.rawValue, userInfo: nil))
                break
            default:
                break
        }
        self.delegate?.positionLocationCenter(self, didChangeLocationAuthorizationStatus: self.locationServicesStatus)
    }
    
    @objc(locationManager:didDetermineState:forRegion:) func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
    }
    
    @objc(locationManager:didVisit:) func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        self.delegate?.positionLocationCenter(self, didVisit: visit)
    }

    @objc(locationManager:didEnterRegion:) func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        // TODO begin optimization of current tracked fences
    }
    
    @objc(locationManager:didExitRegion:) func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        // TODO begin cycling out the current tracked fences
    }
    
    @objc(locationManager:didStartMonitoringForRegion:) func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
    }

    @objc(locationManager:monitoringDidFailForRegion:withError:) func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        self.delegate?.positionLocationCenter(self, didFailWithError: error)
    }
}

// MARK: - PositionLocationRequest

internal typealias TimeOutCompletionHandler = () -> ()

internal class PositionLocationRequest: NSObject {

    var desiredAccuracy: Double!
    var expired: Bool
    var timeOutHandler: TimeOutCompletionHandler?
    var completionHandler: OneShotCompletionHandler?

    private var expirationTimer: Timer?

    var expiration: TimeInterval! {
        didSet {
            if let timer = self.expirationTimer {
                self.expired = false
                timer.invalidate()
            }
            self.expirationTimer = Timer.scheduledTimer(timeInterval: self.expiration, target: self, selector: #selector(PositionLocationRequest.handleTimerFired(_:)), userInfo: nil, repeats: false)
        }
    }
    
    // MARK - object lifecycle
    
    override init() {
        self.expired = false
        super.init()
    }
    
    deinit {
        self.expired = true
        self.expirationTimer?.invalidate()
        self.expirationTimer = nil
        self.timeOutHandler = nil
        self.completionHandler = nil
    }

    // MARK - functions

    func cancelRequest() {
        self.expired = true
        self.expirationTimer?.invalidate()
        self.timeOutHandler = nil
        self.expirationTimer = nil
    }

    // MARK - NSTimer
    
    func handleTimerFired(_ timer: Timer) {
        DispatchQueue.main.async(execute: {
            self.expired = true
            self.expirationTimer?.invalidate()
            self.expirationTimer = nil
            
            if let timeOutHandler = self.timeOutHandler {
                timeOutHandler()
                self.timeOutHandler = nil
            }
        })
    }
}

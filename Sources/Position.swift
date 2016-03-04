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
import UIKit
import CoreLocation

// MARK: - Position Types

public enum AuthorizationStatus: Int, CustomStringConvertible {
    case NotDetermined = 0
    case NotAvailable
    case Denied
    case AllowedWhenInUse
    case AllowedAlways

    public var description: String {
        get {
            switch self {
            case NotDetermined:
                return "Not Determined"
            case NotAvailable:
                return "Not Available"
            case Denied:
                return "Denied"
            case AllowedWhenInUse:
                return "When In Use"
            case AllowedAlways:
                return "Allowed Always"
            }
        }
    }
}

public let ErrorDomain = "PositionErrorDomain"

public enum ErrorType: Int, CustomStringConvertible {
    case TimedOut = 0
    case Restricted = 1
    case Cancelled = 2
    
    public var description: String {
        get {
            switch self {
                case TimedOut:
                    return "Timed out"
                case Restricted:
                    return "Restricted"
                case Cancelled:
                    return "Cancelled"
            }
        }
    }
}

public let TimeFilterNone : NSTimeInterval = 0.0
public let TimeFilter5Minutes : NSTimeInterval = 5.0 * 60.0
public let TimeFilter10Minutes : NSTimeInterval = 10.0 * 60.0

public typealias OneShotCompletionHandler = (location: CLLocation?, error: NSError?) -> ()

public protocol PositionObserver: NSObjectProtocol {
    // permission
    func position(position: Position, didChangeLocationAuthorizationStatus status: AuthorizationStatus)
    
    // error handling
    func position(position: Position, didFailWithError error: NSError?)
    
    // location
    func position(position: Position, didUpdateOneShotLocation location: CLLocation?)
    func position(position: Position, didUpdateTrackingLocations locations: [CLLocation]?)
    func position(position: Position, didUpdateFloor floor: CLFloor)
    func position(position: Position, didVisit visit: CLVisit?)
    
    func position(position: Position, didChangeDesiredAccurary desiredAccuracy: Double)
}

// MARK: - Position

public class Position: NSObject, PositionLocationCenterDelegate {

    private var observers: NSHashTable?
    private var locationCenter: PositionLocationCenter!
    private var updatingPosition: Bool

    // MARK: - singleton

    static let sharedPosition: Position = Position()

    // MARK: - object lifecycle
    
    override init() {
        self.updatingPosition = false;
        self.adjustLocationUseWhenBackgrounded = false
        self.adjustLocationUseFromBatteryLevel = false
        super.init()
        
        locationCenter = PositionLocationCenter()
        locationCenter.delegate = self
        
        UIDevice.currentDevice().batteryMonitoringEnabled = true
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "applicationDidEnterBackground:", name: UIApplicationDidEnterBackgroundNotification, object: UIApplication.sharedApplication())
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "applicationDidBecomeActive:", name: UIApplicationDidBecomeActiveNotification, object: UIApplication.sharedApplication())
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "applicationWillResignActive:", name: UIApplicationWillResignActiveNotification, object: UIApplication.sharedApplication())

        NSNotificationCenter.defaultCenter().addObserver(self, selector: "batteryLevelChanged:", name:UIDeviceBatteryLevelDidChangeNotification, object: UIApplication.sharedApplication())
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "batteryStateChanged:", name:UIDeviceBatteryStateDidChangeNotification, object: UIApplication.sharedApplication())
    }

    // MARK: - permissions and access

    public var locationServicesStatus: AuthorizationStatus? {
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
    
    // MARK: - observers

    public func addObserver(observer: PositionObserver?) {
        if self.observers == nil {
            self.observers = NSHashTable.weakObjectsHashTable()
        }
        
        if let observers = self.observers {
            if observers.containsObject(observer) == false {
                observers.addObject(observer)
            }
        }
    }
    
    public func removeObserver(observer: PositionObserver?) {
        if let observers = self.observers {
            if observers.containsObject(observer) {
                observers.removeObject(observer)
            }
        }
    }

    // MARK: - settings

    public var adjustLocationUseWhenBackgrounded: Bool {
        didSet {
            if (self.locationCenter.updatingLowPowerLocation == true) {
                self.locationCenter.stopLowPowerUpdating()
                self.locationCenter.startUpdating()
            }
        }
    }

    public var adjustLocationUseFromBatteryLevel: Bool
    
    // MARK: - status
    
    public var updatingLocation: Bool {
        get {
            return self.locationCenter.updatingLocation == true || self.locationCenter.updatingLowPowerLocation == true
        }
    }
    
    // MARK: - positioning

    public var location: CLLocation? {
        get {
            return locationCenter?.location
        }
    }
    
    public func performOneShotLocationUpdateWithDesiredAccuracy(desiredAccuracy: Double, completionHandler: OneShotCompletionHandler) {
        self.locationCenter?.performOneShotLocationUpdateWithDesiredAccuracy(desiredAccuracy, completionHandler: completionHandler)
    }

    // MARK: - tracking

    public var trackingDesiredAccuracyWhenActive: Double!
    
    public var trackingDesiredAccuracyWhenInBackground: Double!

    public var distanceFilter: Double! {
        get {
            return self.locationCenter.distanceFilter
        }
        set {
            self.locationCenter.distanceFilter = newValue
        }
    }

    public var timeFilter: NSTimeInterval! {
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
    }

    public func stopUpdating() {
        self.locationCenter.stopUpdating()
        self.locationCenter.stopLowPowerUpdating()
        self.updatingPosition = false
    }
    
    // MARK: - private
    
    private func checkAuthorizationStatusForServices() {
        if (self.locationCenter.locationServicesStatus == .Denied ) {
            let enumerator = self.observers?.objectEnumerator()
            while let observer: PositionObserver = enumerator!.nextObject() as? PositionObserver {
                observer.position(self, didChangeLocationAuthorizationStatus: .Denied)
            }
        }
        
        // if i have time to add motion services support, that would also be added here.
    }
    
    private func updateLocationAccuracyIfNecessary() {
        if (self.adjustLocationUseFromBatteryLevel == true) {
            let currentState: UIDeviceBatteryState = UIDevice.currentDevice().batteryState
            
            switch currentState {
                case .Full, .Charging:
                    self.locationCenter.trackingDesiredAccuracyActive = kCLLocationAccuracyNearestTenMeters
                    self.locationCenter.trackingDesiredAccuracyBackground = kCLLocationAccuracyHundredMeters
                    break
                case .Unplugged, .Unknown:
                    let batteryLevel: Float = UIDevice.currentDevice().batteryLevel
                    if (batteryLevel < 0.15) {
                        self.locationCenter.trackingDesiredAccuracyActive = kCLLocationAccuracyThreeKilometers;
                        self.locationCenter.trackingDesiredAccuracyBackground = kCLLocationAccuracyThreeKilometers;
                    } else {
                        self.locationCenter.trackingDesiredAccuracyActive = kCLLocationAccuracyHundredMeters;
                        self.locationCenter.trackingDesiredAccuracyBackground = kCLLocationAccuracyKilometer;
                    }
                    break
            }
        }
    }
    
    // MARK: - PositionLocationCenterDelegate

    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didChangeLocationAuthorizationStatus status: AuthorizationStatus) {
        let enumerator = self.observers?.objectEnumerator()
        while let observer: PositionObserver = enumerator!.nextObject() as? PositionObserver {
            observer.position(self, didChangeLocationAuthorizationStatus: status)
        }
    }
    
    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didFailWithError error: NSError?) {
        let enumerator = self.observers?.objectEnumerator()
        while let observer: PositionObserver = enumerator!.nextObject() as? PositionObserver {
            observer.position(self, didFailWithError : error)
        }
    }
    
    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didUpdateOneShotLocation location: CLLocation?) {
        let enumerator = self.observers?.objectEnumerator()
        while let observer: PositionObserver = enumerator!.nextObject() as? PositionObserver {
            observer.position(self, didUpdateOneShotLocation: location)
        }
    }
    
    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didUpdateTrackingLocations locations: [CLLocation]?) {
        let enumerator = self.observers?.objectEnumerator()
        while let observer: PositionObserver = enumerator!.nextObject() as? PositionObserver {
            observer.position(self, didUpdateTrackingLocations: locations)
        }
    }
    
    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didUpdateFloor floor: CLFloor) {
        let enumerator = self.observers?.objectEnumerator()
        while let observer: PositionObserver = enumerator!.nextObject() as? PositionObserver {
            observer.position(self, didUpdateFloor: floor)
        }
    }

    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didVisit visit: CLVisit?) {
        let enumerator = self.observers?.objectEnumerator()
        while let observer: PositionObserver = enumerator!.nextObject() as? PositionObserver {
            observer.position(self, didVisit: visit)
        }
    }
    
    // MARK: - NSNotifications

    func applicationDidEnterBackground(notification: NSNotification) {
    }
    
    func applicationDidBecomeActive(notification: NSNotification) {
        self.checkAuthorizationStatusForServices()
        
        // if position is not updating, don't modify state
        if (self.updatingPosition == false) {
            return
        }
        
        // internally, locationCenter will adjust desiredaccuracy to trackingDesiredAccuracyBackground
        if (self.adjustLocationUseWhenBackgrounded == true) {
            self.locationCenter.stopLowPowerUpdating()
        }        
    }

    func applicationWillResignActive(notification: NSNotification) {
        if (self.updatingPosition == true) {
            return
        }

        if (self.adjustLocationUseWhenBackgrounded == true) {
            self.locationCenter.startLowPowerUpdating()
        }
        
        self.updateLocationAccuracyIfNecessary()
    }

    func batteryLevelChanged(notification: NSNotification) {
        let batteryLevel: Float = UIDevice.currentDevice().batteryLevel
        if (batteryLevel < 0.0) {
            return;
        }
        self.updateLocationAccuracyIfNecessary()
    }

    func batteryStateChanged(notification: NSNotification) {
        self.updateLocationAccuracyIfNecessary()
    }
}

// MARK: - PositionLocationCenter

let PositionOneShotRequestTimeOut: NSTimeInterval = 1.0 * 60.0

internal protocol PositionLocationCenterDelegate: NSObjectProtocol {
    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didChangeLocationAuthorizationStatus status: AuthorizationStatus)
    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didFailWithError error: NSError?)

    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didUpdateOneShotLocation location: CLLocation?)
    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didUpdateTrackingLocations location: [CLLocation]?)
    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didUpdateFloor floor: CLFloor)
    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didVisit visit: CLVisit?)
}

internal class PositionLocationCenter: NSObject, CLLocationManagerDelegate {

    weak var delegate: PositionLocationCenterDelegate!
    
    var distanceFilter: Double! {
        didSet {
            self.updateLocationManagerStateIfNeeded()
        }
    }
    
    var timeFilter: NSTimeInterval!
    
    var trackingDesiredAccuracyActive: Double! {
        didSet {
            self.updateLocationManagerStateIfNeeded()
        }
    }
    var trackingDesiredAccuracyBackground: Double! {
        didSet {
            self.updateLocationManagerStateIfNeeded()
        }
    }
    
    var location: CLLocation?
    var locations: [CLLocation]?
    
    private var locationManager: CLLocationManager!
    private var locationRequests: NSMutableArray?
    private var updatingLocation: Bool
    private var updatingLowPowerLocation: Bool
    
    // MARK: - object lifecycle
    
    override init() {
        self.updatingLocation = false
        self.updatingLowPowerLocation = false
        super.init()
        
        self.locationManager = CLLocationManager()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.pausesLocationUpdatesAutomatically = false
        
        self.trackingDesiredAccuracyActive = kCLLocationAccuracyHundredMeters
        self.trackingDesiredAccuracyBackground = kCLLocationAccuracyKilometer
    }
    
    // MARK: - permission
    
    var locationServicesStatus: AuthorizationStatus! {
        get {
            if CLLocationManager.locationServicesEnabled() == false {
                return AuthorizationStatus.NotAvailable
            }
            
            var status: AuthorizationStatus! = .NotDetermined
            switch CLLocationManager.authorizationStatus() {
            case .AuthorizedAlways:
                status = AuthorizationStatus.AllowedAlways
                break
            case .AuthorizedWhenInUse:
                status = AuthorizationStatus.AllowedWhenInUse
                break
            case .Denied, .Restricted:
                status = AuthorizationStatus.Denied
                break
            case .NotDetermined:
                status = AuthorizationStatus.NotDetermined
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
    
    func performOneShotLocationUpdateWithDesiredAccuracy(desiredAccuracy: Double, completionHandler: OneShotCompletionHandler) {
    
        if (self.locationServicesStatus == AuthorizationStatus.AllowedAlways ||
            self.locationServicesStatus == AuthorizationStatus.AllowedWhenInUse) {
            
            let request: PositionLocationRequest = PositionLocationRequest()
            request.desiredAccuracy = desiredAccuracy
            request.expiration = PositionOneShotRequestTimeOut;
            request.completionHandler = completionHandler;
            
            if let _: NSArray = self.locationRequests  {
            } else {
                self.locationRequests = NSMutableArray()
            }

            self.locationRequests?.addObject(request)

            self.startLowPowerUpdating()
            self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
            self.locationManager.distanceFilter = kCLDistanceFilterNone

            if (self.updatingLocation == false) {
                self.startUpdating()
                
                // flag signals to turn off updating once complete
                self.updatingLocation = false
            }
            
        } else {
            dispatch_async(dispatch_get_main_queue(), {
                if let handler: OneShotCompletionHandler = completionHandler {
                    let error: NSError! = NSError.init(domain: ErrorDomain, code: ErrorType.Restricted.rawValue, userInfo: nil)
                    handler(location: nil, error: error)
                }
            });
        }

    }
    
    func startUpdating() {
        let status: AuthorizationStatus = self.locationServicesStatus
        switch status {
        case .AllowedAlways, .AllowedWhenInUse:
            self.locationManager.startUpdatingLocation()
            self.locationManager.startMonitoringVisits()
            self.updatingLocation = true
            self.updateLocationManagerStateIfNeeded()
            break
        default:
            break
        }
    }

    func stopUpdating() {
        let status: AuthorizationStatus = self.locationServicesStatus
        switch status {
        case .AllowedAlways, .AllowedWhenInUse:
            self.locationManager.stopUpdatingLocation()
            self.locationManager.stopMonitoringVisits()
            self.updatingLocation = false
            self.updateLocationManagerStateIfNeeded()
            break
        default:
            break
        }
    }
    
    func startLowPowerUpdating() {
        let status: AuthorizationStatus = self.locationServicesStatus
        switch status {
        case .AllowedAlways, .AllowedWhenInUse:
            self.locationManager.startMonitoringSignificantLocationChanges()
            self.updatingLowPowerLocation = true
            self.updateLocationManagerStateIfNeeded()
            break
        default:
            break
        }
    }

    func stopLowPowerUpdating() {
        let status: AuthorizationStatus = self.locationServicesStatus
        switch status {
        case .AllowedAlways, .AllowedWhenInUse:
            self.locationManager.stopMonitoringSignificantLocationChanges()
            self.updatingLowPowerLocation = false
            self.updateLocationManagerStateIfNeeded()
            break
        default:
            break
        }
    }
    
    // MARK - private methods
    
    private func processLocationRequests() {
    
        if let locationRequests = self.locationRequests {
            
            let completeRequests: NSMutableArray! = NSMutableArray()
            
            for request in locationRequests {
                // check for expired requests
                if (request as! PositionLocationRequest).expired == true {
                    completeRequests.addObject(request)
                    continue
                }
                
                // check if desiredAccuracy was met for the request
                if let location = self.location {
                    if location.horizontalAccuracy < (request as! PositionLocationRequest).desiredAccuracy {
                        completeRequests.addObject(request)
                        continue
                    }
                }
            }
            
            for request in completeRequests {
                if let handler = (request as! PositionLocationRequest).completionHandler {
                    if (request as! PositionLocationRequest).expired == true {
                        let error: NSError! = NSError.init(domain: ErrorDomain, code: ErrorType.TimedOut.rawValue, userInfo: nil)
                        handler(location: nil, error: error)
                    } else {
                        handler(location: self.location, error: nil)
                    }
                }
                locationRequests.removeObject(request)
            }

            if locationRequests.count == 0 {
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
        
        if let _ = self.locationRequests {
        } else {
            self.delegate.positionLocationCenter(self, didUpdateTrackingLocations: self.locations)
        }
    }
    
    private func completeLocationRequestsWithError(error: NSError) {
        if let requests = self.locationRequests {
            for locationRequest in requests {
                locationRequest.cancelRequest()
                if let resultingError: NSError? = error {
                    if let handler = (locationRequest as! PositionLocationRequest).completionHandler {
                        handler(location: nil, error: resultingError)
                    }
                } else {
                    if let handler = (locationRequest as! PositionLocationRequest).completionHandler {
                        handler(location: nil, error: NSError(domain: ErrorDomain, code: ErrorType.Cancelled.rawValue, userInfo: nil))
                    }
                }
            }
        }
    }

    private func updateLocationManagerStateIfNeeded() {
        // when not processing requests, set desired accuracy appropriately
        if let requests = self.locationRequests {
            if requests.count > 0 {
                if self.updatingLocation == true {
                    self.locationManager.desiredAccuracy = trackingDesiredAccuracyActive
                } else if self.updatingLowPowerLocation == true {
                    self.locationManager.desiredAccuracy = trackingDesiredAccuracyBackground
                }
                
                self.locationManager.distanceFilter = self.distanceFilter
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.location = locations.last
        self.locations = locations
    
        // update one-shot requests
        self.processLocationRequests()
    }
    
    func locationManager(manager: CLLocationManager, didFailWithError error: NSError) {
        self.completeLocationRequestsWithError(error)
        self.delegate.positionLocationCenter(self, didFailWithError: error)
    }
    
    func locationManager(manager: CLLocationManager, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        switch status {
            case .Denied, .Restricted:
                self.completeLocationRequestsWithError(NSError(domain: ErrorDomain, code: ErrorType.Restricted.rawValue, userInfo: nil))
                break
            default:
                break
        }
        self.delegate.positionLocationCenter(self, didChangeLocationAuthorizationStatus: self.locationServicesStatus)
    }
    
    func locationManager(manager: CLLocationManager, didDetermineState state: CLRegionState, forRegion region: CLRegion) {
    }
    
    func locationManager(manager: CLLocationManager, didVisit visit: CLVisit) {
        self.delegate.positionLocationCenter(self, didVisit: visit)
    }

    func locationManager(manager: CLLocationManager, didEnterRegion region: CLRegion) {
        // TODO begin optimization of current tracked fences
    }
    
    func locationManager(manager: CLLocationManager, didExitRegion region: CLRegion) {
        // TODO begin cycling out the current tracked fences
    }
    
    func locationManager(manager: CLLocationManager, didStartMonitoringForRegion region: CLRegion) {
    }

    func locationManager(manager: CLLocationManager, monitoringDidFailForRegion region: CLRegion?, withError error: NSError) {
        self.delegate.positionLocationCenter(self, didFailWithError: error)
    }
}

// MARK: - PositionLocationRequest

internal class PositionLocationRequest: NSObject {

    var desiredAccuracy: Double!
    var expired: Bool
    var completionHandler: OneShotCompletionHandler?

    private var expirationTimer: NSTimer?

    var expiration: NSTimeInterval! {
        didSet {
            if self.expirationTimer != nil {
                self.expired = false
                self.expirationTimer!.invalidate()
            }
            self.expirationTimer = NSTimer.scheduledTimerWithTimeInterval(self.expiration, target: self, selector: "handleTimerFired:", userInfo: nil, repeats: false)
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
        self.expirationTimer = nil;
        self.completionHandler = nil;
    }

    // MARK - methods

    func cancelRequest() {
        self.expired = true
        self.expirationTimer?.invalidate()
        self.expirationTimer = nil;
    }

    // MARK - NSTimer
    
    func handleTimerFired(timer: NSTimer) {
        self.expired = true
        self.expirationTimer?.invalidate()
        self.expirationTimer = nil;
    }

}

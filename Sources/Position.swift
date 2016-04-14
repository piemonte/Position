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
import CoreMotion

// MARK: - Position Types

public enum LocationAuthorizationStatus: CustomStringConvertible {
    case NotDetermined
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

public enum MotionAuthorizationStatus: CustomStringConvertible {
	case NotDetermined
	case NotAvailable
	case Allowed
	
	public var description: String {
		get {
			switch self {
			case NotDetermined:
				return "Not Determined"
			case NotAvailable:
				return "Not Available"
			case Allowed:
				return "Allowed"
			}
		}
	}
}

public enum MotionActivityType: CustomStringConvertible {
	case Unknown
	case Walking
	case Running
	case Automotive
	case Cycling
	
	init(activity: CMMotionActivity) {
		if activity.walking {
			self = .Walking
		} else if activity.running {
			self = .Running
		} else if activity.automotive {
			self = .Automotive
		} else if activity.cycling {
			self = .Cycling
		} else {
			self = .Unknown
		}
	}
	
	public var description: String {
		get {
			switch self {
                case Unknown:
                    return "Unknown"
                case Walking:
                    return "Walking"
                case Running:
                    return "Running"
                case Automotive:
                    return "Automotive"
                case Cycling:
                    return "Cycling"
			}
		}
	}
	
	public var locationActivityType: CLActivityType {
		switch self {
		case .Automotive:
			return .AutomotiveNavigation
		case .Walking, .Running, .Cycling:
			return .Fitness
		default:
			return .Other
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
    func position(position: Position, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus)
	func position(position: Position, didChangeMotionAuthorizationStatus status: MotionAuthorizationStatus)
    
    // error handling
    func position(position: Position, didFailWithError error: NSError?)
    
    // location
    func position(position: Position, didUpdateOneShotLocation location: CLLocation?)
    func position(position: Position, didUpdateTrackingLocations locations: [CLLocation]?)
    func position(position: Position, didUpdateFloor floor: CLFloor)
    func position(position: Position, didVisit visit: CLVisit?)
    
    func position(position: Position, didChangeDesiredAccurary desiredAccuracy: Double)
	
	// motion
	func position(position: Position, didChangeActivity activity: MotionActivityType)
}

// MARK: - Position

public class Position: NSObject {

    private var observers: NSHashTable?
	
    // location types
    private let locationCenter: PositionLocationCenter
    private var updatingPosition: Bool
	
    // motion types
	private let activityManager: CMMotionActivityManager
	private let activityQueue: NSOperationQueue
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
		self.activityQueue = NSOperationQueue()
		self.motionActivityStatus = CMMotionActivityManager.isActivityAvailable() ? .NotDetermined : .NotAvailable
		self.lastActivity = .Unknown
				
        super.init()
		
        locationCenter.delegate = self
        
        UIDevice.currentDevice().batteryMonitoringEnabled = true
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(UIApplicationDelegate.applicationDidEnterBackground(_:)), name: UIApplicationDidEnterBackgroundNotification, object: UIApplication.sharedApplication())
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(UIApplicationDelegate.applicationDidBecomeActive(_:)), name: UIApplicationDidBecomeActiveNotification, object: UIApplication.sharedApplication())
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(UIApplicationDelegate.applicationWillResignActive(_:)), name: UIApplicationWillResignActiveNotification, object: UIApplication.sharedApplication())

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(Position.batteryLevelChanged(_:)), name:UIDeviceBatteryLevelDidChangeNotification, object: UIApplication.sharedApplication())
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(Position.batteryStateChanged(_:)), name:UIDeviceBatteryStateDidChangeNotification, object: UIApplication.sharedApplication())
    }

    // MARK: - permissions and access

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
        guard self.motionActivityStatus == .Allowed else {
            self.activityManager.startActivityUpdatesToQueue(NSOperationQueue()) { (activity) in
                self.activityManager.stopActivityUpdates()
                
                let enumerator = self.observers?.objectEnumerator()
                while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
                    self.motionActivityStatus = .Allowed
                    observer.position(self, didChangeMotionAuthorizationStatus: self.motionActivityStatus)
                }
            }
            return;
        }
	}
	
    // MARK: - observers

    public func addObserver(observer: PositionObserver?) {
        if self.observers == nil {
            self.observers = NSHashTable.weakObjectsHashTable()
        }
         
        if self.observers?.containsObject(observer) == false {
            self.observers?.addObject(observer)
        }
    }
	
    public func removeObserver(observer: PositionObserver?) {
		if self.observers?.containsObject(observer) == true {
			self.observers?.removeObject(observer)
		}
        if self.observers?.count == 0 {
            self.observers = nil;
        }
    }

    // MARK: - settings

    public var adjustLocationUseWhenBackgrounded: Bool {
        didSet {
            if self.locationCenter.updatingLowPowerLocation == true {
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
            return locationCenter.location
        }
    }
    
    public func performOneShotLocationUpdateWithDesiredAccuracy(desiredAccuracy: Double, completionHandler: OneShotCompletionHandler) {
        self.locationCenter.performOneShotLocationUpdateWithDesiredAccuracy(desiredAccuracy, completionHandler: completionHandler)
    }

    // MARK: - location tracking

    public var trackingDesiredAccuracyWhenActive: Double!
    
    public var trackingDesiredAccuracyWhenInBackground: Double!

    public var distanceFilter: Double {
        get {
            return self.locationCenter.distanceFilter
        }
        set {
            self.locationCenter.distanceFilter = newValue
        }
    }

    public var timeFilter: NSTimeInterval {
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
		
		if self.motionActivityStatus == .Allowed {
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
			if self.motionActivityStatus == .Allowed && self.adjustLocationUseFromActivity {
				self.startUpdatingActivity()
			}
		}
	}
	
	public var adjustLocationUseFromActivity: Bool {
		didSet {
			if self.motionActivityStatus == .Allowed {
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
		self.activityManager.startActivityUpdatesToQueue(activityQueue) { (activity) in
			dispatch_async(dispatch_get_main_queue(), {
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
	
    // MARK: - private
    
    private func checkAuthorizationStatusForServices() {
        if self.locationCenter.locationServicesStatus == .Denied {
            let enumerator = self.observers?.objectEnumerator()
            while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
                observer.position(self, didChangeLocationAuthorizationStatus: .Denied)
            }
        }
		
		if self.motionActivityStatus == .NotDetermined {
			self.activityManager.startActivityUpdatesToQueue(NSOperationQueue()) { (activity) in
				self.activityManager.stopActivityUpdates()
				self.motionActivityStatus = .Allowed
				
				let enumerator = self.observers?.objectEnumerator()
				while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
					observer.position(self, didChangeMotionAuthorizationStatus: self.motionActivityStatus)
				}
			}
		}
    }
    
    private func updateLocationAccuracyIfNecessary() {
        if self.adjustLocationUseFromBatteryLevel == true {
            let currentState: UIDeviceBatteryState = UIDevice.currentDevice().batteryState
            
            switch currentState {
                case .Full, .Charging:
                    self.locationCenter.trackingDesiredAccuracyActive = kCLLocationAccuracyNearestTenMeters
                    self.locationCenter.trackingDesiredAccuracyBackground = kCLLocationAccuracyHundredMeters
				
					if self.adjustLocationUseFromActivity == true {
						switch lastActivity {
							case .Automotive, .Cycling:
								self.locationCenter.trackingDesiredAccuracyActive = kCLLocationAccuracyBestForNavigation
								break
							default:
								break
						}
					}
					
                case .Unplugged, .Unknown:
                    let batteryLevel: Float = UIDevice.currentDevice().batteryLevel
                    if batteryLevel < 0.15 {
                        self.locationCenter.trackingDesiredAccuracyActive = kCLLocationAccuracyThreeKilometers
                        self.locationCenter.trackingDesiredAccuracyBackground = kCLLocationAccuracyThreeKilometers
                    } else {
						self.locationCenter.trackingDesiredAccuracyActive = kCLLocationAccuracyHundredMeters
						self.locationCenter.trackingDesiredAccuracyBackground = kCLLocationAccuracyKilometer
						
						if self.adjustLocationUseFromActivity == true {
							switch lastActivity {
								case .Walking:
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
				case .Automotive, .Cycling:
					self.locationCenter.trackingDesiredAccuracyActive = kCLLocationAccuracyHundredMeters
					self.locationCenter.trackingDesiredAccuracyBackground = kCLLocationAccuracyKilometer
					break
				case .Running, .Walking:
					self.locationCenter.trackingDesiredAccuracyActive = kCLLocationAccuracyNearestTenMeters
					self.locationCenter.trackingDesiredAccuracyBackground = kCLLocationAccuracyHundredMeters
					break
				default:
					break
			}
		}
    }

    // MARK: - NSNotifications

    func applicationDidEnterBackground(notification: NSNotification) {
    }
    
    func applicationDidBecomeActive(notification: NSNotification) {
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

    func applicationWillResignActive(notification: NSNotification) {
        if self.updatingPosition == true {
            return
        }

        if self.adjustLocationUseWhenBackgrounded == true {
            self.locationCenter.startLowPowerUpdating()
        }
        
        self.updateLocationAccuracyIfNecessary()
    }

    func batteryLevelChanged(notification: NSNotification) {
        let batteryLevel: Float = UIDevice.currentDevice().batteryLevel
        if batteryLevel < 0.0 {
            return
        }
        self.updateLocationAccuracyIfNecessary()
    }

    func batteryStateChanged(notification: NSNotification) {
        self.updateLocationAccuracyIfNecessary()
    }
    
}

// MARK: - PositionLocationCenterDelegate

extension Position: PositionLocationCenterDelegate {

    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus) {
        let enumerator = self.observers?.objectEnumerator()
        while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
            observer.position(self, didChangeLocationAuthorizationStatus: status)
        }
    }
    
    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didFailWithError error: NSError?) {
        let enumerator = self.observers?.objectEnumerator()
        while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
            observer.position(self, didFailWithError : error)
        }
    }
    
    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didUpdateOneShotLocation location: CLLocation?) {
        let enumerator = self.observers?.objectEnumerator()
        while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
            observer.position(self, didUpdateOneShotLocation: location)
        }
    }
    
    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didUpdateTrackingLocations locations: [CLLocation]?) {
        let enumerator = self.observers?.objectEnumerator()
        while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
            observer.position(self, didUpdateTrackingLocations: locations)
        }
    }
    
    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didUpdateFloor floor: CLFloor) {
        let enumerator = self.observers?.objectEnumerator()
        while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
            observer.position(self, didUpdateFloor: floor)
        }
    }

    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didVisit visit: CLVisit?) {
        let enumerator = self.observers?.objectEnumerator()
        while let observer: PositionObserver = enumerator?.nextObject() as? PositionObserver {
            observer.position(self, didVisit: visit)
        }
    }
}

// MARK: - PositionLocationCenter

let PositionOneShotRequestTimeOut: NSTimeInterval = 0.5 * 60.0

internal protocol PositionLocationCenterDelegate: NSObjectProtocol {
    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus)
    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didFailWithError error: NSError?)

    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didUpdateOneShotLocation location: CLLocation?)
    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didUpdateTrackingLocations location: [CLLocation]?)
    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didUpdateFloor floor: CLFloor)
    func positionLocationCenter(positionLocationCenter: PositionLocationCenter, didVisit visit: CLVisit?)
}

internal class PositionLocationCenter: NSObject {

    weak var delegate: PositionLocationCenterDelegate?
    
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
	
	var activityType: MotionActivityType {
		didSet {
			locationManager.activityType = activityType.locationActivityType
		}
	}
    
    var location: CLLocation?
    var locations: [CLLocation]?
    
    private var locationManager: CLLocationManager
    private var locationRequests: [PositionLocationRequest]?
    private var updatingLocation: Bool
    private var updatingLowPowerLocation: Bool
    
    // MARK: - object lifecycle
    
    override init() {
		self.locationManager = CLLocationManager()
        self.updatingLocation = false
        self.updatingLowPowerLocation = false
		self.activityType = .Unknown
        super.init()
		
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.pausesLocationUpdatesAutomatically = false
        
        self.trackingDesiredAccuracyActive = kCLLocationAccuracyHundredMeters
        self.trackingDesiredAccuracyBackground = kCLLocationAccuracyKilometer
    }
    
    // MARK: - permission
    
    var locationServicesStatus: LocationAuthorizationStatus {
        get {
            if CLLocationManager.locationServicesEnabled() == false {
                return .NotAvailable
            }
            
            var status: LocationAuthorizationStatus = .NotDetermined
            switch CLLocationManager.authorizationStatus() {
                case .AuthorizedAlways:
                    status = .AllowedAlways
                    break
                case .AuthorizedWhenInUse:
                    status = .AllowedWhenInUse
                    break
                case .Denied, .Restricted:
                    status = .Denied
                    break
                case .NotDetermined:
                    status = .NotDetermined
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
    
        if self.locationServicesStatus == .AllowedAlways ||
            self.locationServicesStatus == .AllowedWhenInUse {
            
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
            dispatch_async(dispatch_get_main_queue(), {
				guard let handler: OneShotCompletionHandler = completionHandler else { return }
				let error: NSError = NSError(domain: ErrorDomain, code: ErrorType.Restricted.rawValue, userInfo: nil)
				handler(location: nil, error: error)
            })
        }

    }
    
    func startUpdating() {
        let status: LocationAuthorizationStatus = self.locationServicesStatus
        switch status {
            case .AllowedAlways, .AllowedWhenInUse:
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
            case .AllowedAlways, .AllowedWhenInUse:
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
            case .AllowedAlways, .AllowedWhenInUse:
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
            case .AllowedAlways, .AllowedWhenInUse:
                self.locationManager.stopMonitoringSignificantLocationChanges()
                self.updatingLowPowerLocation = false
                self.updateLocationManagerStateIfNeeded()
            default:
                break
        }
    }
    
    // MARK - private methods
    
    private func processLocationRequests() {
        guard self.locationRequests != nil && self.locationRequests?.count > 0 else {
            self.delegate?.positionLocationCenter(self, didUpdateTrackingLocations: self.locations)
			return
        }
		
		let completeRequests: [PositionLocationRequest] = self.locationRequests!.filter { (request) -> Bool in
            // check if a request completed, meaning expired or met horizontal accuracy
            //print("desiredAccuracy \(request.desiredAccuracy) horizontal \(self.location?.horizontalAccuracy)")
            guard request.expired == true || self.location?.horizontalAccuracy < request.desiredAccuracy else {
                return false
            }
            return true
		}
        
		for request in completeRequests {
			if let handler = request.completionHandler {
				if request.expired == true {
					let error: NSError = NSError(domain: ErrorDomain, code: ErrorType.TimedOut.rawValue, userInfo: nil)
					handler(location: nil, error: error)
				} else {
					handler(location: self.location, error: nil)
				}
			}
			if let index = self.locationRequests!.indexOf(request) {
				self.locationRequests!.removeAtIndex(index)
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
	
    private func completeLocationRequestsWithError(error: NSError) {
        if let locationRequests = self.locationRequests {
            for locationRequest in locationRequests {
                locationRequest.cancelRequest()
                guard let handler = locationRequest.completionHandler else { continue }
                if let resultingError: NSError? = error {
                    handler(location: nil, error: resultingError)
                } else {
                    handler(location: nil, error: NSError(domain: ErrorDomain, code: ErrorType.Cancelled.rawValue, userInfo: nil))
                }
            }
        }
    }

    private func updateLocationManagerStateIfNeeded() {
        // when not processing requests, set desired accuracy appropriately
        if let locationRequests = self.locationRequests {
            if locationRequests.count > 0 {
                if self.updatingLocation == true {
                    self.locationManager.desiredAccuracy = trackingDesiredAccuracyActive
                } else if self.updatingLowPowerLocation == true {
                    self.locationManager.desiredAccuracy = trackingDesiredAccuracyBackground
                }
                
                self.locationManager.distanceFilter = self.distanceFilter
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension PositionLocationCenter: CLLocationManagerDelegate {
	
    func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.location = locations.last
        self.locations = locations
    
        // update one-shot requests
        self.processLocationRequests()
    }
    
    func locationManager(manager: CLLocationManager, didFailWithError error: NSError) {
        self.completeLocationRequestsWithError(error)
        self.delegate?.positionLocationCenter(self, didFailWithError: error)
    }
    
    func locationManager(manager: CLLocationManager, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        switch status {
            case .Denied, .Restricted:
                self.completeLocationRequestsWithError(NSError(domain: ErrorDomain, code: ErrorType.Restricted.rawValue, userInfo: nil))
                break
            default:
                break
        }
        self.delegate?.positionLocationCenter(self, didChangeLocationAuthorizationStatus: self.locationServicesStatus)
    }
    
    func locationManager(manager: CLLocationManager, didDetermineState state: CLRegionState, forRegion region: CLRegion) {
    }
    
    func locationManager(manager: CLLocationManager, didVisit visit: CLVisit) {
        self.delegate?.positionLocationCenter(self, didVisit: visit)
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

    private var expirationTimer: NSTimer?

    var expiration: NSTimeInterval! {
        didSet {
            if let timer = self.expirationTimer {
                self.expired = false
                timer.invalidate()
            }
            self.expirationTimer = NSTimer.scheduledTimerWithTimeInterval(self.expiration, target: self, selector: #selector(PositionLocationRequest.handleTimerFired(_:)), userInfo: nil, repeats: false)
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

    // MARK - methods

    func cancelRequest() {
        self.expired = true
        self.expirationTimer?.invalidate()
        self.timeOutHandler = nil
        self.expirationTimer = nil
    }

    // MARK - NSTimer
    
    func handleTimerFired(timer: NSTimer) {
        dispatch_async(dispatch_get_main_queue(), {
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

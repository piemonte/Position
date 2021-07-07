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

// MARK: -
// MARK: - Internal

// MARK: - DeviceLocationManagerDelegate

internal protocol DeviceLocationManagerDelegate: AnyObject {
    func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didChangeLocationAuthorizationStatus status: Position.LocationAuthorizationStatus)
    func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didFailWithError error: Error?)

    func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didUpdateOneShotLocation location: CLLocation?)
    func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didUpdateTrackingLocations location: [CLLocation]?)
    func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didUpdateHeading newHeading: CLHeading)

    // extras
    func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didUpdateFloor floor: CLFloor)
    func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didVisit visit: CLVisit?)
}

// MARK: - DeviceLocationManager

/// Internal location manager used by Position
internal class DeviceLocationManager: NSObject {

    // MARK: - types

    internal static let OneShotRequestDefaultTimeOut: TimeInterval = 0.5 * 60.0
    internal static let RequestQueueSpecificKey = DispatchSpecificKey<()>()

    // MARK: - properties

    internal weak var delegate: DeviceLocationManagerDelegate?

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

    internal var heading: CLHeading? {
        _locationManager.heading
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
        _requestQueue = DispatchQueue(label: "DeviceLocationManagerRequestQueue",
                                      autoreleaseFrequency: .workItem,
                                      target: DispatchQueue.global())
        _requestQueue.setSpecific(key: DeviceLocationManager.RequestQueueSpecificKey, value: ())

        super.init()

        _locationManager.delegate = self
        _locationManager.desiredAccuracy = kCLLocationAccuracyBest
        _locationManager.pausesLocationUpdatesAutomatically = false
        if CLLocationManager.backgroundCapabilitiesEnabled {
            self._locationManager.allowsBackgroundLocationUpdates = true
        }
    }
}

// MARK: - permissions

extension DeviceLocationManager {

    internal var locationServicesStatus: Position.LocationAuthorizationStatus {
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

    @available(iOS 14, *)
    internal var locationAccuracyAuthorizationStatus: Position.LocationAccuracyAuthorizationStatus {
        get {
            switch _locationManager.accuracyAuthorization {
            case .fullAccuracy:
                return .fullAccuracy
            case .reducedAccuracy:
                return .reducedAccuracy
            @unknown default:
                return .reducedAccuracy
            }
        }
    }

    internal func requestAlwaysAuthorization() {
        _locationManager.requestAlwaysAuthorization()
    }

    internal func requestWhenInUseAuthorization() {
        _locationManager.requestWhenInUseAuthorization()
    }

    @available(iOS 14, *)
    internal func requestAccuracyAuthorization(_ completionHandler: ((Bool) -> Void)? = nil) {
        guard _locationManager.accuracyAuthorization != .fullAccuracy else {
            DispatchQueue.main.async {
                completionHandler?(true)
            }
            return
        }

        // Add the purpose key to your app's Info.plist to provide users with a purpose of your request.
        _locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "FullAccuracyPurpose") { [weak self] (error) in
            guard let self = self else {
                DispatchQueue.main.async {
                    completionHandler?(false)
                }
                return
            }
            self._locationManager.accuracyAuthorization == .fullAccuracy ? completionHandler?(true) : completionHandler?(false)
        }
    }

}

// MARK: - location services

extension DeviceLocationManager {

    internal func performOneShotLocationUpdate(withDesiredAccuracy desiredAccuracy: Double, completionHandler: Position.OneShotCompletionHandler? = nil) {
        switch locationServicesStatus {
        case .allowedAlways, .allowedWhenInUse, .notDetermined:
            _requestQueue.async {
                let request = PositionLocationRequest()
                request.desiredAccuracy = desiredAccuracy
                request.lifespan = DeviceLocationManager.OneShotRequestDefaultTimeOut
                request.timeOutHandler = { [weak self] in
                    guard let self = self else { return }
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
        default:
            DispatchQueue.main.async {
                completionHandler?(.failure(Position.ErrorType.restricted))
            }
        }
    }

    internal func startUpdating() {
        switch self.locationServicesStatus {
            case .allowedAlways, .allowedWhenInUse:
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
        let status: Position.LocationAuthorizationStatus = self.locationServicesStatus
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
        let status: Position.LocationAuthorizationStatus = self.locationServicesStatus
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

extension DeviceLocationManager {

    internal func startUpdatingHeading() {
        _locationManager.startUpdatingHeading()
    }

    internal func stopUpdatingHeading() {
        _locationManager.stopUpdatingHeading()
    }


}

// MARK: -

extension DeviceLocationManager {

    // only called from the request queue
    internal func processLocationRequests() {
        guard self._locationRequests.count > 0 else {
            DispatchQueue.main.async {
                self.delegate?.deviceLocationManager(self, didUpdateTrackingLocations: self._locations)
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

            DispatchQueue.main.async {
                if request.isExpired {
                    request.completionHandler?(.failure(Position.ErrorType.timedOut))
                } else {
                    if let location = self._locations?.first {
                        request.completionHandler?(.success(location))
                    } else {
                        request.completionHandler?(.failure(Position.ErrorType.timedOut))
                    }
                }
            }
        }

        let pendingRequests: [PositionLocationRequest] = _locationRequests.filter { request -> Bool in
            request.isCompleted == false
        }
        _locationRequests = pendingRequests

        if _locationRequests.isEmpty {
            updateLocationManagerStateIfNeeded()

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

            DispatchQueue.main.async {
                handler(.failure(error ?? Position.ErrorType.cancelled))
            }
        }
    }

    internal func updateLocationManagerStateIfNeeded() {
        // when not processing requests, set desired accuracy appropriately
        if _locationRequests.count > 0 {
            if isUpdatingLocation == true {
                _locationManager.desiredAccuracy = trackingDesiredAccuracyActive
            } else if isUpdatingLowPowerLocation == true {
                _locationManager.desiredAccuracy = trackingDesiredAccuracyBackground
            }

            _locationManager.distanceFilter = distanceFilter
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension DeviceLocationManager: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        _requestQueue.async { [weak self] in
            guard let self = self else { return }
            // update last location
            self._locations = locations
            // update one-shot requests
            self.processLocationRequests()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        delegate?.deviceLocationManager(self, didUpdateHeading: newHeading)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        _requestQueue.async { [weak self] in
            guard let self = self else { return }
            self.completeLocationRequests(withError: error)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.deviceLocationManager(self, didFailWithError: error)
            }
        }
    }

    @available(iOS 14, *)
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        _requestQueue.async { [weak self] in
            guard let self = self else { return }
            switch manager.authorizationStatus {
            case .denied, .restricted:
                self.completeLocationRequests(withError: Position.ErrorType.restricted)
            default: break
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.deviceLocationManager(self, didChangeLocationAuthorizationStatus: self.locationServicesStatus)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        _requestQueue.async { [weak self] in
            guard let self = self else { return }
            switch status {
            case .denied, .restricted:
                self.completeLocationRequests(withError: Position.ErrorType.restricted)
            default: break
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.deviceLocationManager(self, didChangeLocationAuthorizationStatus: self.locationServicesStatus)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        delegate?.deviceLocationManager(self, didVisit: visit)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    }

    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        delegate?.deviceLocationManager(self, didFailWithError: error)
    }

}

// MARK: - PositionLocationRequest

internal class PositionLocationRequest {

    // MARK: - types

    internal typealias TimeOutCompletionHandler = () -> Void

    // MARK: - properties

    internal var desiredAccuracy: Double = kCLLocationAccuracyBest
    internal var lifespan: TimeInterval = DeviceLocationManager.OneShotRequestDefaultTimeOut {
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
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

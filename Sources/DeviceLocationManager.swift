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
@preconcurrency import CoreLocation

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
internal class DeviceLocationManager: NSObject, @unchecked Sendable {

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
    internal let _requestManager = LocationRequestManager()
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
        }
    }

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

    internal func requestAccuracyAuthorization(_ completionHandler: (@Sendable (Bool) -> Void)? = nil) {
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
                guard let completionHandler = completionHandler else { return }
                
                let request = PositionLocationRequest(
                    desiredAccuracy: desiredAccuracy,
                    completionHandler: completionHandler
                )
                
                Task {
                    await self._requestManager.addRequest(request) { [weak self] in
                        guard let self = self else { return }
                        self.processLocationRequests()
                    }
                }

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
    
    /// Swift 6-style async version of performOneShotLocationUpdate
    @available(iOS 15.0, *)
    internal func performOneShotLocationUpdate(withDesiredAccuracy desiredAccuracy: Double) async throws -> CLLocation {
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
        #if os(iOS)
        _locationManager.startUpdatingHeading()
        #endif
    }

    internal func stopUpdatingHeading() {
        #if os(iOS)
        _locationManager.stopUpdatingHeading()
        #endif
    }


}

// MARK: -

extension DeviceLocationManager {

    // only called from the request queue
    internal func processLocationRequests() {
        Task {
            let requests = await _requestManager.getAllRequests()
            guard !requests.isEmpty else {
                DispatchQueue.main.async {
                    self.delegate?.deviceLocationManager(self, didUpdateTrackingLocations: self._locations)
                }
                return
            }

            let completedRequests = await _requestManager.processCompletedRequests(with: self._locations?.first)
            
            for (_, handler) in completedRequests {
                DispatchQueue.main.async {
                    if let location = self._locations?.first, location.horizontalAccuracy > 0 {
                        handler(.success(location))
                    } else {
                        handler(.failure(Position.ErrorType.timedOut))
                    }
                }
            }

            let remainingRequests = await _requestManager.getAllRequests()
            if remainingRequests.isEmpty {
                updateLocationManagerStateIfNeeded()

                if isUpdatingLocation == false {
                    stopUpdating()
                }

                if isUpdatingLowPowerLocation == false {
                    stopLowPowerUpdating()
                }
            }
        }
    }

    internal func completeLocationRequests(withError error: Error?) {
        Task {
            let handlers = await _requestManager.cancelAllRequests()
            for handler in handlers {
                DispatchQueue.main.async {
                    handler(.failure(error ?? Position.ErrorType.cancelled))
                }
            }
        }
    }

    internal func updateLocationManagerStateIfNeeded() {
        Task {
            let requests = await _requestManager.getAllRequests()
            // when not processing requests, set desired accuracy appropriately
            if !requests.isEmpty {
                if isUpdatingLocation == true {
                    _locationManager.desiredAccuracy = trackingDesiredAccuracyActive
                } else if isUpdatingLowPowerLocation == true {
                    _locationManager.desiredAccuracy = trackingDesiredAccuracyBackground
                }

                _locationManager.distanceFilter = distanceFilter
            }
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

    #if os(iOS)
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        delegate?.deviceLocationManager(self, didUpdateHeading: newHeading)
    }
    #endif

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

/// A value type representing a location request
internal struct PositionLocationRequest: Sendable {
    let id = UUID()
    let desiredAccuracy: Double
    let lifespan: TimeInterval
    let startTime = Date()
    let completionHandler: @Sendable (Swift.Result<CLLocation, Error>) -> Void
    
    var isExpired: Bool {
        Date().timeIntervalSince(startTime) > lifespan
    }
    
    init(desiredAccuracy: Double = kCLLocationAccuracyBest,
         lifespan: TimeInterval = DeviceLocationManager.OneShotRequestDefaultTimeOut,
         completionHandler: @escaping @Sendable (Swift.Result<CLLocation, Error>) -> Void) {
        self.desiredAccuracy = desiredAccuracy
        self.lifespan = lifespan
        self.completionHandler = completionHandler
    }
}

// MARK: - LocationRequestManager

/// Actor that manages location requests in a thread-safe manner
internal actor LocationRequestManager {
    private var requests: [UUID: PositionLocationRequest] = [:]
    private var timers: [UUID: Timer] = [:]
    
    func addRequest(_ request: PositionLocationRequest, timeoutHandler: @escaping @Sendable () -> Void) {
        requests[request.id] = request
        
        // Schedule timeout
        let timer = Timer.scheduledTimer(withTimeInterval: request.lifespan, repeats: false) { _ in
            Task {
                await self.handleTimeout(for: request.id, handler: timeoutHandler)
            }
        }
        timers[request.id] = timer
    }
    
    func removeRequest(_ id: UUID) {
        requests.removeValue(forKey: id)
        timers[id]?.invalidate()
        timers.removeValue(forKey: id)
    }
    
    func getAllRequests() -> [PositionLocationRequest] {
        Array(requests.values)
    }
    
    func processCompletedRequests(with location: CLLocation?) -> [(UUID, @Sendable (Swift.Result<CLLocation, Error>) -> Void)] {
        var completedRequests: [(UUID, @Sendable (Swift.Result<CLLocation, Error>) -> Void)] = []
        
        for (id, request) in requests {
            if request.isExpired {
                completedRequests.append((id, request.completionHandler))
            } else if let location = location, location.horizontalAccuracy < request.desiredAccuracy {
                completedRequests.append((id, request.completionHandler))
            }
        }
        
        // Remove completed requests
        for (id, _) in completedRequests {
            removeRequest(id)
        }
        
        return completedRequests
    }
    
    func cancelAllRequests() -> [@Sendable (Swift.Result<CLLocation, Error>) -> Void] {
        let handlers = requests.values.map { $0.completionHandler }
        
        // Clean up
        for id in requests.keys {
            removeRequest(id)
        }
        
        return handlers
    }
    
    private func handleTimeout(for id: UUID, handler: @Sendable () -> Void) {
        if requests[id] != nil {
            handler()
        }
    }
}

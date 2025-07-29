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
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Legacy Observer Support (Deprecated)
// These protocols are maintained for backwards compatibility but are deprecated in favor of AsyncSequence

/// Position location authorization protocol.
/// - Note: Deprecated. Use `authorizationUpdates` AsyncSequence instead.
@available(*, deprecated, message: "Use authorizationUpdates AsyncSequence instead")
public protocol PositionAuthorizationObserver: AnyObject {
    /// Permission change authorization status, this may be triggered on application resume if the app settings have changed
    func position(_ position: Position, didChangeLocationAuthorizationStatus status: Position.LocationAuthorizationStatus)
}

/// Position location updates protocol.
/// - Note: Deprecated. Use `locationUpdates` AsyncSequence instead.
@available(*, deprecated, message: "Use locationUpdates AsyncSequence instead")
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
/// - Note: Deprecated. Use `headingUpdates` AsyncSequence instead.
@available(*, deprecated, message: "Use headingUpdates AsyncSequence instead")
public protocol PositionHeadingObserver: AnyObject {
    func position(_ postiion: Position, didUpdateHeading newHeading: CLHeading)
}

/// 🛰 Position, Swift and efficient location positioning.
public actor Position {

    // MARK: - types

    /// Location authorization status
    public enum LocationAuthorizationStatus: Int, CustomStringConvertible, Sendable {
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
    public enum LocationAccuracyAuthorizationStatus: Int, Sendable {
        case fullAccuracy = 0
        case reducedAccuracy
    }

    /// Possible error types
    public enum ErrorType: Error, CustomStringConvertible, Sendable {
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
    public typealias OneShotCompletionHandler = @Sendable (Swift.Result<CLLocation, Error>) -> Void

    /// Time based filter constant
    public static let TimeFilterNone: TimeInterval      = 0.0
    /// Time based filter constant
    public static let TimeFilter5Minutes: TimeInterval  = 5.0 * 60.0
    /// Time based filter constant
    public static let TimeFilter10Minutes: TimeInterval = 10.0 * 60.0

    /// A statute mile to be 8 furlongs or 1609.344 meters
    public static let MilesToMetersRatio: Double        = 1609.344

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
    
    /// Sets the distance filter
    public func setDistanceFilter(_ distance: Double) {
        distanceFilter = distance
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
    private var _adjustLocationUseWhenBackgrounded: Bool = false
    public var adjustLocationUseWhenBackgrounded: Bool {
        get { _adjustLocationUseWhenBackgrounded }
        set {
            if _deviceLocationManager.isUpdatingLowPowerLocation == true {
                _deviceLocationManager.stopLowPowerUpdating()
                _deviceLocationManager.startUpdating()
            }
            _adjustLocationUseWhenBackgrounded = newValue
        }
    }

    /// When `true`, location will reduce power usage from adjusted accuracy based on the current battery level.
    private var _adjustLocationUseFromBatteryLevel: Bool = false
    public var adjustLocationUseFromBatteryLevel: Bool {
        get { _adjustLocationUseFromBatteryLevel }
        set {
            #if os(iOS)
            Task { @MainActor in
                UIDevice.current.isBatteryMonitoringEnabled = newValue
            }
            #endif
            _adjustLocationUseFromBatteryLevel = newValue
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

    internal let _deviceLocationManager: DeviceLocationManager = DeviceLocationManager()
    internal private(set) var _updating: Bool = false
    
    // MARK: - AsyncSequence Support
    
    private var _locationContinuation: AsyncStream<CLLocation>.Continuation?
    private var _headingContinuation: AsyncStream<CLHeading>.Continuation?
    private var _authorizationContinuation: AsyncStream<LocationAuthorizationStatus>.Continuation?
    private var _floorContinuation: AsyncStream<CLFloor>.Continuation?
    private var _visitContinuation: AsyncStream<CLVisit>.Continuation?
    private var _errorContinuation: AsyncStream<Error>.Continuation?
    
    /// AsyncSequence for continuous location updates
    @available(iOS 15.0, *)
    public var locationUpdates: AsyncStream<CLLocation> {
        AsyncStream { continuation in
            _locationContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    await self?.cleanupLocationContinuation()
                }
            }
        }
    }
    
    /// AsyncSequence for continuous heading updates
    @available(iOS 15.0, *)
    public var headingUpdates: AsyncStream<CLHeading> {
        AsyncStream { continuation in
            _headingContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    await self?.cleanupHeadingContinuation()
                }
            }
        }
    }
    
    /// AsyncSequence for authorization status changes
    @available(iOS 15.0, *)
    public var authorizationUpdates: AsyncStream<LocationAuthorizationStatus> {
        AsyncStream { continuation in
            _authorizationContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    await self?.cleanupAuthorizationContinuation()
                }
            }
        }
    }
    
    private func cleanupLocationContinuation() {
        _locationContinuation = nil
    }
    
    private func cleanupHeadingContinuation() {
        _headingContinuation = nil
    }
    
    private func cleanupAuthorizationContinuation() {
        _authorizationContinuation = nil
    }
    
    /// AsyncSequence for floor updates
    @available(iOS 15.0, *)
    public var floorUpdates: AsyncStream<CLFloor> {
        AsyncStream { continuation in
            _floorContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    await self?.cleanupFloorContinuation()
                }
            }
        }
    }
    
    /// AsyncSequence for visit updates
    @available(iOS 15.0, *)
    public var visitUpdates: AsyncStream<CLVisit> {
        AsyncStream { continuation in
            _visitContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    await self?.cleanupVisitContinuation()
                }
            }
        }
    }
    
    /// AsyncSequence for error updates
    @available(iOS 15.0, *)
    public var errorUpdates: AsyncStream<Error> {
        AsyncStream { continuation in
            _errorContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    await self?.cleanupErrorContinuation()
                }
            }
        }
    }
    
    private func cleanupFloorContinuation() {
        _floorContinuation = nil
    }
    
    private func cleanupVisitContinuation() {
        _visitContinuation = nil
    }
    
    private func cleanupErrorContinuation() {
        _errorContinuation = nil
    }

    // MARK: - object lifecycle

    public init() {
        _deviceLocationManager.delegate = self

        Task { @MainActor in
            addBatteryObservers()
            addAppObservers()
        }
    }

    // Clean up methods should be called before deinit
    public func cleanup() async {
        await MainActor.run {
            removeAppObservers()
            removeBatteryObservers()
        }
    }
}

// MARK: - observers

extension Position {

    /// Adds an authorization observer.
    /// - Note: Deprecated. Use `authorizationUpdates` AsyncSequence instead.
    /// - Parameter observer: Observing instance.
    @available(*, deprecated, message: "Use authorizationUpdates AsyncSequence instead")
    public func addAuthorizationObserver(_ observer: PositionAuthorizationObserver) {
        // Legacy support - no longer functional
    }

    /// Removes an authorization observer.
    /// - Note: Deprecated. Use `authorizationUpdates` AsyncSequence instead.
    /// - Parameter observer: Observing instance.
    @available(*, deprecated, message: "Use authorizationUpdates AsyncSequence instead")
    public func removeAuthorizationObserver(_ observer: PositionAuthorizationObserver) {
        // Legacy support - no longer functional
    }

    /// Adds a position location observer.
    /// - Note: Deprecated. Use `locationUpdates` AsyncSequence instead.
    /// - Parameter observer: Observing instance.
    @available(*, deprecated, message: "Use locationUpdates AsyncSequence instead")
    public func addObserver(_ observer: PositionObserver) {
        // Legacy support - no longer functional
    }

    /// Removes a position location observer.
    /// - Note: Deprecated. Use `locationUpdates` AsyncSequence instead.
    /// - Parameter observer: Observing instance.
    @available(*, deprecated, message: "Use locationUpdates AsyncSequence instead")
    public func removeObserver(_ observer: PositionObserver) {
        // Legacy support - no longer functional
    }

    /// Adds a position heading observer.
    /// - Note: Deprecated. Use `headingUpdates` AsyncSequence instead.
    /// - Parameter observer: Observing instance.
    @available(*, deprecated, message: "Use headingUpdates AsyncSequence instead")
    public func addHeadingObserver(_ observer: PositionHeadingObserver) {
        // Legacy support - no longer functional
    }

    /// Removes a position heading observer.
    /// - Note: Deprecated. Use `headingUpdates` AsyncSequence instead.
    /// - Parameter observer: Observing instance.
    @available(*, deprecated, message: "Use headingUpdates AsyncSequence instead")
    public func removeHeadingObserver(_ observer: PositionHeadingObserver) {
        // Legacy support - no longer functional
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
        // Request authorization
        _deviceLocationManager.requestAlwaysAuthorization()
        
        // If already authorized, return immediately
        let currentStatus = locationServicesStatus
        if currentStatus == .allowedAlways || currentStatus == .denied {
            return currentStatus
        }
        
        // Wait for authorization change
        for await status in authorizationUpdates {
            if status == .allowedAlways || status == .denied {
                return status
            }
        }
        
        return locationServicesStatus
    }

    /// Request location authorization for in app use only.
    public func requestWhenInUseLocationAuthorization() {
        _deviceLocationManager.requestWhenInUseAuthorization()
    }
    
    /// Async version that requests when-in-use authorization and waits for the result
    /// - Returns: The resulting authorization status after the request
    @available(iOS 15.0, *)
    public func requestWhenInUseLocationAuthorization() async -> LocationAuthorizationStatus {
        // Request authorization
        _deviceLocationManager.requestWhenInUseAuthorization()
        
        // If already authorized, return immediately
        let currentStatus = locationServicesStatus
        if currentStatus == .allowedWhenInUse || currentStatus == .allowedAlways || currentStatus == .denied {
            return currentStatus
        }
        
        // Wait for authorization change
        for await status in authorizationUpdates {
            if status == .allowedWhenInUse || status == .allowedAlways || status == .denied {
                return status
            }
        }
        
        return locationServicesStatus
    }

    public var locationAccuracyAuthorizationStatus: LocationAccuracyAuthorizationStatus {
        _deviceLocationManager.locationAccuracyAuthorizationStatus
    }

    /// Request one time accuracy authorization. Be sure to include "FullAccuracyPurpose" to your Info.plist.
    public func requestOneTimeFullAccuracyAuthorization(_ completionHandler: (@Sendable (Bool) -> Void)? = nil) {
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
    ///
    /// - Note: For Swift 6+, consider using the async version instead:
    /// ```swift
    /// let location = try await Position.shared.currentLocation()
    /// // or with custom accuracy:
    /// let location = try await Position.shared.currentLocation(desiredAccuracy: kCLLocationAccuracyNearestTenMeters)
    /// ```
    public func performOneShotLocationUpdate(withDesiredAccuracy desiredAccuracy: Double, completionHandler: Position.OneShotCompletionHandler? = nil) {
        _deviceLocationManager.performOneShotLocationUpdate(withDesiredAccuracy: desiredAccuracy, completionHandler: completionHandler)
    }
    
    /// Swift 6-style async version of performOneShotLocationUpdate
    /// This is the recommended way to get a one-shot location in Swift 6+
    ///
    /// - Parameter desiredAccuracy: Minimum accuracy to meet before for request.
    /// - Returns: The location if successful
    /// - Throws: Position.ErrorType if the request fails
    @available(iOS 15.0, *)
    public func performOneShotLocationUpdate(withDesiredAccuracy desiredAccuracy: Double) async throws -> CLLocation {
        try await _deviceLocationManager.performOneShotLocationUpdate(withDesiredAccuracy: desiredAccuracy)
    }
    
    /// Convenient Swift 6-style method to get current location with default accuracy
    /// 
    /// - Parameter desiredAccuracy: Minimum accuracy to meet (defaults to kCLLocationAccuracyBest)
    /// - Returns: The current location
    /// - Throws: Position.ErrorType if the request fails
    @available(iOS 15.0, *)
    public func currentLocation(desiredAccuracy: Double = kCLLocationAccuracyBest) async throws -> CLLocation {
        try await performOneShotLocationUpdate(withDesiredAccuracy: desiredAccuracy)
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
    
    // Observer methods removed - use AsyncSequence instead

    internal func checkAuthorizationStatusForServices() {
        if _deviceLocationManager.locationServicesStatus == .denied {
            Task { [weak self] in
                guard let self = self else { return }
                if #available(iOS 15.0, *) {
                    await self._authorizationContinuation?.yield(.denied)
                }
            }
        }
    }

    internal func updateLocationAccuracyIfNecessary() {
        if adjustLocationUseFromBatteryLevel == true {
            #if os(iOS)
            Task { @MainActor in
                switch UIDevice.current.batteryState {
                    case .full,
                         .charging:
                        await self._deviceLocationManager.taskSetTrackingAccuracy(
                            active: kCLLocationAccuracyNearestTenMeters,
                            background: kCLLocationAccuracyHundredMeters
                        )
                        break
                    case .unplugged,
                         .unknown:
                        fallthrough
                    @unknown default:
                        let batteryLevel: Float = UIDevice.current.batteryLevel
                        if batteryLevel < 0.15 {
                            await self._deviceLocationManager.taskSetTrackingAccuracy(
                                active: kCLLocationAccuracyThreeKilometers,
                                background: kCLLocationAccuracyThreeKilometers
                            )
                        } else {
                            await self._deviceLocationManager.taskSetTrackingAccuracy(
                                active: kCLLocationAccuracyHundredMeters,
                                background: kCLLocationAccuracyKilometer
                            )
                        }
                        break
                }
            }
            #endif
        }
    }
}

// MARK: - Notifications

extension Position {

    // add / remove

    @MainActor
    internal func addAppObservers() {
        #if os(iOS)
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationDidBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: UIApplication.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(handleApplicationWillResignActive(_:)), name: UIApplication.willResignActiveNotification, object: UIApplication.shared)
        #endif
    }

    @MainActor
    internal func removeAppObservers() {
        #if os(iOS)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: UIApplication.shared)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: UIApplication.shared)
        #endif
    }

    @MainActor
    internal func addBatteryObservers() {
        #if os(iOS)
        NotificationCenter.default.addObserver(self, selector: #selector(handleBatteryLevelChanged(_:)), name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleBatteryStateChanged(_:)), name: UIDevice.batteryStateDidChangeNotification, object: nil)
        #endif
    }

    @MainActor
    internal func removeBatteryObservers() {
        #if os(iOS)
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryStateDidChangeNotification, object: nil)
        #endif
    }

    // handlers

    @objc
    private nonisolated func handleApplicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            await self.checkAuthorizationStatusForServices()

            // if position is not updating, don't modify state
            if await self._updating == false {
                return
            }

            // internally, locationManager will adjust desiredaccuracy to trackingDesiredAccuracyBackground
            if await self.adjustLocationUseWhenBackgrounded == true {
                self._deviceLocationManager.stopLowPowerUpdating()
            }
        }
    }

    @objc
    private nonisolated func handleApplicationWillResignActive(_ notification: Notification) {
        Task { @MainActor in
            if await self._updating == true {
                return
            }

            if await self.adjustLocationUseWhenBackgrounded == true {
                self._deviceLocationManager.startLowPowerUpdating()
            }

            await self.updateLocationAccuracyIfNecessary()
        }
    }

    @objc
    private nonisolated func handleBatteryLevelChanged(_ notification: Notification) {
        Task { @MainActor in
            #if os(iOS)
            let batteryLevel = UIDevice.current.batteryLevel
            if batteryLevel < 0 {
                return
            }
            await updateLocationAccuracyIfNecessary()
            #endif
        }
    }

    @objc
    private nonisolated func handleBatteryStateChanged(_ notification: Notification) {
        Task { @MainActor in
            #if os(iOS)
            await updateLocationAccuracyIfNecessary()
            #endif
        }
    }

}

// MARK: - DeviceLocationManagerDelegate

extension Position: DeviceLocationManagerDelegate {

    internal nonisolated func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus) {
        Task { [weak self] in
            guard let self = self else { return }
            if #available(iOS 15.0, *) {
                await self._authorizationContinuation?.yield(status)
            }
        }
    }

    internal nonisolated func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didFailWithError error: Error?) {
        Task { [weak self] in
            guard let self = self else { return }
            if #available(iOS 15.0, *), let error = error {
                await self._errorContinuation?.yield(error)
            }
        }
    }

    internal nonisolated func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didUpdateOneShotLocation location: CLLocation?) {
        // One-shot locations are handled via async/await API
    }

    internal nonisolated func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didUpdateTrackingLocations locations: [CLLocation]?) {
        Task { [weak self] in
            guard let self = self else { return }
            if #available(iOS 15.0, *), let location = locations?.first {
                await self._locationContinuation?.yield(location)
            }
        }
    }

    nonisolated func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didUpdateHeading newHeading: CLHeading) {
        let heading = newHeading // Capture immediately
        Task { @Sendable [weak self] in
            guard let self = self else { return }
            if #available(iOS 15.0, *) {
                await self._headingContinuation?.yield(heading)
            }
        }
    }

    internal nonisolated func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didUpdateFloor floor: CLFloor) {
        let floorData = floor // Capture immediately
        Task { @Sendable [weak self] in
            guard let self = self else { return }
            if #available(iOS 15.0, *) {
                await self._floorContinuation?.yield(floorData)
            }
        }
    }

    internal nonisolated func deviceLocationManager(_ deviceLocationManager: DeviceLocationManager, didVisit visit: CLVisit?) {
        guard let visit = visit else { return }
        let visitData = visit // Capture immediately
        Task { @Sendable [weak self] in
            guard let self = self else { return }
            if #available(iOS 15.0, *) {
                await self._visitContinuation?.yield(visitData)
            }
        }
    }

}

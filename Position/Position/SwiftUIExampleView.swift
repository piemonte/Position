//
//  SwiftUIExampleView.swift
//
//  Created for Position SwiftUI example
//
//  The MIT License (MIT)
//
//  Copyright (c) 2025-present patrick piemonte (http://patrickpiemonte.com/)
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

import SwiftUI
import MapKit
import CoreLocation
import Combine

@available(iOS 15.0, *)
struct SwiftUIExampleView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3351, longitude: -122.0088),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var showingPermissionAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            Map(coordinateRegion: $region, showsUserLocation: true)
                .ignoresSafeArea(edges: .top)
            
            VStack(spacing: 16) {
                // status
                VStack(alignment: .leading, spacing: 8) {
                    Label("Location Status", systemImage: "location.circle")
                        .font(.headline)
                    
                    Text("Authorization: \(locationManager.authorizationStatus.description)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let location = locationManager.currentLocation {
                        Text("Lat: \(location.coordinate.latitude, specifier: "%.6f")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Lon: \(location.coordinate.longitude, specifier: "%.6f")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Accuracy: \(location.horizontalAccuracy, specifier: "%.1f")m")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let heading = locationManager.currentHeading {
                        Text("Heading: \(heading.trueHeading, specifier: "%.1f")°")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // actions
                VStack(spacing: 12) {
                    Button(action: requestPermission) {
                        Label("Request Permission", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(locationManager.authorizationStatus == .allowedAlways || 
                             locationManager.authorizationStatus == .allowedWhenInUse)
                    
                    Button(action: requestLocation) {
                        Label("Get Current Location", systemImage: "location.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(locationManager.authorizationStatus != .allowedAlways && 
                             locationManager.authorizationStatus != .allowedWhenInUse)
                    
                    HStack(spacing: 12) {
                        Button(action: startTracking) {
                            Label("Start Tracking", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .disabled(locationManager.isTracking || 
                                 (locationManager.authorizationStatus != .allowedAlways && 
                                  locationManager.authorizationStatus != .allowedWhenInUse))
                        
                        Button(action: stopTracking) {
                            Label("Stop Tracking", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .disabled(!locationManager.isTracking)
                    }
                }
            }
            .padding()
        }
        .alert("Location Permission", isPresented: $showingPermissionAlert) {
            Button("OK") { }
        } message: {
            Text("Please enable location services in Settings to use this feature.")
        }
        .onReceive(locationManager.$currentLocation) { location in
            if let location = location {
                withAnimation {
                    region.center = location.coordinate
                }
            }
        }
    }
    
    private func requestPermission() {
        Position.shared.requestWhenInUseLocationAuthorization()
    }
    
    private func requestLocation() {
        Task {
            do {
                let location = try await Position.shared.performOneShotLocationUpdate(withDesiredAccuracy: kCLLocationAccuracyBest)
                withAnimation {
                    region.center = location.coordinate
                }
            } catch {
                print("Failed to get location: \(error)")
            }
        }
    }
    
    private func startTracking() {
        locationManager.startTracking()
    }
    
    private func stopTracking() {
        locationManager.stopTracking()
    }
}

@available(iOS 15.0, *)
class LocationManager: ObservableObject {
    @Published var currentLocation: CLLocation?
    @Published var currentHeading: CLHeading?
    @Published var authorizationStatus: Position.LocationAuthorizationStatus = .notDetermined
    @Published var isTracking = false
    
    private var cancellables = Set<AnyCancellable>()
    private let position = Position.shared
    
    init() {
        // subscribe to location updates
        position.locationPublisher
            .sink { [weak self] location in
                self?.currentLocation = location
            }
            .store(in: &cancellables)
        
        // subscribe to heading updates
        position.headingPublisher
            .sink { [weak self] heading in
                self?.currentHeading = heading
            }
            .store(in: &cancellables)
        
        // subscribe to authorization changes
        position.authorizationPublisher
            .sink { [weak self] status in
                self?.authorizationStatus = status
            }
            .store(in: &cancellables)
        
        // set initial authorization status
        authorizationStatus = position.locationServicesStatus
    }
    
    func startTracking() {
        position.startUpdating()
        position.startUpdatingHeading()
        isTracking = true
        
        // example of using AsyncSequence for location updates
        Task {
            for await location in position.locationUpdates {
                print("AsyncSequence location update: \(location.coordinate)")
                // Could update UI or process location here
            }
        }
        
        // example of using AsyncSequence for heading updates
        Task {
            for await heading in position.headingUpdates {
                print("AsyncSequence heading update: \(heading.trueHeading)°")
            }
        }
    }
    
    func stopTracking() {
        position.stopUpdating()
        position.stopUpdatingHeading()
        isTracking = false
    }
}

@available(iOS 15.0, *)
struct SwiftUIExampleView_Previews: PreviewProvider {
    static var previews: some View {
        SwiftUIExampleView()
    }
}

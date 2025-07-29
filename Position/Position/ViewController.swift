//
//  ViewController.swift
//
//  Created by patrick piemonte on 2/20/15.
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
import MapKit
import CoreLocation

public class ViewController: UIViewController {

    // MARK: - ivars

    private var _mapView: MKMapView?
    private var _permissionLocationButton: UIButton?
    private var _locationLookupButton: UIButton?
    private let position = Position()

    // MARK: - object lifecycle

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    // MARK: - view lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()

        self.view.autoresizingMask = ([.flexibleWidth, .flexibleHeight])
        self.view.backgroundColor = UIColor.lightGray

        // Setup map view
        self._mapView = MKMapView()
        if let mapView = self._mapView {
            mapView.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(mapView)
        }

        let buttonHeight: CGFloat = 60

        // Setup location button
        self._locationLookupButton = UIButton(type: .system)
        if let locationButton = self._locationLookupButton {
            locationButton.translatesAutoresizingMaskIntoConstraints = false
            locationButton.setTitle("Request Location", for: .normal)
            locationButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
            locationButton.backgroundColor = UIColor(red: 115/255, green: 57/255, blue: 248/255, alpha: 1)
            locationButton.setTitleColor(.white, for: .normal)
            locationButton.addTarget(self, action: #selector(handleOneShotLocationButton(_:)), for: .touchUpInside)
            self.view.addSubview(locationButton)
        }

        // Setup permission button
        self._permissionLocationButton = UIButton(type: .system)
        if let permissionLocationButton = self._permissionLocationButton {
            permissionLocationButton.translatesAutoresizingMaskIntoConstraints = false
            permissionLocationButton.setTitle("Request Permission", for: .normal)
            permissionLocationButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
            permissionLocationButton.backgroundColor = UIColor(red: 50/255, green: 153/255, blue: 252/255, alpha: 1)
            permissionLocationButton.setTitleColor(.white, for: .normal)
            permissionLocationButton.addTarget(self, action: #selector(handleLocationPermissionButton(_:)), for: .touchUpInside)
            self.view.addSubview(permissionLocationButton)
        }
        
        // Setup constraints
        setupConstraints(buttonHeight: buttonHeight)

        // setup position
        Task {
            await position.addObserver(self)
            await position.setDistanceFilter(20)
        }
    }
    
    private func setupConstraints(buttonHeight: CGFloat) {
        guard let mapView = _mapView,
              let locationButton = _locationLookupButton,
              let permissionButton = _permissionLocationButton else {
            return
        }
        
        NSLayoutConstraint.activate([
            // Map view constraints - fills the entire view
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Location button constraints - respects safe area at bottom
            locationButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            locationButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            locationButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            locationButton.heightAnchor.constraint(equalToConstant: buttonHeight),
            
            // Permission button constraints - above location button
            permissionButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            permissionButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            permissionButton.bottomAnchor.constraint(equalTo: locationButton.topAnchor),
            permissionButton.heightAnchor.constraint(equalToConstant: buttonHeight)
        ])
    }
}

// MARK: - UIButton

extension ViewController {

    @objc
    internal func handleLocationPermissionButton(_ button: UIButton) {
        Task {
            // request permissions based on the type of location support required.
            let currentStatus = await position.locationServicesStatus
            if currentStatus == .allowedWhenInUse || currentStatus == .allowedAlways {
                print("app has permission")
            } else {
                // request permission using async/await
                if #available(iOS 15.0, *) {
                    let status = await position.requestWhenInUseLocationAuthorization()
                    print("Authorization status after request: \(status)")
                } else {
                    await position.requestWhenInUseLocationAuthorization()
                }
            }
        }
    }

    @objc
    internal func handleOneShotLocationButton(_ button: UIButton) {
        Task {
            let currentStatus = await position.locationServicesStatus
            if currentStatus == .allowedWhenInUse || currentStatus == .allowedAlways {
                if #available(iOS 15.0, *) {
                    do {
                        let location = try await position.performOneShotLocationUpdate(withDesiredAccuracy: 150)
                        if location.horizontalAccuracy > 0 {
                            let region = MKCoordinateRegion(center: location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
                            await MainActor.run {
                                self._mapView?.setRegion(region, animated: true)
                            }
                        }
                    } catch {
                        print("Location update failed: \(error)")
                    }
                } else {
                    await position.performOneShotLocationUpdate(withDesiredAccuracy: 150) { result in
                        switch result {
                        case .success(let location):
                            if location.horizontalAccuracy > 0 {
                                let region = MKCoordinateRegion(center: location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
                                DispatchQueue.main.async {
                                    self._mapView?.setRegion(region, animated: true)
                                }
                            }
                        case .failure(let error):
                            print("Location update failed: \(error)")
                        }
                    }
                }
            } else if currentStatus == .notAvailable {
                print("location is not available")
            }
        }
    }

}

// MARK: - PositionAuthorizationObserver

extension ViewController: PositionAuthorizationObserver {

    public func position(_ position: Position, didChangeLocationAuthorizationStatus status: Position.LocationAuthorizationStatus) {
        // location authorization did change, this may even be triggered on application resume if the user updated settings
        print("position, location authorization status \(status)")
    }

}

// MARK: - PositionObserver

extension ViewController: PositionObserver {

    public func position(_ position: Position, didUpdateOneShotLocation location: CLLocation?) {
//        print("position, one-shot location updated \(location)")
    }

    public func position(_ position: Position, didUpdateTrackingLocations locations: [CLLocation]?) {
//        print("position, tracking location update \(locations?.last)")
    }

    public func position(_ position: Position, didUpdateFloor floor: CLFloor) {
    }

    public func position(_ position: Position, didVisit visit: CLVisit?) {
    }

    public func position(_ position: Position, didChangeDesiredAccurary desiredAccuracy: Double) {
//        print("position, changed desired accuracy \(desiredAccuracy)")
    }

    // error handling
    public func position(_ position: Position, didFailWithError error: Error?) {
        print("position, failed with error \(String(describing: error?.localizedDescription))")
    }

}

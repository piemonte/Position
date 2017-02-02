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

class ViewController: UIViewController {

    // MARK: - ivars
    
    internal var _mapView: MKMapView?
    internal var _permissionLocationButton: UIButton?
    internal var _locationLookupButton: UIButton?
    
    // MARK: - object lifecycle
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
    }
    
    deinit {
    }

    // MARK: - view lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.autoresizingMask = ([UIViewAutoresizing.flexibleWidth, UIViewAutoresizing.flexibleHeight])
        self.view.backgroundColor = UIColor.lightGray
        
        self._mapView = MKMapView(frame: self.view.bounds)
        if let mapView = self._mapView {
            self.view.addSubview(mapView)
        }
        
        let buttonHeight: CGFloat = 60
        
        self._locationLookupButton = UIButton(frame: CGRect(x: 0, y: self.view.bounds.size.height - buttonHeight, width: self.view.bounds.size.width, height: buttonHeight))
        if let locationButton = self._locationLookupButton {
            locationButton.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
            locationButton.setTitle("Request Location", for: UIControlState())
            locationButton.titleLabel!.font = UIFont(name: "AvenirNext-Medium", size: 16)
            locationButton.backgroundColor = UIColor(red: 115/255, green: 57/255, blue: 248/255, alpha: 1)
            locationButton.addTarget(self, action: #selector(ViewController.handleOneShotLocationButton(_:)), for: .touchUpInside)
            self.view.addSubview(locationButton)
        }
        
        self._permissionLocationButton = UIButton(frame: CGRect(x: 0, y: self.view.bounds.size.height - (buttonHeight * 2), width: self.view.bounds.size.width, height: buttonHeight))
        if let permissionLocationButton = self._permissionLocationButton {
            permissionLocationButton.setTitle("Request Permission", for: UIControlState())
            permissionLocationButton.titleLabel!.font = UIFont(name: "AvenirNext-Medium", size: 16)
            permissionLocationButton.backgroundColor = UIColor(red: 50/255, green: 153/255, blue: 252/255, alpha: 1)
            permissionLocationButton.addTarget(self, action: #selector(handleLocationPermissionButton(_:)), for: .touchUpInside)
            self.view.addSubview(permissionLocationButton)
        }
        
        // setup position
        
        let position = Position.shared
        position.addObserver(self)
        position.distanceFilter = 20
        
        // Example, using settings for AllowedAlways tracking:
        // position.adjustLocationUseWhenBackgrounded = true
        // position.adjustLocationUseFromBatteryLevel = true
        
        // Example, using location tracking
        // if position.locationServicesStatus == .AllowedWhenInUse ||
        //      position.locationServicesStatus == .AllowedAlways {
        //      position.startUpdating()
        // }
    }
}

// MARK: - UIButton

extension ViewController {
    
    func handleLocationPermissionButton(_ button: UIButton) {
        // request permissions based on the type of location support required.
        let position = Position.shared
        if position.locationServicesStatus == .allowedWhenInUse ||
            position.locationServicesStatus == .allowedAlways {
            print("app has permission")
        } else {
            Position.shared.requestWhenInUseLocationAuthorization()
            //Position.shared.requestAlwaysLocationAuthorization()
        }
    }
    
    func handleOneShotLocationButton(_ button: UIButton) {
        let position = Position.shared
        if position.locationServicesStatus == .allowedWhenInUse ||
           position.locationServicesStatus == .allowedAlways {
            position.performOneShotLocationUpdate(withDesiredAccuracy: 150) { (location, error) -> () in
                if let pos = location {
                    if pos.horizontalAccuracy > 0 {
                        let region = MKCoordinateRegion(center: pos.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
                        self._mapView?.setRegion(region, animated: true)
                    }
                }
                print("one shot location update \(location) error \(error)")
            }
        } else if position.locationServicesStatus == .notAvailable {
            print("location is not available")
        }
    }

}

// MARK: - PositionAuthorizationObserver

extension ViewController: PositionAuthorizationObserver {

    func position(_ position: Position, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus) {
        // location authorization did change, this may even be triggered on application resume if the user updated settings
        print("position, location authorization status \(status)")
    }

}

// MARK: - PositionObserver

extension ViewController: PositionObserver {
	
    // location
    func position(_ position: Position, didUpdateOneShotLocation location: CLLocation?) {
        print("position, one-shot location updated \(location)")
    }
    
    func position(_ position: Position, didUpdateTrackingLocations locations: [CLLocation]?) {
        print("position, tracking location update \(locations?.last)")
    }
    
    func position(_ position: Position, didUpdateFloor floor: CLFloor) {
    }
    
    func position(_ position: Position, didVisit visit: CLVisit?) {
    }
    
    func position(_ position: Position, didChangeDesiredAccurary desiredAccuracy: Double) {
        print("position, changed desired accuracy \(desiredAccuracy)")
    }
    
    // error handling
    func position(_ position: Position, didFailWithError error: Error?) {
        print("position, failed with error \(error)")
    }

}

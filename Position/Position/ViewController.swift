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
import CoreLocation

class ViewController: UIViewController {

    // MARK: - ivars
    
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
        self.view.backgroundColor = UIColor.white
        
        self._permissionLocationButton = UIButton(frame: CGRect(x: 0, y: 0, width: 240, height: 50))
        if let permissionLocationButton = self._permissionLocationButton {
            permissionLocationButton.center = CGPoint(x: self.view.center.x, y: self.view.center.y - 120)
            permissionLocationButton.setTitle("Location Permission", for: UIControlState())
            permissionLocationButton.titleLabel!.font = UIFont(name: "AvenirNext-Regular", size: 20)
            permissionLocationButton.backgroundColor = UIColor(red: 115/255, green: 252/255, blue: 214/255, alpha: 1)
            permissionLocationButton.layer.cornerRadius = 6.0
            permissionLocationButton.addTarget(self, action: #selector(handleLocationPermissionButton(_:)), for: .touchUpInside)
            self.view.addSubview(permissionLocationButton)
        }
        
        let locationButton: UIButton = UIButton(frame: CGRect(x: 0, y: 0, width: 240, height: 50))
        locationButton.center = CGPoint(x: self.view.center.x, y: self.view.center.y + 60)
        locationButton.setTitle("Request Location", for: UIControlState())
        locationButton.titleLabel!.font = UIFont(name: "AvenirNext-Regular", size: 20)
        locationButton.backgroundColor = UIColor(red: 115/255, green: 252/255, blue: 214/255, alpha: 1)
        locationButton.layer.cornerRadius = 6.0
        locationButton.addTarget(self, action: #selector(ViewController.handleOneShotLocationButton(_:)), for: .touchUpInside)
        self.view.addSubview(locationButton)
        
        // setup position
        
        let position = Position.shared
        position.addObserver(self)
        position.distanceFilter = 20
        
        // Example settings for AllowedAlways:
        // position.adjustLocationUseWhenBackgrounded = true
        // position.adjustLocationUseFromBatteryLevel = true
        
        // tracking
        // if position.locationServicesStatus == .AllowedWhenInUse ||
        //      position.locationServicesStatus == .AllowedAlways {
        //      position.startUpdating()
        // }

    }
}

// MARK: - UIButton

extension ViewController {
    
    func handleLocationPermissionButton(_ button: UIButton!) {
        // request permissions based on the type of location support required.
        Position.shared.requestWhenInUseLocationAuthorization()
        //Position.shared.requestAlwaysLocationAuthorization()
    }
    
    func handleOneShotLocationButton(_ button: UIButton!) {
        let position = Position.shared
        if position.locationServicesStatus == .allowedWhenInUse ||
           position.locationServicesStatus == .allowedAlways {
            position.performOneShotLocationUpdate(withDesiredAccuracy: 150) { (location, error) -> () in
                print("one shot location update \(location) error \(error)")
            }
        } else if position.locationServicesStatus == .notAvailable {
            print("location is not available")
        }
    }

}

// MARK: - PositionObserver

extension ViewController: PositionObserver {

    func position(_ position: Position, didChangeLocationAuthorizationStatus status: LocationAuthorizationStatus) {
        // location authorization did change, often this may even be triggered on application resume if the user updated settings
        print("location authorization status \(status)")
    }
	
    // error handling
    func position(_ position: Position, didFailWithError error: Error?) {
        print("failed with error \(error)")
    }

    // location
    func position(_ position: Position, didUpdateOneShotLocation location: CLLocation?) {
    }
    
    func position(_ position: Position, didUpdateTrackingLocations locations: [CLLocation]?) {
        print("tracking location update \(locations?.last)")
    }
    
    func position(_ position: Position, didUpdateFloor floor: CLFloor) {
    }
    
    func position(_ position: Position, didVisit visit: CLVisit?) {
    }
    
    func position(_ position: Position, didChangeDesiredAccurary desiredAccuracy: Double) {
    }

}

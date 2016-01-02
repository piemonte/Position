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

class ViewController: UIViewController, PositionObserver {

    // MARK: object lifecycle
    
    convenience init() {
        self.init(nibName: nil, bundle:nil)
    }
    
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: NSBundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    // MARK: view lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.autoresizingMask = ([UIViewAutoresizing.FlexibleWidth, UIViewAutoresizing.FlexibleHeight])
        self.view.backgroundColor = UIColor.whiteColor()

        let position: Position! = Position.sharedPosition
        position.addObserver(self)
        position.distanceFilter = 20
        
        // Example settings for Always:
//        position.adjustLocationUseWhenBackgrounded = true
//        position.adjustLocationUseFromBatteryLevel = true
//        if position.locationServicesStatus == .AllowedWhenInUse ||
//           position.locationServicesStatus == .AllowedAlways {
//              position.startUpdating()
//        }
        
        let permissionButton: UIButton = UIButton(frame: CGRectMake(0, 0, 240, 50))
        permissionButton.center = CGPointMake(self.view.center.x, self.view.center.y - 60)
        permissionButton.setTitle("Request Permission", forState: .Normal)
        permissionButton.titleLabel!.font = UIFont(name: "AvenirNext-Regular", size: 20)
        permissionButton.backgroundColor = UIColor(red: 115/255, green: 252/255, blue: 214/255, alpha: 1)
        permissionButton.layer.cornerRadius = 6.0
        permissionButton.addTarget(self, action: "handlePermissionButton:", forControlEvents: .TouchUpInside)
        self.view.addSubview(permissionButton)
        
        let locationButton: UIButton = UIButton(frame: CGRectMake(0, 0, 240, 50))
        locationButton.center = CGPointMake(self.view.center.x, self.view.center.y + 60)
        locationButton.setTitle("Request Location", forState: .Normal)
        locationButton.titleLabel!.font = UIFont(name: "AvenirNext-Regular", size: 20)
        locationButton.backgroundColor = UIColor(red: 115/255, green: 252/255, blue: 214/255, alpha: 1)
        locationButton.layer.cornerRadius = 6.0
        locationButton.addTarget(self, action: "handleOneShotLocationButton:", forControlEvents: .TouchUpInside)
        self.view.addSubview(locationButton)
    }
    
    // MARK: UIButton
    
    func handlePermissionButton(button: UIButton!) {
        // request permissions based on the type of location support required.
        Position.sharedPosition.requestWhenInUseLocationAuthorization()
        //Position.sharedPosition.requestAlwaysLocationAuthorization()
    }
    
    func handleOneShotLocationButton(button: UIButton!) {
        let position: Position! = Position.sharedPosition
        if position.locationServicesStatus == .AllowedWhenInUse ||
           position.locationServicesStatus == .AllowedAlways {
            position.performOneShotLocationUpdateWithDesiredAccuracy(250) { (location, error) -> () in
                print("one shot location update \(location) error \(error)")
            }
        } else if position.locationServicesStatus == .NotAvailable {
            print("location is not available")
        }
    }
    
    // MARK: PositionObserver
    
    func position(position: Position, didChangeLocationAuthorizationStatus status: AuthorizationStatus) {
        // location authorization did change, often this may even be triggered on application resume if the user updated settings
        print("authorization status \(status)")
    }
    
    // error handling
    func position(position: Position, didFailWithError error: NSError?) {
        print("failed with error \(error)")
    }

    // location
    func position(position: Position, didUpdateOneShotLocation location: CLLocation?) {
    }
    
    func position(position: Position, didUpdateTrackingLocations locations: [CLLocation]?) {
        print("tracking location update \(locations?.last)")
    }
    
    func position(position: Position, didUpdateFloor floor: CLFloor) {
    }
    
    func position(position: Position, didVisit visit: CLVisit?) {
    }
    
    func position(position: Position, didChangeDesiredAccurary desiredAccuracy: Double) {
    }
}

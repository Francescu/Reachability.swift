//
//  ViewController.swift
//  Reachability Sample
//
//  Created by Ashley Mills on 22/09/2014.
//  Copyright (c) 2014 Joylord Systems. All rights reserved.
//
//
import UIKit

let useClosures = false

extension Reachability.NetworkStatus {
    func color() -> UIColor {
        switch self {
        case .ReachableViaWiFi: return UIColor.greenColor()
        case .ReachableViaWWAN(let type): return type.isFast() ? UIColor.blueColor() : UIColor.orangeColor()
        case .NotReachable: return UIColor.redColor()
        }
    }
}

class ViewController: UIViewController {

    @IBOutlet weak var networkStatus: UILabel!
    
    var reachability: Reachability?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        do {
            let reachability = try Reachability.reachabilityForInternetConnection()
            self.reachability = reachability
            try self.reachability!.startNotifier()
        } catch ReachabilityError.FailedToCreateWithAddress(let address) {
            networkStatus.textColor = UIColor.redColor()
            networkStatus.text = "Unable to create\nReachability with address:\n\(address)"
            return
        } catch {}
        
        reachability?.networkStatusChanged = updateLabel
        
        // Initial reachability check
        if let reachability = reachability {
            updateLabel(reachability.currentReachabilityStatus)
        }
    }
    
    deinit {

        reachability?.stopNotifier()
        
        if (!useClosures) {
            NSNotificationCenter.defaultCenter().removeObserver(self, name: ReachabilityChangedNotification, object: nil)
        }
    }

    func updateLabel(status: Reachability.NetworkStatus) {
        self.networkStatus.textColor = status.color()
        self.networkStatus.text = status.description
    }
   
}


/*
Copyright (c) 2014, Ashley Mills
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
*/

import SystemConfiguration
import Foundation
import CoreTelephony
import UIKit
enum ReachabilityError: ErrorType {
    case FailedToCreateWithAddress(sockaddr_in)
    case FailedToCreateWithHostname(String)
    case UnableToSetCallback
    case UnableToSetDispatchQueue
}

public let ReachabilityChangedNotification = "ReachabilityChangedNotification"

func callback(reachability:SCNetworkReachability, flags: SCNetworkReachabilityFlags, info: UnsafeMutablePointer<Void>) {
    let reachability = Unmanaged<Reachability>.fromOpaque(COpaquePointer(info)).takeUnretainedValue()

    dispatch_async(dispatch_get_main_queue()) {
        reachability.reachabilityChanged(flags)
    }
}

let test = CTRadioAccessTechnologyEdge

public class Reachability: NSObject {

    public typealias NetworkStatusChanged = (NetworkStatus) -> ()
    public typealias NetworkReachable = (Reachability) -> ()
    public typealias NetworkUnreachable = (Reachability) -> ()

    public enum NetworkStatus: CustomStringConvertible, Equatable {

        case NotReachable, ReachableViaWiFi, ReachableViaWWAN(CellularType)

        func reachable() -> Bool {
            switch self {
            case .NotReachable:                           return false
            case .ReachableViaWiFi, .ReachableViaWWAN(_): return true
            }
        }
        
        func reachableFast() -> Bool {
            switch self {
            case .ReachableViaWiFi:           return true
            case .ReachableViaWWAN(let type): return type.isFast()
            case .NotReachable:               return false
            }
        }
        
        public var description: String {
            switch self {
            case .ReachableViaWWAN(let type):
                return "Cellular-\(type)"
            case .ReachableViaWiFi:
                return "WiFi"
            case .NotReachable:
                return "No Connection"
            }
        }
    }

    public enum CellularType {
        case GRPS, Edge, WCDMA, HSDPA, HSUPA, CDMA1x, CDMAEVD0, eHRPD, LTE, Unknown
        
        init(radioConstant: String) {
            switch radioConstant {
            case CTRadioAccessTechnologyGPRS:
                self = .GRPS
            case CTRadioAccessTechnologyEdge:
                self = .Edge
            case CTRadioAccessTechnologyWCDMA:
                self = .WCDMA
            case CTRadioAccessTechnologyHSDPA:
                self = .HSDPA
            case CTRadioAccessTechnologyHSUPA:
                self = .HSUPA
            case CTRadioAccessTechnologyCDMA1x:
                self = .CDMA1x
            case CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA, CTRadioAccessTechnologyCDMAEVDORevB:
                self = .CDMAEVD0
            case CTRadioAccessTechnologyeHRPD:
                self = .eHRPD
            case CTRadioAccessTechnologyLTE:
                self = .LTE
            default:
                self = .Unknown
            }
        }
        
        func isFast() -> Bool {
            switch self {
            case .GRPS, .Edge, .CDMA1x, .Unknown:                 return false
            case .WCDMA, .HSDPA, .HSUPA, .CDMAEVD0, .eHRPD, .LTE: return true
            }
        }
    }

    private let telephonyInfo = CTTelephonyNetworkInfo()
    
    // MARK: - *** Public properties ***

    public var whenReachable: NetworkReachable?
    public var whenUnreachable: NetworkUnreachable?
    public var networkStatusChanged: NetworkStatusChanged?
    
    public var reachableOnWWAN: Bool
    public var notificationCenter = NSNotificationCenter.defaultCenter()

    public var currentReachabilityStatus: NetworkStatus {
        return reachabilityStatus(currentCellularType)
    }

    public var currentReachabilityString: String {
        return "\(currentReachabilityStatus)"
    }
    
    private var currentCellularType: CellularType = .Unknown {
        didSet {
            print("Pong cellular!")
            if let networkStatusChanged = networkStatusChanged {
                dispatch_async(dispatch_get_main_queue()) {
                    networkStatusChanged(self.currentReachabilityStatus)
                }
            }
        }
    }

    // MARK: - *** Initialisation methods ***
    
    required public init(reachabilityRef: SCNetworkReachability) {
        reachableOnWWAN = true
        self.reachabilityRef = reachabilityRef
        
        super.init()
        
        updateCurrentCellularType()
        
        notificationCenter.addObserverForName(UIApplicationDidBecomeActiveNotification, object: nil, queue: NSOperationQueue.mainQueue()) { _ in
            print("Ping pong AppActive")
            if let networkStatusChanged = self.networkStatusChanged {
                networkStatusChanged(self.currentReachabilityStatus)
            }
        }
        notificationCenter.addObserverForName(CTRadioAccessTechnologyDidChangeNotification, object: nil, queue: nil, usingBlock: updateCurrentCellularType)
    }
    
    private func updateCurrentCellularType(notification: NSNotification? = nil) {
        print("Ping cellular!")
        if let radio = telephonyInfo.currentRadioAccessTechnology {
            print(radio)
            currentCellularType = CellularType(radioConstant: radio)
        }
        else {
            print("pong plane")
        }
    }
    
    public convenience init(hostname: String) throws {
        
        let nodename = (hostname as NSString).UTF8String
        guard let ref = SCNetworkReachabilityCreateWithName(nil, nodename) else { throw ReachabilityError.FailedToCreateWithHostname(hostname) }

        self.init(reachabilityRef: ref)
    }

    public class func reachabilityForInternetConnection() throws -> Reachability {
        
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(sizeofValue(zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        guard let ref = withUnsafePointer(&zeroAddress, {
            SCNetworkReachabilityCreateWithAddress(nil, UnsafePointer($0))
        }) else { throw ReachabilityError.FailedToCreateWithAddress(zeroAddress) }
        
        return Reachability(reachabilityRef: ref)
    }

    public class func reachabilityForLocalWiFi() throws -> Reachability {

        var localWifiAddress: sockaddr_in = sockaddr_in(sin_len: __uint8_t(0), sin_family: sa_family_t(0), sin_port: in_port_t(0), sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        localWifiAddress.sin_len = UInt8(sizeofValue(localWifiAddress))
        localWifiAddress.sin_family = sa_family_t(AF_INET)

        // IN_LINKLOCALNETNUM is defined in <netinet/in.h> as 169.254.0.0
        let address: UInt32 = 0xA9FE0000
        localWifiAddress.sin_addr.s_addr = in_addr_t(address.bigEndian)

        guard let ref = withUnsafePointer(&localWifiAddress, {
            SCNetworkReachabilityCreateWithAddress(nil, UnsafePointer($0))
        }) else { throw ReachabilityError.FailedToCreateWithAddress(localWifiAddress) }
        
        return Reachability(reachabilityRef: ref)
    }

    // MARK: - *** Notifier methods ***
    public func startNotifier() throws {

        if notifierRunning { return }
        
        var context = SCNetworkReachabilityContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        context.info = UnsafeMutablePointer(Unmanaged.passUnretained(self).toOpaque())
        
        if !SCNetworkReachabilitySetCallback(reachabilityRef!, callback, &context) {
            stopNotifier()
            throw ReachabilityError.UnableToSetCallback
        }

        if !SCNetworkReachabilitySetDispatchQueue(reachabilityRef!, reachabilitySerialQueue) {
            stopNotifier()
            throw ReachabilityError.UnableToSetDispatchQueue
        }

        notifierRunning = true
    }
    

    public func stopNotifier() {
        if let reachabilityRef = reachabilityRef {
            SCNetworkReachabilitySetCallback(reachabilityRef, nil, nil)
            SCNetworkReachabilitySetDispatchQueue(reachabilityRef, nil)
        }
        notifierRunning = false
    }

    // MARK: - *** Connection test methods ***
    
    private func reachabilityStatus(cellularType: CellularType) -> NetworkStatus {
        if isReachable() {
            if isReachableViaWiFi() {
                return .ReachableViaWiFi
            }
            if isRunningOnDevice,
                let radio = telephonyInfo.currentRadioAccessTechnology {
                    return .ReachableViaWWAN(CellularType(radioConstant: radio))
            }
        }
        
        return .NotReachable
    }
    
    public func isReachable() -> Bool {
        return isReachableWithTest({ (flags: SCNetworkReachabilityFlags) -> (Bool) in
            return self.isReachableWithFlags(flags)
        })
    }

    public func isReachableViaWWAN() -> Bool {

        if isRunningOnDevice {
            return isReachableWithTest() { flags -> Bool in
                if self.isReachable(flags) {

                    // Now, check we're on WWAN
                    if self.isOnWWAN(flags) {
                        return true
                    }
                }
                return false
            }
        }
        return false
    }
    
    public func isReachableFast() -> Bool {
        return currentReachabilityStatus.reachableFast()
    }

    public func isReachableViaWiFi() -> Bool {

        return isReachableWithTest() { flags -> Bool in

            // Check we're reachable
            if self.isReachable(flags) {

                if self.isRunningOnDevice {
                    // Check we're NOT on WWAN
                    if self.isOnWWAN(flags) {
                        return false
                    }
                }
                return true
            }

            return false
        }
    }

    // MARK: - *** Private methods ***
    private var isRunningOnDevice: Bool = {
        #if (arch(i386) || arch(x86_64)) && os(iOS)
            return false
            #else
            return true
        #endif
        }()

    private var notifierRunning = false
    private var reachabilityRef: SCNetworkReachability?
    private let reachabilitySerialQueue = dispatch_queue_create("uk.co.ashleymills.reachability", DISPATCH_QUEUE_SERIAL)

    private func reachabilityChanged(flags: SCNetworkReachabilityFlags) {
        print("Pong callback!")
        if let networkStatusChanged = networkStatusChanged {
            networkStatusChanged(currentReachabilityStatus)
        }
        
        if isReachableWithFlags(flags) {
            if let block = whenReachable {
                block(self)
            }
        } else {
            if let block = whenUnreachable {
                block(self)
            }
        }

        notificationCenter.postNotificationName(ReachabilityChangedNotification, object:self)
    }

    private func isReachableWithFlags(flags: SCNetworkReachabilityFlags) -> Bool {

        let reachable = isReachable(flags)

        if !reachable {
            return false
        }

        if isConnectionRequiredOrTransient(flags) {
            return false
        }

        if isRunningOnDevice {
            if isOnWWAN(flags) && !reachableOnWWAN {
                // We don't want to connect when on 3G.
                return false
            }
        }

        return true
    }

    private func isReachableWithTest(test: (SCNetworkReachabilityFlags) -> (Bool)) -> Bool {

        if let reachabilityRef = reachabilityRef {
            
            var flags = SCNetworkReachabilityFlags(rawValue: 0)
            let gotFlags = withUnsafeMutablePointer(&flags) {
                SCNetworkReachabilityGetFlags(reachabilityRef, UnsafeMutablePointer($0))
            }
            
            if gotFlags {
                return test(flags)
            }
        }

        return false
    }

    // WWAN may be available, but not active until a connection has been established.
    // WiFi may require a connection for VPN on Demand.
    private func isConnectionRequired() -> Bool {
        return connectionRequired()
    }

    private func connectionRequired() -> Bool {
        return isReachableWithTest({ (flags: SCNetworkReachabilityFlags) -> (Bool) in
            return self.isConnectionRequired(flags)
        })
    }

    // Dynamic, on demand connection?
    private func isConnectionOnDemand() -> Bool {
        return isReachableWithTest({ (flags: SCNetworkReachabilityFlags) -> (Bool) in
            return self.isConnectionRequired(flags) && self.isConnectionOnTrafficOrDemand(flags)
        })
    }

    // Is user intervention required?
    private func isInterventionRequired() -> Bool {
        return isReachableWithTest({ (flags: SCNetworkReachabilityFlags) -> (Bool) in
            return self.isConnectionRequired(flags) && self.isInterventionRequired(flags)
        })
    }

    private func isOnWWAN(flags: SCNetworkReachabilityFlags) -> Bool {
        #if os(iOS)
            return flags.contains(.IsWWAN)
        #else
            return false
        #endif
    }
    private func isReachable(flags: SCNetworkReachabilityFlags) -> Bool {
        return flags.contains(.Reachable)
    }
    private func isConnectionRequired(flags: SCNetworkReachabilityFlags) -> Bool {
        return flags.contains(.ConnectionRequired)
    }
    private func isInterventionRequired(flags: SCNetworkReachabilityFlags) -> Bool {
        return flags.contains(.InterventionRequired)
    }
    private func isConnectionOnTraffic(flags: SCNetworkReachabilityFlags) -> Bool {
        return flags.contains(.ConnectionOnTraffic)
    }
    private func isConnectionOnDemand(flags: SCNetworkReachabilityFlags) -> Bool {
        return flags.contains(.ConnectionOnDemand)
    }
    func isConnectionOnTrafficOrDemand(flags: SCNetworkReachabilityFlags) -> Bool {
        return !flags.intersect([.ConnectionOnTraffic, .ConnectionOnDemand]).isEmpty
    }
    private func isTransientConnection(flags: SCNetworkReachabilityFlags) -> Bool {
        return flags.contains(.TransientConnection)
    }
    private func isLocalAddress(flags: SCNetworkReachabilityFlags) -> Bool {
        return flags.contains(.IsLocalAddress)
    }
    private func isDirect(flags: SCNetworkReachabilityFlags) -> Bool {
        return flags.contains(.IsDirect)
    }
    private func isConnectionRequiredOrTransient(flags: SCNetworkReachabilityFlags) -> Bool {
        let testcase:SCNetworkReachabilityFlags = [.ConnectionRequired, .TransientConnection]
        return flags.intersect(testcase) == testcase
    }

    private var reachabilityFlags: SCNetworkReachabilityFlags {
        if let reachabilityRef = reachabilityRef {
            
            var flags = SCNetworkReachabilityFlags(rawValue: 0)
            let gotFlags = withUnsafeMutablePointer(&flags) {
                SCNetworkReachabilityGetFlags(reachabilityRef, UnsafeMutablePointer($0))
            }
            
            if gotFlags {
                return flags
            }
        }

        return []
    }

    override public var description: String {

        var W: String
        if isRunningOnDevice {
            W = isOnWWAN(reachabilityFlags) ? "W" : "-"
        } else {
            W = "X"
        }
        let R = isReachable(reachabilityFlags) ? "R" : "-"
        let c = isConnectionRequired(reachabilityFlags) ? "c" : "-"
        let t = isTransientConnection(reachabilityFlags) ? "t" : "-"
        let i = isInterventionRequired(reachabilityFlags) ? "i" : "-"
        let C = isConnectionOnTraffic(reachabilityFlags) ? "C" : "-"
        let D = isConnectionOnDemand(reachabilityFlags) ? "D" : "-"
        let l = isLocalAddress(reachabilityFlags) ? "l" : "-"
        let d = isDirect(reachabilityFlags) ? "d" : "-"

        return "\(W)\(R) \(c)\(t)\(i)\(C)\(D)\(l)\(d)"
    }

    deinit {
        stopNotifier()

        reachabilityRef = nil
        whenReachable = nil
        whenUnreachable = nil
        
        notificationCenter.removeObserver(self, name: CTRadioAccessTechnologyDidChangeNotification, object: nil)
        notificationCenter.removeObserver(self, name: UIApplicationDidBecomeActiveNotification, object: nil)
    }
}

public func ==(left: Reachability.NetworkStatus, right: Reachability.NetworkStatus) -> Bool {
    return left.description == right.description
}

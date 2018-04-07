//
//  DispatchQueue+Extention.swift
//  YYAsyncLayerDemo
//
//  Created by roy.cao on 05/04/2018.
//  Copyright © 2018 roy.cao. All rights reserved.
//

import Foundation


extension DispatchQueue {
    
    private static var _onceTracker = [String]()
    
    public class func once(token: String, block: () -> Void) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        
        if _onceTracker.contains(token) {
            return
        }
        _onceTracker.append(token)
        block()
    }
}

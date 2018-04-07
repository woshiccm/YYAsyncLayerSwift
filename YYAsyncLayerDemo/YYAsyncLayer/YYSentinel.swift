//
//  YYSentinel.swift
//  YYAsyncLayerDemo
//
//  Created by roy.cao on 05/04/2018.
//  Copyright © 2018 roy.cao. All rights reserved.
//

import Foundation

/**
 线程安全的计数器
 YYSentine对OSAtomicIncrement32()函数的封装, 改函数为一个线程安全的计数器,用于判断异步绘制任务是否被取消
 */
class YYSentinel: NSObject {
    
    private var _value: Int32 = 0
    
    public var value: Int32 {
        return _value
    }
    
    @discardableResult
    public func increase() -> Int32 {
        
        // OSAtomic原子操作更趋于数据的底层，从更深层次来对单例进行保护。同时，它没有阻断其它线程对函数的访问。
        return OSAtomicIncrement32(&_value)
    }
}

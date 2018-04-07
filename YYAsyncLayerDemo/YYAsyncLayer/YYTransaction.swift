//
//  YYTransaction.swift
//  YYAsyncLayerDemo
//
//  Created by roy.cao on 05/04/2018.
//  Copyright © 2018 roy.cao. All rights reserved.
//

import Foundation

private let onceToken = UUID().uuidString
private var transactionSet: Set<YYTransaction>?
private func YYTransactionSetup() {
    
    DispatchQueue.once(token: onceToken) {
        transactionSet = Set()
        /// 获取main RunLoop
        let runloop = CFRunLoopGetCurrent()
        var observer: CFRunLoopObserver?
        
        //RunLoop循环的回调
        let YYRunLoopObserverCallBack: CFRunLoopObserverCallBack = {_,_,_ in
            guard (transactionSet?.count) ?? 0 > 0 else { return }
            let currentSet = transactionSet
            //取完上一次需要调用的YYTransaction事务对象后后进行清空
            transactionSet = Set()
            //遍历set，执行里面的selector
            for transaction in currentSet! {
                _ = (transaction.target as AnyObject).perform(transaction.selector)
            }
        }
        
        /**
         创建一个RunLoop的观察者
         allocator：该参数为对象内存分配器，一般使用默认的分配器kCFAllocatorDefault。或者nil
         activities：该参数配置观察者监听Run Loop的哪种运行状态，这里我们监听beforeWaiting和exit状态
         repeats：CFRunLoopObserver是否循环调用。
         order：CFRunLoopObserver的优先级，当在Runloop同一运行阶段中有多个CFRunLoopObserver时，根据这个来先后调用CFRunLoopObserver，0为最高优先级别。正常情况下使用0。
         callout：观察者的回调函数，在Core Foundation框架中用CFRunLoopObserverCallBack重定义了回调函数的闭包。
         context：观察者的上下文。 (类似与KVO传递的context，可以传递信息，)因为这个函数创建ovserver的时候需要传递进一个函数指针，而这个函数指针可能用在n多个oberver 可以当做区分是哪个observer的状机态。（下面的通过block创建的observer一般是一对一的，一般也不需要Context，），还有一个例子类似与NSNOtificationCenter的 SEL和 Block方式
         */
        observer = CFRunLoopObserverCreate(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue,
            true,
            0xFFFFFF,
            YYRunLoopObserverCallBack,
            nil
        )
        //将观察者添加到主线程runloop的common模式下的观察中
        CFRunLoopAddObserver(runloop, observer, .commonModes)
        observer = nil
    }
}


/**
 YYTransaction let you perform a selector once before current runloop sleep.
 */
class YYTransaction: NSObject {
    
    var target: Any?
    var selector: Selector?
    
    
    /**
     创建和返回一个transaction通过一个定义的target和selector
     
     @param target   执行target，target会在runloop结束前被retain
     @param selector target的selector
     
     @return 1个新的transaction，或者有错误时返回nil
     */
    static func transaction(with target: AnyObject, selector: Selector) -> YYTransaction?{
        
        let t = YYTransaction()
        t.target = target
        t.selector = selector
        return t
    }
    
    /**
     Commit the trancaction to main runloop.
     
     @discussion It will perform the selector on the target once before main runloop's
     current loop sleep. If the same transaction (same target and same selector) has
     already commit to runloop in this loop, this method do nothing.
     */
    func commit() {
        
        guard target != nil && selector != nil else {
            //初始化runloop监听
            YYTransactionSetup()
            //添加行为到Set中
            transactionSet?.insert(self)
            return
        }
    }
    
    
    /**
     因为该对象还要被存放至Set集合中，通过重写isEqual和hash来支持根据selector,target判断相等性.
     确保不会将具有相同target和selector的委托对象放入Set中
     */
    override var hash: Int {
        
        let v1 = selector?.hashValue ?? 0
        let v2 = (target as AnyObject).hashValue ?? 0
        return v1 ^ v2
    }
    
    override func isEqual(_ object: Any?) -> Bool {
        
        guard let other = object as? YYTransaction else {
            return false
        }
        guard other != self else {
            return true
        }
        return other.selector == selector
    }
}









//
//  YYAsyncLayer.swift
//  YYAsyncLayerDemo
//
//  Created by roy.cao on 05/04/2018.
//  Copyright © 2018 roy.cao. All rights reserved.
//

import Foundation
import UIKit

//全局释放队列
private let YYAsyncLayerGetReleaseQueue = DispatchQueue.global(qos: .utility)
private let onceToken = UUID().uuidString
private let MAX_QUEUE_COUNT = 16
private var  queueCount = 0
private var queues = [DispatchQueue](repeating: DispatchQueue(label: ""), count: MAX_QUEUE_COUNT)
private var counter: Int32 = 0

//全局显示队列，给content渲染用
private let YYAsyncLayerGetDisplayQueue: DispatchQueue = {
    //GCD只运行一次。使用字符串token作为once的ID，执行once的时候加了一个锁，避免多线程下的token判断不准确的问题。
    DispatchQueue.once(token: onceToken) {
        // https://cnbin.github.io/blog/2015/05/21/nsprocessinfo-huo-qu-jin-cheng-xin-xi/
        // queueCount = 运行该进程的系统的处于激活状态的处理器数量
        queueCount = ProcessInfo().activeProcessorCount
        //处理器数量，最多创建16个serial线程
        queueCount = queueCount < 1 ? 1 : queueCount > MAX_QUEUE_COUNT ? MAX_QUEUE_COUNT : queueCount
        //创建指定数量的串行队列存放在队列数组中
        for i in 0 ..< queueCount {
            queues[i] = DispatchQueue(label: "com.ibireme.MTkit.render")
        }
    }
    //此为线程安全的自增计数,每调用一次+1
    var cur = OSAtomicIncrement32(&counter)
    if cur < 0 {
        cur = -cur
    }
    return queues[Int(cur) % queueCount]
}()

/**
 YYAsyncLayer是异步渲染的CALayer子类
 */
class YYAsyncLayer: CALayer {
    
    //是否异步渲染
    var displaysAsynchronously = true
    //计数，用于取消异步绘制
    var _sentinel: YYSentinel!
    var scale: CGFloat = 0
    private let _onceToken = UUID().uuidString
    
    override class func defaultValue(forKey key: String) -> Any? {
        if key == "displaysAsynchronously" {
            return true
        } else {
            return super.defaultValue(forKey: key)
        }
    }
    
    override init() {
        super.init()
        DispatchQueue.once(token: _onceToken) {
            scale = UIScreen.main.scale
        }
        //默认异步,每个图层都配置一个计数器
        contentsScale = scale
        _sentinel = YYSentinel()
    }
    
    //取消绘制
    deinit {
        _sentinel.increase()
    }
    
    //需要重新渲染的时候，取消原来没有完成的异步渲染
    override func setNeedsDisplay() {
        
        self.cancelAsyncDisplay()
        super.setNeedsDisplay()
    }
    
    /**
     重写展示方法，设置contents内容
     */
    override func display() {
        
        super.contents = super.contents
        displayAsync(async: displaysAsynchronously)
    }
    
    func displayAsync(async: Bool) {
        //获取delegate对象，这边默认是CALayer的delegate，持有它的UIView
        guard let delegate = self.delegate as? YYAsyncLayerDelegate else { return }
        //delegate的初始化方法
        let task = delegate.newAsyncDisplayTask
        
        if task.display == nil {
            task.willDisplay?(self)
            contents = nil
            task.didDisplay?(self, true)
            return
        }
        
        if async {
            task.willDisplay?(self)
            let sentinel = _sentinel
            let value = sentinel!.value
            //判断是否要取消的block，在displayblock调用绘制前，可以通过判断isCancelled布尔值的值来停止绘制，减少性能上的消耗，以及避免出现线程阻塞的情况，比如TableView快速滑动的时候，就可以通过这样的判断，来避免不必要的绘制，提升滑动的流畅性.
            let isCancelled = {
                return value != sentinel!.value
            }
            let size = bounds.size
            let opaque = isOpaque
            let scale = contentsScale
            var backgroundColor = (opaque && (self.backgroundColor != nil)) ? self.backgroundColor : nil
            
            // 当图层宽度或高度小于1时(此时没有绘制意义)
            if size.width < 1 || size.height < 1 {
                //获取contents内容
                var image = contents
                //清除内容
                contents = nil
                //当图层内容为图片时,将释放操作留在并行释放队列中进行
                if (image != nil) {
                    YYAsyncLayerGetReleaseQueue.async {
                        image = nil
                    }
                    //已经展示完成block，finish为yes
                    task.didDisplay?(self, true)
                    backgroundColor = nil
                    return
                }
            }
            
            // 异步绘制
            YYAsyncLayerGetDisplayQueue.async {
                guard !isCancelled() else { return }
                
                /**
                系统会维护一个CGContextRef的栈，UIGraphicsGetCurrentContext()会取出栈顶的context，所以在setFrame调用UIGraphicsGetCurrentContext(), 但获得的上下文总是nil。只能在drawRect里调用UIGraphicsGetCurrentContext()，
                因为在drawRect之前，系统会往栈里面压入一个valid的CGContextRef，除非自己去维护一个CGContextRef，否则不应该在其他地方取CGContextRef。
                那如果就像在drawRect之外获得context怎么办？那只能自己创建位图上下文了
                */
                
                /**
                UIGraphicsBeginImageContext这个方法也可以来获取图形上下文进行绘制的话就会出现你绘制出来的图片相当的模糊，其实原因很简单
                因为 UIGraphicsBeginImageContext(size) = UIGraphicsBeginImageContextWithOptions(size,NO,1.0)
                */
                
                /**
                 创建一个图片类型的上下文。调用UIGraphicsBeginImageContextWithOptions函数就可获得用来处理图片的图形上下文。利用该上下文，你就可以在其上进行绘图，并生成图片
                 
                 第一个参数表示所要创建的图片的尺寸
                 第二个参数表示这个图层是否完全透明，一般情况下最好设置为YES，这样可以让图层在渲染的时候效率更高
                 第三个参数指定生成图片的缩放因子，这个缩放因子与UIImage的scale属性所指的含义是一致的。传入0则表示让图片的缩放因子根据屏幕的分辨率而变化，所以我们得到的图片不管是在单分辨率还是视网膜屏上看起来都会很好
                 */
                UIGraphicsBeginImageContextWithOptions(size, opaque, scale)
                guard let context = UIGraphicsGetCurrentContext() else { return }
                
                //将坐标系上下翻转
                context.textMatrix = CGAffineTransform.identity
                context.translateBy(x: 0, y: self.bounds.height)
                context.scaleBy(x: 1, y: -1)
                
                if opaque {
                    /**
                    使用Quartz时涉及到一个图形上下文，其中图形上下文中包含一个保存过的图形状态堆栈。在Quartz创建图形上下文时，该堆栈是空的。CGContextSaveGState函数的作用是将当前图形状态推入堆栈。之后，您对图形状态所做的修改会影响随后的描画操作，但不影响存储在堆栈中的拷贝。在修改完成后，您可以通过CGContextRestoreGState函数把堆栈顶部的状态弹出，返回到之前的图形状态。这种推入和弹出的方式是回到之前图形状态的快速方法，避免逐个撤消所有的状态修改；这也是将某些状态（比如裁剪路径）恢复到原有设置的唯一方式。
                    */
                    context.saveGState()
                    if backgroundColor == nil || backgroundColor!.alpha < 1 {
                        //设置填充颜色，setStrokeColor为边框颜色
                        context.setFillColor(UIColor.white.cgColor)
                        //添加矩形边框路径
                        context.addRect(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
                        context.fillPath()
                    }
                    
                    if let backgroundColor = backgroundColor {
                        context.setFillColor(backgroundColor)
                        context.addRect(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
                        context.fillPath()
                    }
                    
                    context.restoreGState()
                    backgroundColor = nil
                }
                
                task.display?(context, size, isCancelled)
                
                //若取消 则释放资源,取消绘制
                if isCancelled() {
                    //调用UIGraphicsEndImageContext函数关闭图形上下文
                    UIGraphicsEndImageContext()
                    DispatchQueue.main.async {
                        task.didDisplay?(self, false)
                    }
                    return
                }
                
                //UIGraphicsGetImageFromCurrentImageContext函数可从当前上下文中获取一个UIImage对象
                let image = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                
                //若取消 则释放资源,取消绘制
                if isCancelled() {
                    UIGraphicsEndImageContext()
                    DispatchQueue.main.async {
                        task.didDisplay?(self, false)
                    }
                    return
                }
                
                //主线程异步将绘制结果的图片赋值给contents
                DispatchQueue.main.async {
                    if isCancelled() {
                        task.didDisplay?(self, false)
                    }else{
                        self.contents = image?.cgImage
                        task.didDisplay?(self, true)
                    }
                }

            }

        }else{
            _sentinel.increase()
            task.willDisplay?(self)
            UIGraphicsBeginImageContextWithOptions(bounds.size, isOpaque, contentsScale)
            guard let context = UIGraphicsGetCurrentContext() else { return }
            if isOpaque {
                var size = bounds.size
                size.width *= contentsScale
                size.height *= contentsScale
                context.saveGState()
            
                if backgroundColor == nil || backgroundColor!.alpha < 1 {
                    context.setFillColor(UIColor.white.cgColor)
                    context.addRect(CGRect(origin: .zero, size: size))
                    context.fillPath()
                }
                if let backgroundColor = backgroundColor {
                    context.setFillColor(backgroundColor)
                    context.addRect(CGRect(origin: .zero, size: size))
                    context.fillPath()
                }
                context.restoreGState()
            }
            
            task.display?(context, bounds.size, {return false })
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            contents = image?.cgImage
            task.didDisplay?(self, true)
            
        }
    }
    
    
    private func cancelAsyncDisplay() {
        // 增加计数，标明取消之前的渲染
        _sentinel.increase()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

/**
 YYAsyncLayer's的delegate协议，一般是uiview。必须实现这个方法
 */
protocol YYAsyncLayerDelegate {
    
    //当layer的contents需要更新的时候，返回一个新的展示任务
    var newAsyncDisplayTask:  YYAsyncLayerDisplayTask { get }
}

/**
 YYAsyncLayer在后台渲染contents的显示任务类
 */
open class YYAsyncLayerDisplayTask: NSObject {
    
    /**
     这个block会在异步渲染开始的前调用，只在主线程调用。
     */
    public var willDisplay: ((CALayer) -> Void)?
    
    /**
     这个block会调用去显示layer的内容
     */
    public var display: ((_ context: CGContext, _ size: CGSize, _ isCancelled: (() -> Bool)?) -> Void)?
    
    /**
     这个block会在异步渲染结束后调用，只在主线程调用。
     */
    public var didDisplay: ((_ layer: CALayer, _ finished: Bool) -> Void)?
}












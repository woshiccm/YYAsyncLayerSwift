[YYAsyncLayer](https://github.com/ibireme/YYAsyncLayer)是[ibireme](https://blog.ibireme.com/author/ibireme/)开源用于图层异步绘制的一个组件,将耗时操作(如文本布局计算)放在RunLoop空闲时去做,进而减少卡顿，代码我也是写了Swift版本。

# YYAsyncLayer结构
YYAsyncLayer一共分为三个部分：     
1. **YYTransaction**：将YYAsyncLayer委托的绘制任务注册Runloop调用，在RunLoop空闲时执行    
2. **YYSentine**：线程安全的计数器，用于判断异步绘制任务是否被取消    
3. **YYAsyncLayer**：CALayer子类，用来异步渲染layer内容   

>YYAsyncLayer内使用YYTransaction在 RunLoop 中注册了一个 Observer，监视的事件和 Core Animation 一样，但优先级比 CA 要低。当 RunLoop 进入休眠前、CA 处理完事件后，YYTransaction 就会执行该 loop 内提交的所有任务。 在YYAsyncLayer中，通过重写CALayer显示display方法，向delegate请求一个异步绘制的任务，并且在子线程中绘制Core Graphic对象，最后再回到主线程中设置layer.contents内容。    

>YYAsyncLayer 是 CALayer 的子类，当它需要显示内容（比如调用了 [layer setNeedDisplay]）时，它会向 delegate，也就是 UIView 请求一个异步绘制的任务。在异步绘制时，Layer 会传递一个 BOOL(^isCancelled)() 这样的 block，绘制代码可以随时调用该 block 判断绘制任务是否已经被取消。

异步绘制思路图
![](https://upload-images.jianshu.io/upload_images/1121012-86524da67fb8b094.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/700)



# YYTransaction


YYTransaction绘制任务的机制仿照CoreAnimation的绘制机制，监听主线程RunLoop，在空闲阶段插入绘制任务，并将任务优先级设置在CoreAnimation绘制完成之后，然后遍历绘制任务集合进行绘制工作并且清空集合。

>事务是通过CATransaction类来做管理，这个类的设计有些奇怪，不像你从它的命名预期的那样去管理一个简单的事务，而是管理了一叠你不能访问的事务。CATransaction没有属性或者实例方法，并且也不能用+alloc和-init方法创建它。但是可以用+begin和+commit分别来入栈或者出栈。
任何可以做动画的图层属性都会被添加到栈顶的事务，你可以通过+setAnimationDuration:方法设置当前事务的动画时间，或者通过+animationDuration方法来获取值（默认0.25秒）。
Core Animation在每个run loop周期中自动开始一次新的事务（run loop是iOS负责收集用户输入，处理定时器或者网络事件并且重新绘制屏幕的东西），即使你不显式的用[CATransaction begin]开始一次事务，任何在一次run loop循环中属性的改变都会被集中起来，然后做一次0.25秒的动画。



YYTransaction存储了target和selector，并且在runloop中注册kCFRunLoopBeforeWaiting与kCFRunLoopExit。   
主线程 RunLoop观察者在RunLoop进入kCFRunLoopBeforeWaiting或kCFRunLoopExit开始执行观察者。   
注意指定了观察者的优先级：0xFFFFFF，这个优先级比CATransaction优先级为2000000的优先级更低。这是为了确保系统的动画优先执行，之后再执行异步渲染。


```Swift   
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
```  


```Swift   
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

```    




# YYSentine   


YYSentine对OSAtomicIncrement32()函数的封装, 改函数为一个线程安全的计数器,用于判断异步绘制任务是否被取消 

```Swift 
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

```


# YYAsyncLayer   
YYAsyncLayer为了异步绘制而继承CALayer的子类。通过使用CoreGraphic相关方法，在子线程中绘制内容Context，绘制完成后，回到主线程对layer.contents进行直接显示。
通过开辟线程进行异步绘制，但是不能无限开辟线程

>我们都知道，把阻塞主线程执行的代码放入另外的线程里保证APP可以及时的响应用户的操作。但是线程的切换也是需要额外的开销的。也就是说，线程不能无限度的开辟下去。     
那么，dispatch_queue_t的实例也不能一直增加下去。有人会说可以用dispatch_get_global_queue()来获取系统的队列。没错，但是这个情况只适用于少量的任务分配。因为，系统本身也会往这个queue里添加任务的。   
所以，我们需要用自己的queue，但是是有限个的。在YY里给这个数量指定的值是16。


## YYAsyncLayerDelegate
YYAsyncLayerDelegate 的 newAsyncDisplayTask 是提供了 YYAsyncLayer 需要在后台队列绘制的内容  

```Swift  
/**
 YYAsyncLayer's的delegate协议，一般是uiview。必须实现这个方法
 */
protocol YYAsyncLayerDelegate {
    
    //当layer的contents需要更新的时候，返回一个新的展示任务
    var newAsyncDisplayTask:  YYAsyncLayerDisplayTask { get }
}
```


## YYAsyncLayerDisplayTask   
display在mainthread或者background thread调用，这要求display应该是线程安全的，这里是通过YYSentinel保证线程安全。willdisplay和didDisplay在mainthread调用。

```Swift 
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
```  



## YYAsyncLayer
YYAsyncLayer是通过创建异步创建图像Context在其绘制，最后再主线程异步添加图像从而实现的异步绘制。同时，在绘制过程中进行了多次进行取消判断，以避免额外绘制.

```Swift
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
    ////GCD只运行一次。使用字符串token作为once的ID，执行once的时候加了一个锁，避免多线程下的token判断不准确的问题。
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

```    

需要注意的是绘制的图片会发生倒置问题，源码中并未进行立正操作。
究其原因是因为CoreGraphics源于Mac OS X系统，在Mac OS X中，坐标原点在左下方并且正y坐标是朝上的，而在iOS中，原点坐标是在左上方并且正y坐标是朝下的。在大多数情况下，这不会出现任何问题，因为图形上下文的坐标系统是会自动调节补偿的。但是创建和绘制一个CGImage对象时就会暴露出倒置问题。所以用到以下函数进行立正

```Swift
context.textMatrix = CGAffineTransform.identity
context.translateBy(x: 0, y: self.bounds.height)
context.scaleBy(x: 1, y: -1)
```














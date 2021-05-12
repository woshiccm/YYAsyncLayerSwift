//
//  AsyncDisplayController.swift
//  VVeboTableViewDemo
//
//  Created by 伯驹 黄 on 2017/4/13.
//  Copyright © 2017年 伯驹 黄. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    fileprivate lazy var tableView: UITableView = {
        let tableView = UITableView(frame: self.view.frame)
        tableView.dataSource = self
        tableView.delegate = self
        return tableView
    }()
    
    lazy var data: [[String]] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.white
        tableView.register(AsyncDisplayCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.global().async {
            self.data = [(0...100).map { "\($0)" }]
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

extension ViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return data.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return data[section].count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
    }
}

extension ViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 66
    }
}

class AsyncDisplayCell: UITableViewCell {
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(AsyncDisplayView(frame: CGRect(x: 15, y: 3, width: 60, height: 60)))
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class AsyncDisplayView: UIView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.red
        
        contentNeedUpdate()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func contentNeedUpdate() {
        layer.setNeedsDisplay()
    }
    
    override class var layerClass: AnyClass {
        return YYAsyncLayer.self
    }
}

extension AsyncDisplayView: YYAsyncLayerDelegate {
    var newAsyncDisplayTask: YYAsyncLayerDisplayTask {
        let task = YYAsyncLayerDisplayTask()
        
        task.willDisplay = { layer in
            
        }
        
        task.display = { context, size, isCancelled in
            guard let cgimage = UIImage(named: "timg")?.cgImage else { return }
            context.draw(cgimage, in: CGRect(origin: .zero, size: CGSize(width: 60, height: 60)))
        }
        
        task.didDisplay = { layer, flag in
            
        }
        
        return task
    }
}


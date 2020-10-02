//
//  ViewController.swift
//  MyApp
//
//  Created by John McIntosh on 10/2/20.
//

import MySDK11
import MySDK12
import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        MySDK11.SDKInterface.launch()
        MySDK12.SDKInterface.launch()
    }
}

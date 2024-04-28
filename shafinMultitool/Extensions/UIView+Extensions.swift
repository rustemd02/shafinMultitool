//
//  UIView+WarningView.swift
//  shafinMultitool
//
//  Created by Рустем on 28.04.2024.
//

import UIKit

extension UIView {
    
    static func warningView(withImageName text: String) -> UIView {
        let warningView = UIView()
        warningView.backgroundColor = .red.withAlphaComponent(0.3)
        warningView.layer.cornerRadius = 10
        warningView.layer.masksToBounds = true
        warningView.applyBlurEffect()
        
        warningView.snp.makeConstraints { make in
            make.height.equalTo(45)
            make.width.equalTo(45)
        }
        var warningIcon = UIImage()
        if text == "blur" {
            warningIcon = (UIImage(named: text)?.withTintColor(.white, renderingMode: .alwaysOriginal))!.resize(withSize: CGSize(width: 25, height: 25))
        } else {
            warningIcon = (UIImage(systemName: text)?.withTintColor(.white, renderingMode: .alwaysOriginal))!
        }
        let warningIconView = UIImageView(image: warningIcon)
        warningView.addSubview(warningIconView)
        warningIconView.layer.masksToBounds = true
        
        warningIconView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        return warningView
    }
}

//
//  UIView+WarningView.swift
//  shafinMultitool
//
//  Created by Рустем on 28.04.2024.
//

import UIKit
import SnapKit

extension UIView {
    
    static func warningView(withImageName text: String) -> UIView {
        let warningView = UIView()
        warningView.configureWarningView(withImageName: text)
        
        warningView.snp.makeConstraints { make in
            make.height.equalTo(45)
            make.width.equalTo(45)
        }
        
        return warningView
    }

    func configureWarningView(withImageName text: String) {
        backgroundColor = .red.withAlphaComponent(0.3)
        layer.cornerRadius = 10
        layer.masksToBounds = true
        applyBlurEffect()

        subviews.forEach { $0.removeFromSuperview() }

        let warningIcon: UIImage
        if text == "blur" {
            warningIcon = (UIImage(named: text)?.withTintColor(.white, renderingMode: .alwaysOriginal))!.resize(withSize: CGSize(width: 25, height: 25))
        } else {
            warningIcon = (UIImage(systemName: text)?.withTintColor(.white, renderingMode: .alwaysOriginal))!
        }
        let warningIconView = UIImageView(image: warningIcon)
        addSubview(warningIconView)
        warningIconView.layer.masksToBounds = true

        warningIconView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
    
    func shake(duration timeDuration: Double = 0.07, repeat countRepeat: Float = 3){
        let animation = CABasicAnimation(keyPath: "position")
        animation.duration = timeDuration
        animation.repeatCount = countRepeat
        animation.autoreverses = true
        animation.fromValue = NSValue(cgPoint: CGPoint(x: self.center.x - 10, y: self.center.y))
        animation.toValue = NSValue(cgPoint: CGPoint(x: self.center.x + 10, y: self.center.y))
        self.layer.add(animation, forKey: "position")
    }
}

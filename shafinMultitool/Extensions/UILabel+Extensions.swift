//
//  UILabel+Extensions.swift
//  shafinMultitool
//
//  Created by Рустем on 28.04.2024.
//

import UIKit

extension UILabel {
    static func subtitlesNameLabel(withText text: String?) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .boldSystemFont(ofSize: 16)
        label.textColor = .yellow
        label.textAlignment = .center
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowRadius = 3.0
        label.layer.shadowOpacity = 1.0
        label.layer.shadowOffset = CGSize(width: 4, height: 4)
        label.layer.masksToBounds = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    static func subtitlesPhraseLabel(withText text: String?) -> UILabel {
        let label = subtitlesNameLabel(withText: text)
        label.font = .systemFont(ofSize: 16)
        label.textColor = .white
        return label
    }
}

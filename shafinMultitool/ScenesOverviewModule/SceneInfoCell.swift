//
//  SceneCell.swift
//  shafinMultitool
//
//  Created by Рустем on 11.11.2023.
//

import UIKit

class SceneInfoCell: UICollectionViewCell {
    
    var titleLabel = UILabel()
    var deleteButton = UIButton()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setupCell() {
        contentView.backgroundColor = .clear
        contentView.addSubview(titleLabel)
        self.layer.cornerRadius = 10
        self.layer.borderWidth = 1.0
        self.layer.borderColor = UIColor.lightGray.cgColor
        
        self.layer.backgroundColor = UIColor.white.cgColor
        self.layer.shadowColor = UIColor.gray.cgColor
        self.layer.shadowOffset = CGSize(width: 2.0, height: 4.0)
        self.layer.shadowRadius = 2.0
        self.layer.shadowOpacity = 1.0
        self.layer.masksToBounds = false
        
        titleLabel.font = .boldSystemFont(ofSize: 24)
        titleLabel.textAlignment = .center
        titleLabel.textColor = .black
        titleLabel.numberOfLines = 0
        titleLabel.snp.makeConstraints { make in
            make.leadingMargin.equalTo(contentView.snp_leadingMargin)
            make.trailingMargin.equalTo(contentView.snp_trailingMargin)
            make.center.equalTo(contentView)

        }
        
        contentView.addSubview(deleteButton)
        deleteButton.setImage(UIImage(systemName: "trash.circle.fill"), for: .normal)
        deleteButton.tintColor = .black
        deleteButton.contentVerticalAlignment = .fill
        deleteButton.contentHorizontalAlignment = .fill
        deleteButton.snp.makeConstraints { make in
            make.width.height.equalTo(30)
            make.top.equalTo(contentView.snp.top).offset(7)
            make.trailing.equalTo(contentView.snp.trailing).offset(-7)
        }
    }
    
    func resizeLabel(size: Int) {
        titleLabel.font = .boldSystemFont(ofSize: CGFloat(integerLiteral: size))
    }
        
}

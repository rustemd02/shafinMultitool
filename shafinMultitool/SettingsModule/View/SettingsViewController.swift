//
//  SettingsViewController.swift
//  shafinMultitool
//
//  Created by Рустем on 15.05.2023.
//

import UIKit

protocol SettingsViewProtocol: AnyObject {

}

class SettingsViewController: UIViewController {
    
    // MARK: - Properties
    var presenter: SettingsPresenterProtocol?
    private let resolutionLabel = UILabel()
    private let resolutionPicker = UIPickerView()
    
    private let submitButton = UIButton()
    
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        presenter?.viewDidLoad()
        setupUI()
        submitButton.addTarget(self, action: #selector(submitButtonPressed), for: .touchUpInside)
        resolutionPicker.dataSource = self
        resolutionPicker.delegate = self
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        resolutionPicker.selectRow(presenter?.getCurrentRow() ?? 0, inComponent: 0, animated: false)
        super.viewDidAppear(animated)
    }
    
    // MARK: - Private functions
    private func setupUI() {
        view.backgroundColor = .black.withAlphaComponent(0.5)
    
        view.addSubview(resolutionPicker)
        resolutionPicker.snp.makeConstraints { make in
            make.top.equalTo(view.snp_topMargin).offset(25)
            make.right.equalTo(view.snp_rightMargin).offset(25)
        }
        
        view.addSubview(resolutionLabel)
        resolutionLabel.text = "Разрешение"
        resolutionLabel.textColor = .white
        resolutionLabel.font = .boldSystemFont(ofSize: 25)
        resolutionLabel.snp.makeConstraints { make in
            make.centerY.equalTo(resolutionPicker.snp_centerYWithinMargins)
            make.left.equalTo(view.snp_leftMargin).inset(25)
        }
        
        view.addSubview(submitButton)
        submitButton.setTitle("Cохранить", for: .normal)
        submitButton.snp.makeConstraints { make in
            make.bottom.equalTo(view.snp_bottomMargin).inset(25)
            make.right.equalTo(view.snp_rightMargin).offset(30)
        }
    }
    
    @objc
    private func submitButtonPressed() {
        presenter?.submitButtonPressed()
    }
    
    
}

extension SettingsViewController: UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        guard let numberOfRows = presenter?.getResolutionsArrayLength() else { return 0 }
        return numberOfRows
    }
    
}

extension SettingsViewController: UIPickerViewDelegate {
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return presenter?.titleForRow(row: row) ?? ""
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        presenter?.didSelectRow(row: row)
    }
}

extension SettingsViewController: SettingsViewProtocol {
   
    
}


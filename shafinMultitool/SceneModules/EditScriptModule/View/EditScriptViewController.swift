//
//  SettingsViewController.swift
//  shafinMultitool
//
//  Created by Рустем on 15.05.2023.
//

import UIKit

protocol EditScriptViewProtocol: AnyObject {

}

class EditScriptViewController: UIViewController {
    
    // MARK: - Properties
    var presenter: EditScriptPresenterProtocol?
    var script: String?
    
    private let settingsBackgroundView = UIView()
    
    private let scriptTextFieldLabel = UILabel()
    private let scriptTextView = UITextView()
    private let submitButton = UIButton()
    
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        self.script = presenter?.fetchScript()
        setupUI()
        submitButton.addTarget(self, action: #selector(submitButtonPressed), for: .touchUpInside)
        
    }

    // MARK: - Private functions
    private func setupUI() {
        view.backgroundColor = .white.withAlphaComponent(0.75)
        view.applyBlurEffect()
        
        view.addSubview(settingsBackgroundView)
        settingsBackgroundView.layer.cornerRadius = 15
        settingsBackgroundView.backgroundColor = .white
        settingsBackgroundView.snp.makeConstraints { make in
            make.topMargin.equalTo(view.snp_topMargin).offset(30)
            make.leftMargin.equalTo(view.snp_leftMargin).inset(45)
            make.rightMargin.equalTo(view.snp_rightMargin).inset(45)
            make.bottomMargin.equalTo(view.snp_bottomMargin).inset(30)
        }
        
        view.addSubview(scriptTextView)
        if let script = self.script {
            scriptTextView.text = script
        }

        scriptTextView.isEditable = true
        scriptTextView.textAlignment = .left
        scriptTextView.returnKeyType = .default
        scriptTextView.backgroundColor = #colorLiteral(red: 0.9607006907, green: 0.9607006907, blue: 0.9607006907, alpha: 1)
        scriptTextView.textColor = .black
        addToolBar(textView: scriptTextView)
        scriptTextView.snp.makeConstraints { make in
            make.topMargin.equalTo(settingsBackgroundView.snp_topMargin).offset(45)
            make.leftMargin.equalTo(settingsBackgroundView.snp_leftMargin).inset(45)
            make.rightMargin.equalTo(settingsBackgroundView.snp_rightMargin).inset(45)
            make.bottomMargin.equalTo(settingsBackgroundView.snp_bottomMargin).inset(45)
        }
        
        let configuration = UIPasteControl.Configuration()
        configuration.baseBackgroundColor = .systemBlue
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.displayMode = .iconOnly
                            
        let pasteButton = UIPasteControl(configuration: configuration)
        pasteButton.frame = CGRect(x: view.bounds.width/2.0, y: view.bounds.height/2.0, width: 120, height: 45)
        scriptTextView.addSubview(pasteButton)


        pasteButton.target = scriptTextView
        
        view.addSubview(scriptTextFieldLabel)
        scriptTextFieldLabel.text = "Введите сценарий"
        scriptTextFieldLabel.font = .boldSystemFont(ofSize: 16)
        scriptTextFieldLabel.textColor = .lightGray
        scriptTextFieldLabel.snp.makeConstraints { make in
            make.leadingMargin.equalTo(scriptTextView.snp_leadingMargin)
            make.bottomMargin.equalTo(scriptTextView.snp_topMargin).offset(-20)
        }
        
        view.addSubview(submitButton)
        submitButton.setTitle("Ок", for: .normal)
        submitButton.setTitleColor(.systemBlue, for: .normal)
        submitButton.snp.makeConstraints { make in
            make.bottom.equalTo(view.snp_bottomMargin).inset(25)
            make.right.equalTo(view.snp_rightMargin).offset(30)
        }
    }
    
    @objc
    private func submitButtonPressed() {
        let newScript = scriptTextView.text ?? ""
        presenter?.submitButtonPressed(newScript: newScript)
    }
}


extension EditScriptViewController: EditScriptViewProtocol {
   
    
}

extension UIView {
    func applyBlurEffect() {
        let blurEffect = UIBlurEffect(style: .light)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)
        blurEffectView.frame = bounds
        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blurEffectView)
    }
}

extension UIViewController: UITextFieldDelegate {
    func addToolBar(textView: UITextView){
        let toolBar = UIToolbar()
        toolBar.barStyle = UIBarStyle.default
        toolBar.isTranslucent = true
        let spaceButton = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(title: "Готово", style: .done, target: self, action: #selector(donePressed))
        toolBar.setItems([spaceButton, doneButton], animated: false)
        toolBar.isUserInteractionEnabled = true
        toolBar.sizeToFit()

        textView.inputAccessoryView = toolBar
    }
    
    @objc func donePressed(){
        view.endEditing(true)
    }

}

extension UIImage {
    func resize(withSize newSize: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { (context) in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

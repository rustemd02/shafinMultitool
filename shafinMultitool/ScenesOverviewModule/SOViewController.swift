//
//  ScenesOverviewViewController.swift
//  shafinMultitool
//
//  Created by Рустем on 07.11.2023.
//

import UIKit

protocol SOViewControllerProtocol: AnyObject {
    func updateUI()
    
}

class SOViewController: UIViewController {
    var presenter: SOPresenter?
    
    private let titleName = UILabel()
    private var sceneNames: [String] = []
    private var scenesListCollectionView: UICollectionView!
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sceneNames = presenter?.getSceneNames() ?? []
        scenesListCollectionView.reloadData()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
    }
    
    private func setupUI() {
        view.backgroundColor = #colorLiteral(red: 0.1125308201, green: 0.1222153977, blue: 0.1352786422, alpha: 1)
        
        scenesListCollectionView = UICollectionView(frame: .zero, collectionViewLayout: setupFlowLayout())
        scenesListCollectionView.translatesAutoresizingMaskIntoConstraints = false
        // выключить индиактор скролла
        scenesListCollectionView.dataSource = self
        scenesListCollectionView.delegate = self
        scenesListCollectionView.register(SceneInfoCell.self, forCellWithReuseIdentifier: "\(SceneInfoCell.self)")
        
        view.addSubview(titleName)
        titleName.text = "Выберите сцену:"
        titleName.font = .systemFont(ofSize: 24, weight: .black)
        titleName.textColor = .white
        titleName.snp.makeConstraints { make in
            make.leadingMargin.equalTo(view.snp_leadingMargin)
            make.topMargin.equalTo(view.safeAreaLayoutGuide).offset(35)
        }
        
        view.addSubview(scenesListCollectionView)
        scenesListCollectionView.backgroundColor = .clear
        scenesListCollectionView.snp.makeConstraints { make in
            make.topMargin.equalTo(titleName.snp_bottomMargin).offset(35)
            make.center.equalToSuperview()
            make.horizontalEdges.equalTo(view)
        }
        
    }
    
    private func setupFlowLayout() -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()
        
        layout.itemSize = .init(width: 150, height: view.frame.height - 150)
        layout.scrollDirection = .horizontal
        
        return layout
    }
    
    @objc
    private func deleteSceneButtonPressed(_ sender: UIButton) {
        let point = sender.convert(CGPoint.zero, to: scenesListCollectionView)
        if let indexPath = scenesListCollectionView.indexPathForItem(at: point) {
            presenter?.deleteScene(with: sceneNames[indexPath.row - 1])
            scenesListCollectionView.deleteItems(at: [indexPath])
        }
        
    }
}
    


extension SOViewController: UICollectionViewDelegate, UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return sceneNames.count + 1
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = scenesListCollectionView.dequeueReusableCell(withReuseIdentifier: "\(SceneInfoCell.self)", for: indexPath) as? SceneInfoCell else { return UICollectionViewCell.init() }
        cell.resizeLabel(size: 24)
        cell.deleteButton.isHidden = false
        if indexPath.item == 0 {
            cell.titleLabel.text = "+"
            cell.resizeLabel(size: 48)
            cell.deleteButton.isHidden = true
            return cell
        }
        
        cell.titleLabel.text = sceneNames[indexPath.item - 1]
        cell.deleteButton.addTarget(self, action: #selector(deleteSceneButtonPressed), for: .touchUpInside)
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let cell = scenesListCollectionView.dequeueReusableCell(withReuseIdentifier: "\(SceneInfoCell.self)", for: indexPath) as? SceneInfoCell else { return }
//        UIView.animate(withDuration: 0.2, animations: {
//            cell.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
//            cell.alpha = 0.8
//        }, completion: { _ in
//            UIView.animate(withDuration: 0.1) {
//                cell.transform = CGAffineTransform(scaleX: 1, y: 1)
//                cell.alpha = 1
//            }
//        })
            
        if indexPath.item == 0 {
            let alertController = UIAlertController(title: "Введите название новой сцены:", message: nil, preferredStyle: .alert)
            
            alertController.addTextField { textField in
                textField.placeholder = "Сцена"
            }
            
            let cancelAction = UIAlertAction(title: "Отмена", style: .cancel, handler: nil)
            let saveAction = UIAlertAction(title: "Сохранить", style: .default) { _ in
                guard let nameTextField = alertController.textFields?.first, let newName = nameTextField.text else { return }
                if self.sceneNames.contains(newName) {
                    collectionView.shake()
                    return
                } else {
                    self.presenter?.loadSceneWithName(title: newName, newScene: true)
                }
            }
            
            alertController.addAction(cancelAction)
            alertController.addAction(saveAction)
            
            present(alertController, animated: true, completion: nil)
            return
        }
        let sceneName = sceneNames[indexPath.item - 1]
        presenter?.loadSceneWithName(title: sceneName, newScene: false)
        
    }
}

extension SOViewController: SOViewControllerProtocol {
    func updateUI() {
        sceneNames = presenter?.getSceneNames() ?? []
    }
}

extension UIView {
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

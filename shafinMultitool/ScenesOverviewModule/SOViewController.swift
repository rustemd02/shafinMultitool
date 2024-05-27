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
    
    private var backgroundImageView = UIImageView()
    private var logoImageView = UIImageView()
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
        
        view.addSubview(backgroundImageView)
        backgroundImageView.image = UIImage(named: "background")!
        backgroundImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
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
        
        view.addSubview(logoImageView)
        logoImageView.image = UIImage(named: "logo_menu")
        logoImageView.alpha = 0.65
        logoImageView.snp.makeConstraints { make in
            make.height.equalTo(30)
            make.width.equalTo(275)
            make.trailingMargin.equalTo(view.snp_trailingMargin)
            make.bottomMargin.equalTo(view.safeAreaLayoutGuide).offset(-15)
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
        guard scenesListCollectionView.dequeueReusableCell(withReuseIdentifier: "\(SceneInfoCell.self)", for: indexPath) is SceneInfoCell else { return }
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

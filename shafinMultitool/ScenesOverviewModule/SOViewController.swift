//
//  ScenesOverviewViewController.swift
//  shafinMultitool
//
//  Created by Рустем on 07.11.2023.
//

import UIKit
import SwiftUI

protocol SOViewControllerProtocol: AnyObject {
    func updateUI()
}

/// Library route root (SET OS Package 3). The controller stays the library
/// behavior owner wired by `SOModuleBuilder`; the visible surface is the SET OS
/// contact sheet, which talks to the presenter through `SETLibraryModel`.
final class SOViewController: UIViewController {
    var presenter: SOPresenter?

    private var libraryModel: SETLibraryModel?
    private var hostingController: UIHostingController<SETLibraryProductionView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = SETPalette.ink.uiColor
        installLibrarySurface()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        libraryModel?.reload()
    }

    private func installLibrarySurface() {
        guard let presenter else { return }
        let model = SETLibraryModel(controlling: presenter)
        libraryModel = model

        let host = UIHostingController(rootView: SETLibraryProductionView(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        hostingController = host
    }
}

extension SOViewController: SOViewControllerProtocol {
    func updateUI() {
        libraryModel?.reload()
    }
}

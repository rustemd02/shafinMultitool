//
//  SORoutre.swift
//  shafinMultitool
//
//  Created by Рустем on 07.11.2023.
//

import Foundation
import SwiftUI

protocol SORouterProtocol: AnyObject {
    func loadSceneWithName(title: String?, newScene: Bool)
}

class SORouter: SORouterProtocol {
    weak var view: SOViewController?
    
    func loadSceneWithName(title: String?, newScene: Bool) {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return }

        if newScene {
            do {
                _ = try DBService.shared.createUnifiedSceneProject(named: title)
            } catch {
                print("Error creating unified scene project: \(error)")
                return
            }
        }

        let viewModel = MainActor.assumeIsolated {
            SceneGeneratorViewModel(projectName: title, isNewProject: false)
        }
        let vc = LandscapeHostingController(
            rootView: SceneGeneratorView(viewModel: viewModel)
        )
        vc.sceneWorkspaceTeardownProvider = viewModel
        vc.disablesInteractivePopGesture = true
        view?.navigationController?.pushViewController(vc, animated: true)
    }
}

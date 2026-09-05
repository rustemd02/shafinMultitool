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
    @discardableResult
    func loadScene(id: UUID) -> Result<Void, SETLibraryFailure>
}

extension SORouterProtocol {
    @discardableResult
    func loadScene(id: UUID) -> Result<Void, SETLibraryFailure> {
        .failure(.unsupported)
    }
}

class SORouter: SORouterProtocol {
    weak var view: SOViewController?
    private let projectStore: DBService
#if DEBUG
    private(set) var testingLastOpenedProjectID: UUID?
#endif

    init(projectStore: DBService = .shared) {
        self.projectStore = projectStore
    }
    
    func loadSceneWithName(title: String?, newScene: Bool) {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return }

        let projectID: UUID
        if newScene {
            do {
                projectID = try projectStore.createUnifiedSceneProject(named: title).id
            } catch {
                print("Error creating unified scene project: \(error)")
                return
            }
        } else {
            guard let summary = projectStore.listUnifiedSceneProjects().first(where: { $0.name == title }) else {
                return
            }
            projectID = summary.id
        }

        _ = loadScene(id: projectID)
    }

    @discardableResult
    func loadScene(id: UUID) -> Result<Void, SETLibraryFailure> {
#if DEBUG
        testingLastOpenedProjectID = nil
#endif
        switch projectStore.loadUnifiedSceneProjectForOpening(id: id) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let record):
            guard record.validation.isOpenable else {
                return .failure(.persistence)
            }

            return pushWorkspace(for: record)
        }
    }

    private func pushWorkspace(
        for record: UnifiedSceneProjectOpenRecord
    ) -> Result<Void, SETLibraryFailure> {

        #if DEBUG
        let launchArguments = ProcessInfo.processInfo.arguments
        let launchConfiguration = SETGalleryLaunchConfiguration(arguments: launchArguments)
        let localeOverride: Locale? = launchArguments.contains(SETGalleryLaunchConfiguration.localeArgument)
            ? launchConfiguration.locale.locale
            : nil
        let reduceMotionOverride: Bool? = launchArguments.contains(SETGalleryLaunchConfiguration.reduceMotionArgument)
            ? launchConfiguration.reduceMotion
            : nil
        let reduceTransparencyOverride: Bool? = launchArguments.contains(SETGalleryLaunchConfiguration.reduceTransparencyArgument)
            ? launchConfiguration.reduceTransparency
            : nil
        let dynamicTypeOverride: DynamicTypeSize? = launchArguments.contains(SETGalleryLaunchConfiguration.dynamicTypeArgument)
            ? launchConfiguration.dynamicTypeSize
            : nil
        #else
        let localeOverride: Locale? = nil
        let reduceMotionOverride: Bool? = nil
        let reduceTransparencyOverride: Bool? = nil
        let dynamicTypeOverride: DynamicTypeSize? = nil
        #endif

        let viewModel = MainActor.assumeIsolated {
            SceneGeneratorViewModel(
                projectName: record.project.name,
                isNewProject: false,
                projectStore: projectStore,
                presentationLocale: localeOverride,
                persistedProject: record.project,
                persistedWorldMap: record.worldMap
            )
        }
#if DEBUG
        testingLastOpenedProjectID = MainActor.assumeIsolated { viewModel.projectID }
#endif
        var rootView = AnyView(SceneGeneratorView(viewModel: viewModel))
        if let localeOverride {
            rootView = AnyView(rootView.environment(\.locale, localeOverride))
        }
        if let reduceMotionOverride {
            rootView = AnyView(rootView.environment(\.setReduceMotionOverride, reduceMotionOverride))
        }
        if let reduceTransparencyOverride {
            rootView = AnyView(rootView.environment(\.setReduceTransparencyOverride, reduceTransparencyOverride))
        }
        if let dynamicTypeOverride {
            rootView = AnyView(rootView.environment(\.dynamicTypeSize, dynamicTypeOverride))
        }
        let vc = LandscapeHostingController(rootView: rootView)
        vc.sceneWorkspaceTeardownProvider = viewModel
        vc.disablesInteractivePopGesture = true
        #if DEBUG
        let shouldAnimate = !(reduceMotionOverride ?? UIAccessibility.isReduceMotionEnabled)
        #else
        let shouldAnimate = !UIAccessibility.isReduceMotionEnabled
        #endif
        view?.navigationController?.pushViewController(vc, animated: shouldAnimate)
        return .success(())
    }
}

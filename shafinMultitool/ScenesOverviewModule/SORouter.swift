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
                projectName: title,
                isNewProject: false,
                presentationLocale: localeOverride
            )
        }
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
    }
}

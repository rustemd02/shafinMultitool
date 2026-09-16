//
//  SceneDelegate.swift
//  shafinMultitool
//
//  Created by Рустем on 25.04.2023.
//

import UIKit
import SwiftUI
#if DEBUG
import AVFoundation
#endif

#if DEBUG
private let uiTestingEnvironmentKey = "SHAFIN_UI_TESTING"
private let uiTestingCameraPermissionArgument = "-SHAFIN_CAMERA_PERMISSION_STATE"
private let uiTestingCameraIntroArgument = "-SHAFIN_CAMERA_INTRO_STATE"
private let uiTestingCameraProductionFixtureArgument = "-SHAFIN_CAMERA_PRODUCTION_FIXTURE"
private let uiTestingLibraryProductionFixtureArgument = "-SHAFIN_LIBRARY_PRODUCTION_FIXTURE"
private let uiTestingLibraryResetArgument = "-SHAFIN_LIBRARY_RESET_FOR_UI_TESTING"
#endif

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var hasLeftActiveScene = false

#if DEBUG
    private static func makeUITestingRootViewController() -> UIViewController {
        let uiTestingConfiguration = CameraCoachUITestingConfiguration(
            arguments: ProcessInfo.processInfo.arguments
        )

        return CommercialShellComposition(
            cameraCoachBuilder: {
                let thermal = ThermalGovernor()
                let cameraManager = CameraManager(
                    scheduler: RealtimeScheduler(),
                    thermalGovernor: thermal,
                    motionGate: MotionGate(),
                    sessionRunner: CameraCoachUITestingSessionRunner(),
                    configuration: .ready,
                    notificationCenter: NotificationCenter()
                )
                let analysisPipeline = AnalysisPipeline(
                    thermalGovernor: thermal,
                    neuralHeavyModelsEnabledProvider: {
                        thermal.nextBudget().heavyModelsEnabled
                    }
                )
                let permissions = CameraCoachUITestingPermissionClient(
                    snapshot: uiTestingConfiguration.cameraSnapshot,
                    recheckSnapshot: uiTestingConfiguration.cameraRecheckSnapshot,
                    requestResult: uiTestingConfiguration.cameraRequestResult
                )
                let dependencies = ContentView.CameraCoachDependencies(
                    cameraManager: cameraManager,
                    viewModel: CameraViewModel(
                        cameraManager: cameraManager,
                        analysisPipeline: analysisPipeline,
                        recordingCoordinatorFactory: ContentView.makeRecordingCoordinatorFactory(
                            cameraManager: cameraManager, permissions: permissions
                        )
                    ),
                    permissionClient: permissions,
                    introStore: CameraCoachUITestingIntroStore(
                        initiallySeen: uiTestingConfiguration.introSeen
                    )
                )
                let viewController = CommercialCameraCoachHostingController(
                    rootView: ContentView(dependencies: dependencies)
                )
                return CommercialCameraCoachRoute(
                    viewController: viewController,
                    cameraViewModel: dependencies.viewModel,
                    entryFlowModel: dependencies.entryFlowModel
                )
            }
        ).makeShell()
    }

    static func makeRootViewController(
        galleryConfiguration: SETGalleryLaunchConfiguration? = nil,
        productionFixtureConfiguration: SETCameraCoachFixtureConfiguration? = nil,
        libraryFixtureConfiguration: SETLibraryFixtureConfiguration? = nil,
        decisionTraceFixtureConfiguration: SETDecisionTraceFixtureConfiguration? = nil,
        benchmarkConfig: DeviceBenchmarkConfig?,
        benchmarkRootBuilder: @escaping (DeviceBenchmarkConfig) -> UIViewController,
        commercialRootBuilder: @escaping () -> UIViewController
    ) -> UIViewController {
        if let galleryConfiguration {
            return UIHostingController(
                rootView: DesignSystemPreviews(configuration: galleryConfiguration)
            )
        }

        if let decisionTraceFixtureConfiguration {
            return UIHostingController(
                rootView: SETDecisionTraceFixtureRoot(
                    configuration: decisionTraceFixtureConfiguration
                )
            )
        }

        if let productionFixtureConfiguration {
            return UIHostingController(
                rootView: SETCameraCoachProductionView(
                    fixtureConfiguration: productionFixtureConfiguration
                )
            )
        }

        if let libraryFixtureConfiguration {
            return UIHostingController(
                rootView: SETLibraryProductionView(
                    fixtureConfiguration: libraryFixtureConfiguration
                )
            )
        }

        if let benchmarkConfig {
            return benchmarkRootBuilder(benchmarkConfig)
        }

        return commercialRootBuilder()
    }
#else
    static func makeRootViewController(
        commercialRootBuilder: @escaping () -> UIViewController
    ) -> UIViewController {
        commercialRootBuilder()
    }
#endif

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        window.backgroundColor = .black
#if DEBUG
        let isUITesting = ProcessInfo.processInfo.environment[uiTestingEnvironmentKey] == "1"
        let launchArguments = ProcessInfo.processInfo.arguments
        if launchArguments.contains(uiTestingLibraryResetArgument) {
            DBService.shared.resetUnifiedSceneProjectsForUITesting()
        }
        let galleryConfiguration = launchArguments.contains(SETGalleryLaunchConfiguration.galleryArgument)
            ? SETGalleryLaunchConfiguration(arguments: launchArguments)
            : nil
        let productionFixtureConfiguration = Self.makeProductionFixtureConfiguration(
            arguments: launchArguments
        )
        let libraryFixtureConfiguration = Self.makeLibraryFixtureConfiguration(
            arguments: launchArguments
        )
        let decisionTraceFixtureConfiguration = Self.makeDecisionTraceFixtureConfiguration(
            arguments: launchArguments
        )
        let rootViewController = Self.makeRootViewController(
            galleryConfiguration: galleryConfiguration,
            productionFixtureConfiguration: productionFixtureConfiguration,
            libraryFixtureConfiguration: libraryFixtureConfiguration,
            decisionTraceFixtureConfiguration: decisionTraceFixtureConfiguration,
            benchmarkConfig: DeviceBenchmarkConfig.fromEnvironment(),
            benchmarkRootBuilder: { benchmarkConfig in
                UIHostingController(
                    rootView: DeviceBenchmarkRootView(config: benchmarkConfig, interactive: true)
                )
            },
            commercialRootBuilder: {
                if isUITesting {
                    return Self.makeUITestingRootViewController()
                }
                return CommercialShellComposition().makeShell()
            }
        )
#else
        let rootViewController = Self.makeRootViewController {
            CommercialShellComposition().makeShell()
        }
#endif
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
    }

#if DEBUG
    private static func makeProductionFixtureConfiguration(
        arguments: [String]
    ) -> SETCameraCoachFixtureConfiguration? {
        guard let index = arguments.firstIndex(of: uiTestingCameraProductionFixtureArgument),
              arguments.indices.contains(index + 1) else {
            return nil
        }

        let fixtureID = arguments[index + 1]
        let galleryConfiguration = SETGalleryLaunchConfiguration(arguments: arguments)
        return SETCameraCoachFixtureConfiguration(
            fixtureID: fixtureID,
            localeIdentifier: galleryConfiguration.locale.rawValue,
            reduceMotion: galleryConfiguration.reduceMotion,
            reduceTransparency: galleryConfiguration.reduceTransparency,
            dynamicTypeSize: galleryConfiguration.dynamicTypeSize
        )
    }

    private static func makeLibraryFixtureConfiguration(
        arguments: [String]
    ) -> SETLibraryFixtureConfiguration? {
        guard let index = arguments.firstIndex(of: uiTestingLibraryProductionFixtureArgument),
              arguments.indices.contains(index + 1) else {
            return nil
        }

        let fixtureID = arguments[index + 1]
        let galleryConfiguration = SETGalleryLaunchConfiguration(arguments: arguments)
        return SETLibraryFixtureConfiguration(
            fixtureID: fixtureID,
            localeIdentifier: galleryConfiguration.locale.rawValue,
            reduceMotion: galleryConfiguration.reduceMotion,
            reduceTransparency: galleryConfiguration.reduceTransparency,
            dynamicTypeSize: galleryConfiguration.dynamicTypeSize
        )
    }

    private static func makeDecisionTraceFixtureConfiguration(
        arguments: [String]
    ) -> SETDecisionTraceFixtureConfiguration? {
        guard let index = arguments.firstIndex(of: SETGalleryLaunchConfiguration.decisionTraceFixtureArgument),
              arguments.indices.contains(index + 1),
              !arguments[index + 1].isEmpty else {
            return nil
        }

        let galleryConfiguration = SETGalleryLaunchConfiguration(arguments: arguments)
        return SETDecisionTraceFixtureConfiguration(
            fixtureID: arguments[index + 1],
            locale: galleryConfiguration.locale.locale,
            reduceMotion: galleryConfiguration.reduceMotion,
            reduceTransparency: galleryConfiguration.reduceTransparency,
            dynamicTypeSize: galleryConfiguration.dynamicTypeSize
        )
    }
#endif

    func sceneWillResignActive(_ scene: UIScene) {
        hasLeftActiveScene = true
    }

    /// M1-004: single UIKit entry point for backgrounding. The shell forwards to
    /// the active route owner exactly once (camera capture owner or scene
    /// workspace teardown); SwiftUI scenePhase handlers converge on the same
    /// idempotent owners and must not become second event owners.
    func sceneDidEnterBackground(_ scene: UIScene) {
        (window?.rootViewController as? CommercialShellViewController)?.handleSceneDidEnterBackground()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard hasLeftActiveScene else { return }
        hasLeftActiveScene = false

        Task { @MainActor [weak self] in
            guard let self else { return }
            (self.window?.rootViewController as? CommercialShellViewController)?.handleAppDidBecomeActive()
        }
    }
}

#if DEBUG
private struct CameraCoachUITestingConfiguration {
    enum PermissionState: String {
        case notDetermined
        case authorized
        case denied
        case restricted
        case unavailable
        case unknown
    }

    let cameraSnapshot: PermissionSnapshot
    let cameraRecheckSnapshot: PermissionSnapshot
    let cameraRequestResult: PermissionSnapshot
    let introSeen: Bool

    init(arguments: [String]) {
        let permissionState = Self.value(
            for: uiTestingCameraPermissionArgument,
            in: arguments
        ).flatMap(PermissionState.init(rawValue:)) ?? .authorized
        let availableSnapshot = Self.snapshot(for: permissionState)

        self.cameraSnapshot = availableSnapshot
        self.cameraRecheckSnapshot = permissionState == .denied
            ? Self.snapshot(for: .authorized)
            : availableSnapshot
        self.cameraRequestResult = permissionState == .notDetermined
            ? Self.snapshot(for: .authorized)
            : availableSnapshot
        self.introSeen = Self.value(
            for: uiTestingCameraIntroArgument,
            in: arguments
        ) != "notSeen"
    }

    private static func value(for argument: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: argument),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func snapshot(for state: PermissionState) -> PermissionSnapshot {
        switch state {
        case .notDetermined:
            return PermissionSnapshot(
                permission: .camera,
                authorization: .notDetermined,
                availability: .available
            )
        case .authorized:
            return PermissionSnapshot(
                permission: .camera,
                authorization: .authorized,
                availability: .available
            )
        case .denied:
            return PermissionSnapshot(
                permission: .camera,
                authorization: .denied,
                availability: .available
            )
        case .restricted:
            return PermissionSnapshot(
                permission: .camera,
                authorization: .restricted,
                availability: .available
            )
        case .unavailable:
            return PermissionSnapshot(
                permission: .camera,
                authorization: .authorized,
                availability: .unavailable(.cameraHardware)
            )
        case .unknown:
            return PermissionSnapshot(
                permission: .camera,
                authorization: .unknown,
                availability: .available
            )
        }
    }
}

private actor CameraCoachUITestingPermissionClient: PermissionClient {
    private let cameraSnapshot: PermissionSnapshot
    private let cameraRecheckSnapshot: PermissionSnapshot
    private let cameraRequestResult: PermissionSnapshot
    private var cameraSnapshotCallCount = 0

    init(
        snapshot: PermissionSnapshot,
        recheckSnapshot: PermissionSnapshot,
        requestResult: PermissionSnapshot
    ) {
        self.cameraSnapshot = snapshot
        self.cameraRecheckSnapshot = recheckSnapshot
        self.cameraRequestResult = requestResult
    }

    func snapshot(for permission: AppPermission) async -> PermissionSnapshot {
        guard permission == .camera else {
            return PermissionSnapshot(
                permission: permission,
                authorization: .unknown,
                availability: .available
            )
        }

        defer { cameraSnapshotCallCount += 1 }
        return cameraSnapshotCallCount == 0
            ? cameraSnapshot
            : cameraRecheckSnapshot
    }

    func request(_ permission: AppPermission) async -> PermissionSnapshot {
        permission == .camera
            ? cameraRequestResult
            : PermissionSnapshot(
                permission: permission,
                authorization: .unknown,
                availability: .available
            )
    }
}

private final class CameraCoachUITestingSessionRunner: CameraSessionRunner {
    private(set) var isRunning = false

    func startRunning() {
        isRunning = true
    }

    func stopRunning() {
        isRunning = false
    }
}

private final class CameraCoachUITestingIntroStore: CameraCoachIntroStore {
    private var seen: Bool

    init(initiallySeen: Bool) {
        self.seen = initiallySeen
    }

    func hasSeenCameraCoachIntro() -> Bool {
        seen
    }

    func markCameraCoachIntroSeen() {
        seen = true
    }
}
#endif

//
//  ContentView.swift
//  multitool2
//
//  Created by Рустем on 27.10.2025.
//

import SwiftUI

@MainActor
struct ContentView: View {
    @MainActor
    struct CameraCoachDependencies {
        let cameraManager: CameraManager
        let viewModel: CameraViewModel
        let entryFlowModel: CameraCoachEntryFlowModel

        init(
            cameraManager: CameraManager,
            viewModel: CameraViewModel,
            permissionClient: any PermissionClient = PermissionCoordinator(client: SystemPermissionClient()),
            introStore: any CameraCoachIntroStore = UserDefaultsCameraCoachIntroStore()
        ) {
            self.cameraManager = cameraManager
            self.viewModel = viewModel
            self.entryFlowModel = CameraCoachEntryFlowModel(
                permissionClient: permissionClient,
                introStore: introStore
            )
        }

        init(
            cameraManager: CameraManager,
            viewModel: CameraViewModel,
            entryFlowModel: CameraCoachEntryFlowModel
        ) {
            self.cameraManager = cameraManager
            self.viewModel = viewModel
            self.entryFlowModel = entryFlowModel
        }
    }

    @StateObject private var viewModel: CameraViewModel
    @StateObject private var entryFlowModel: CameraCoachEntryFlowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let cameraManager: CameraManager

    init() {
        self.init(dependencies: Self.makeCameraCoachDependencies())
    }

    init(dependencies: CameraCoachDependencies) {
        _viewModel = StateObject(wrappedValue: dependencies.viewModel)
        _entryFlowModel = StateObject(
            wrappedValue: dependencies.entryFlowModel
        )
        self.cameraManager = dependencies.cameraManager
    }

    static func makeCameraCoachDependencies() -> CameraCoachDependencies {
        let scheduler = RealtimeScheduler()
        let thermal = ThermalGovernor()
        let motionGate = MotionGate()
        let cameraManager = CameraManager(scheduler: scheduler,
                                          thermalGovernor: thermal,
                                          motionGate: motionGate)
        let pipeline = AnalysisPipeline(
            thermalGovernor: thermal,
            neuralHeavyModelsEnabledProvider: {
                thermal.nextBudget().heavyModelsEnabled
            }
        )
        let permissions = PermissionCoordinator(client: SystemPermissionClient())
        return CameraCoachDependencies(
            cameraManager: cameraManager,
            viewModel: CameraViewModel(cameraManager: cameraManager,
                                       analysisPipeline: pipeline,
                                       recordingCoordinatorFactory: makeRecordingCoordinatorFactory(
                                           cameraManager: cameraManager, permissions: permissions
                                       )),
            permissionClient: permissions,
            introStore: UserDefaultsCameraCoachIntroStore()
        )
    }

    /// Production and injected capture routes use the same recording owner.
    /// Available device formats decide whether the capture can start a take.
    static func makeRecordingCoordinatorFactory(
        cameraManager: CameraManager, permissions: any PermissionClient
    ) -> @MainActor () throws -> CameraCoachRecordingCoordinator {
        {
            let artifactStore = try RecordingArtifactStore()
            return CameraCoachRecordingCoordinator(
                capture: cameraManager, artifactStore: artifactStore,
                persistence: CameraRecordingDBAdapter(artifactStore: artifactStore),
                permissions: permissions,
                projectName: {
                    SETCopyKey.cameraRecordingProjectName.localizedString(locale: .current)
                        + " " + Date().formatted(date: .abbreviated, time: .standard)
                        + " " + String(UUID().uuidString.prefix(4))
                }
            )
        }
    }

    var body: some View {
        Group {
            if entryFlowModel.phase == .ready {
                ZStack {
                    OverlayView(viewModel: viewModel, cameraManager: cameraManager)

                    if let leaderPhase = entryFlowModel.leaderPhase {
                        CameraCoachEntryLeaderOverlay(phase: leaderPhase)
                    }
                }
                .onAppear {
                    entryFlowModel.acceptCameraEntry(reduceMotion: reduceMotion)
                }
            } else {
                CameraCoachEntryView(
                    phase: entryFlowModel.phase,
                    onOpenCamera: {
                        Task { @MainActor in
                            await entryFlowModel.openCameraTapped()
                        }
                    },
                    onContinuePermissionRequest: {
                        Task { @MainActor in
                            await entryFlowModel.continuePermissionRequest()
                        }
                    },
                    onRecheckCameraAccess: {
                        Task { @MainActor in
                            await entryFlowModel.recheckCameraAccess()
                        }
                    },
                    markerEventID: entryFlowModel.markerEventID,
                    markerDrawProgress: entryFlowModel.markerDrawProgress
                )
            }
        }
        .preferredColorScheme(.dark)
        .task { @MainActor in
            entryFlowModel.updateAccessibilityPreferences(reduceMotion: reduceMotion)
            await entryFlowModel.resolveInitialState()
        }
        // M1-004: no SwiftUI scenePhase foreground recheck here. Foreground
        // recovery is owned by the shell adapter (SceneDelegate →
        // CommercialShellViewController.handleAppDidBecomeActive → route),
        // which is a superset of the removed blocked-only recheck.
        .onChange(of: reduceMotion) { _, newValue in
            entryFlowModel.updateAccessibilityPreferences(reduceMotion: newValue)
        }
    }
}

#Preview {
    ContentView()
}

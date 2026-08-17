//
//  ContentView.swift
//  multitool2
//
//  Created by Рустем on 27.10.2025.
//

import SwiftUI

@MainActor
struct ContentView: View {
    struct CameraCoachDependencies {
        let cameraManager: CameraManager
        let viewModel: CameraViewModel
        let permissionClient: any PermissionClient
        let introStore: any CameraCoachIntroStore

        init(
            cameraManager: CameraManager,
            viewModel: CameraViewModel,
            permissionClient: any PermissionClient = SystemPermissionClient(),
            introStore: any CameraCoachIntroStore = UserDefaultsCameraCoachIntroStore()
        ) {
            self.cameraManager = cameraManager
            self.viewModel = viewModel
            self.permissionClient = permissionClient
            self.introStore = introStore
        }
    }

    @StateObject private var viewModel: CameraViewModel
    @StateObject private var entryFlowModel: CameraCoachEntryFlowModel
    private let cameraManager: CameraManager

    init() {
        self.init(dependencies: Self.makeCameraCoachDependencies())
    }

    init(dependencies: CameraCoachDependencies) {
        _viewModel = StateObject(wrappedValue: dependencies.viewModel)
        _entryFlowModel = StateObject(
            wrappedValue: CameraCoachEntryFlowModel(
                permissionClient: dependencies.permissionClient,
                introStore: dependencies.introStore
            )
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
        return CameraCoachDependencies(
            cameraManager: cameraManager,
            viewModel: CameraViewModel(cameraManager: cameraManager,
                                       analysisPipeline: pipeline),
            permissionClient: SystemPermissionClient(),
            introStore: UserDefaultsCameraCoachIntroStore()
        )
    }

    var body: some View {
        Group {
            if entryFlowModel.phase == .ready {
                OverlayView(viewModel: viewModel, cameraManager: cameraManager)
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
                    }
                )
            }
        }
        .preferredColorScheme(.dark)
        .task { @MainActor in
            await entryFlowModel.resolveInitialState()
        }
    }
}

#Preview {
    ContentView()
}

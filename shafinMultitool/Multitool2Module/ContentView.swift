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
    }

    @StateObject private var viewModel: CameraViewModel
    private let cameraManager: CameraManager

    init() {
        self.init(dependencies: Self.makeCameraCoachDependencies())
    }

    init(dependencies: CameraCoachDependencies) {
        _viewModel = StateObject(wrappedValue: dependencies.viewModel)
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
                                       analysisPipeline: pipeline)
        )
    }

    var body: some View {
        OverlayView(viewModel: viewModel, cameraManager: cameraManager)
            .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}

//
//  ContentView.swift
//  multitool2
//
//  Created by Рустем on 27.10.2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: CameraViewModel
    private let cameraManager: CameraManager

    init() {
        let scheduler = RealtimeScheduler()
        let thermal = ThermalGovernor()
        let motionGate = MotionGate()
        let cameraManager = CameraManager(scheduler: scheduler,
                                          thermalGovernor: thermal,
                                          motionGate: motionGate)
        let pipeline = AnalysisPipeline()
        _viewModel = StateObject(wrappedValue: CameraViewModel(cameraManager: cameraManager,
                                                               analysisPipeline: pipeline))
        self.cameraManager = cameraManager
    }

    var body: some View {
        OverlayView(viewModel: viewModel, cameraManager: cameraManager)
            .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}

//
//  MockNeuralEvidenceProvider.swift
//  multitool2
//
//  Created by Codex on 22.04.2026.
//

import Foundation

final class MockNeuralEvidenceProvider: NeuralEvidenceProvider {
    typealias PrepareHandler = () async throws -> Void
    typealias InferHandler = (NeuralEvidenceProviderRequest) async throws -> NeuralEvidenceProviderOutput

    let descriptor: NeuralEvidenceProviderDescriptor

    private let prepareHandler: PrepareHandler
    private let inferHandler: InferHandler
    private let stateQueue = DispatchQueue(label: "MockNeuralEvidenceProvider.state")
    private var _prepareCallCount = 0
    private var _inferCallCount = 0

    var prepareCallCount: Int {
        stateQueue.sync { _prepareCallCount }
    }

    var inferCallCount: Int {
        stateQueue.sync { _inferCallCount }
    }

    init(descriptor: NeuralEvidenceProviderDescriptor = NeuralEvidenceProviderDescriptor(
        providerKind: .mock,
        inferenceTarget: .onDevice,
        modelFamily: "mock_neural_evidence",
        modelVersion: "test.v1",
        preprocessingVersion: "prep.test",
        thresholdProfileLive: "default_live_v1",
        thresholdProfilePause: "default_pause_v1",
        bundleVersion: "mock.bundle.v1"
    ),
         prepare: @escaping PrepareHandler = {},
         infer: @escaping InferHandler) {
        self.descriptor = descriptor
        self.prepareHandler = prepare
        self.inferHandler = infer
    }

    func prepareIfNeeded() async throws {
        stateQueue.sync {
            _prepareCallCount += 1
        }
        try await prepareHandler()
    }

    func infer(request: NeuralEvidenceProviderRequest) async throws -> NeuralEvidenceProviderOutput {
        stateQueue.sync {
            _inferCallCount += 1
        }
        return try await inferHandler(request)
    }
}

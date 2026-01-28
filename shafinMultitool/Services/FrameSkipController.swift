//
//  FrameSkipController.swift
//  shafinMultitool
//
//  Created as part of Stage 2 optimizations.
//

import Foundation

/// Lightweight helper that decides whether the current frame should run heavy auxiliary work (Vision, overlays, etc.)
final class FrameSkipController {

    private var frameCounter: Int = 0
    private var skipModulo: Int
    private let queue = DispatchQueue(label: "frameSkip.controller", qos: .utility)

    init(sourceFPS: Int = 60, targetFPS: Int = 12) {
        self.skipModulo = FrameSkipController.computeModulo(sourceFPS: sourceFPS, targetFPS: targetFPS)
    }

    func updateTarget(sourceFPS: Int = 60, targetFPS: Int) {
        queue.async {
            self.skipModulo = FrameSkipController.computeModulo(sourceFPS: sourceFPS, targetFPS: targetFPS)
            self.frameCounter = 0
        }
    }

    func shouldProcessFrame() -> Bool {
        return queue.sync {
            frameCounter = (frameCounter + 1) % skipModulo
            return frameCounter == 0
        }
    }

    private static func computeModulo(sourceFPS: Int, targetFPS: Int) -> Int {
        guard sourceFPS > 0 else { return 1 }
        let modulo = max(1, sourceFPS / max(1, targetFPS))
        return modulo
    }
}


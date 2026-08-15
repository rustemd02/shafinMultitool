struct CameraInputReplacementTransaction<Input> {
    enum Outcome: Equatable {
        case replaced
        case restored
        case rollbackFailed
    }

    private let oldInput: Input
    private let newInput: Input
    private let removeInput: (Input) -> Void
    private let canAddInput: (Input) -> Bool
    private let addInput: (Input) -> Void

    init(oldInput: Input,
         newInput: Input,
         removeInput: @escaping (Input) -> Void,
         canAddInput: @escaping (Input) -> Bool,
         addInput: @escaping (Input) -> Void) {
        self.oldInput = oldInput
        self.newInput = newInput
        self.removeInput = removeInput
        self.canAddInput = canAddInput
        self.addInput = addInput
    }

    func perform() -> Outcome {
        removeInput(oldInput)

        guard canAddInput(newInput) else {
            guard canAddInput(oldInput) else {
                return .rollbackFailed
            }

            addInput(oldInput)
            return .restored
        }

        addInput(newInput)
        return .replaced
    }
}

import XCTest
@testable import shafinMultitool

final class CameraLensSwitchTransactionTests: XCTestCase {
    func testSuccessfulReplacementRemovesOldChecksNewAndAddsNew() {
        var operations: [Operation] = []
        let transaction = CameraInputReplacementTransaction(
            oldInput: InputToken.old,
            newInput: InputToken.new,
            removeInput: { input in operations.append(.remove(input)) },
            canAddInput: { input in
                operations.append(.canAdd(input))
                return input == .new
            },
            addInput: { input in operations.append(.add(input)) }
        )

        XCTAssertEqual(transaction.perform(), .replaced)
        XCTAssertEqual(operations, [
            .remove(.old),
            .canAdd(.new),
            .add(.new)
        ])
    }

    func testRejectedReplacementRestoresOldInput() {
        var operations: [Operation] = []
        let transaction = CameraInputReplacementTransaction(
            oldInput: InputToken.old,
            newInput: InputToken.new,
            removeInput: { input in operations.append(.remove(input)) },
            canAddInput: { input in
                operations.append(.canAdd(input))
                return input == .old
            },
            addInput: { input in operations.append(.add(input)) }
        )

        XCTAssertEqual(transaction.perform(), .restored)
        XCTAssertEqual(operations, [
            .remove(.old),
            .canAdd(.new),
            .canAdd(.old),
            .add(.old)
        ])
    }

    func testRejectedReplacementAndRejectedRestoreReportRollbackFailureWithoutAdding() {
        var operations: [Operation] = []
        let transaction = CameraInputReplacementTransaction(
            oldInput: InputToken.old,
            newInput: InputToken.new,
            removeInput: { input in operations.append(.remove(input)) },
            canAddInput: { input in
                operations.append(.canAdd(input))
                return false
            },
            addInput: { input in operations.append(.add(input)) }
        )

        XCTAssertEqual(transaction.perform(), .rollbackFailed)
        XCTAssertEqual(operations, [
            .remove(.old),
            .canAdd(.new),
            .canAdd(.old)
        ])
    }

    func testOldInputIsRemovedOnceAndEveryAddHasAPrecedingApproval() {
        var operations: [Operation] = []
        var approvedInputs: Set<InputToken> = []
        var invalidAddCount = 0
        let transaction = CameraInputReplacementTransaction(
            oldInput: InputToken.old,
            newInput: InputToken.new,
            removeInput: { input in operations.append(.remove(input)) },
            canAddInput: { input in
                operations.append(.canAdd(input))
                let approved = input == .new
                if approved {
                    approvedInputs.insert(input)
                }
                return approved
            },
            addInput: { input in
                guard approvedInputs.remove(input) != nil else {
                    invalidAddCount += 1
                    return
                }
                operations.append(.add(input))
            }
        )

        XCTAssertEqual(transaction.perform(), .replaced)
        XCTAssertEqual(invalidAddCount, 0)
        XCTAssertEqual(operations.filter { $0 == .remove(.old) }.count, 1)
        XCTAssertEqual(operations.filter { $0 == .add(.new) }.count, 1)

        guard let canAddIndex = operations.firstIndex(of: .canAdd(.new)),
              let addIndex = operations.firstIndex(of: .add(.new)) else {
            return XCTFail("Expected canAdd and add operations for the new input")
        }
        XCTAssertLessThan(canAddIndex, addIndex)
    }
}

private enum InputToken: Hashable {
    case old
    case new
}

private enum Operation: Equatable {
    case remove(InputToken)
    case canAdd(InputToken)
    case add(InputToken)
}

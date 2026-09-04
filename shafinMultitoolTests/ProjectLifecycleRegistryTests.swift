//
//  ProjectLifecycleRegistryTests.swift
//  shafinMultitoolTests
//
//  M1-016 ProjectLifecycleOwner: deletion of an open project is rejected while
//  the workspace lease is active, and succeeds only after the owner releases.
//

import XCTest
@testable import shafinMultitool

final class ProjectLifecycleRegistryTests: XCTestCase {

    func testAcquireIsExclusiveAndReleaseIsTokenFenced() {
        let registry = ProjectLifecycleRegistry()
        let projectID = UUID()

        let firstToken = registry.acquire(projectID: projectID)
        XCTAssertNotNil(firstToken)
        XCTAssertTrue(registry.isLeased(projectID: projectID))

        XCTAssertNil(registry.acquire(projectID: projectID), "second owner must not share the lease")

        // A stale token cannot drop a newer lease.
        registry.release(projectID: projectID, token: UUID())
        XCTAssertTrue(registry.isLeased(projectID: projectID))

        registry.release(projectID: projectID, token: firstToken!)
        XCTAssertFalse(registry.isLeased(projectID: projectID))

        // After release the project can be leased again.
        XCTAssertNotNil(registry.acquire(projectID: projectID))
    }

    func testConcurrentAcquireYieldsExactlyOneWinner() {
        let registry = ProjectLifecycleRegistry()
        let projectID = UUID()
        let lock = NSLock()
        var winners = 0

        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            if registry.acquire(projectID: projectID) != nil {
                lock.lock()
                winners += 1
                lock.unlock()
            }
        }

        XCTAssertEqual(winners, 1)
        XCTAssertTrue(registry.isLeased(projectID: projectID))
    }

    func testDeletionIsRejectedWhileWorkspaceLeaseIsActiveAndSucceedsAfterRelease() throws {
        let leases = ProjectLifecycleRegistry()
        let dbService = DBService(projectLeases: leases)
        let projectName = "leased-project-\(UUID().uuidString)"

        let project = try dbService.createUnifiedSceneProject(named: projectName)

        let token = try XCTUnwrap(leases.acquire(projectID: project.id), "test must own the lease")

        var deleteResult: Bool?
        let deletionRejected = expectation(description: "deletion rejected")
        dbService.deleteUnifiedSceneProject(named: projectName) { deleted in
            deleteResult = deleted
            deletionRejected.fulfill()
        }
        wait(for: [deletionRejected], timeout: 5)
        XCTAssertEqual(deleteResult, false, "deletion must be rejected while the workspace owns the project")

        let stillStored = try XCTUnwrap(
            dbService.loadUnifiedSceneProject(named: projectName),
            "the leased project must remain intact"
        )
        XCTAssertEqual(stillStored.0.id, project.id)

        leases.release(projectID: project.id, token: token)

        var secondResult: Bool?
        let deletionSucceeded = expectation(description: "deletion succeeds")
        dbService.deleteUnifiedSceneProject(named: projectName) { deleted in
            secondResult = deleted
            deletionSucceeded.fulfill()
        }
        wait(for: [deletionSucceeded], timeout: 5)
        XCTAssertEqual(secondResult, true)
        XCTAssertNil(dbService.loadUnifiedSceneProject(named: projectName))
    }
}

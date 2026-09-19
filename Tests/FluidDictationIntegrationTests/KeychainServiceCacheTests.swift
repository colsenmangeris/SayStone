@testable import FluidVoice_Debug
import XCTest

private final class KeychainServiceBox: @unchecked Sendable {
    let service: KeychainService

    init(_ service: KeychainService) {
        self.service = service
    }
}

final class KeychainServiceCacheTests: XCTestCase {
    func testOneTimeImportStoresCredentialAndDeletesPrivateFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let importURL = directory.appendingPathComponent("credential.import")
        try Data("  speech-token\n".utf8).write(to: importURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: importURL.path)

        var stored: [String: String] = [:]
        let service = KeychainService(
            testingLoad: { stored },
            testingSave: { stored = $0 }
        )

        XCTAssertTrue(try service.importKeyIfPresent(from: importURL, for: "saystone-profile-sync"))
        XCTAssertEqual(stored["saystone-profile-sync"], "speech-token")
        XCTAssertFalse(FileManager.default.fileExists(atPath: importURL.path))
        XCTAssertFalse(try service.importKeyIfPresent(from: importURL, for: "saystone-profile-sync"))
    }

    func testOneTimeImportRejectsBroadFilePermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let importURL = directory.appendingPathComponent("credential.import")
        try Data("speech-token".utf8).write(to: importURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: importURL.path)

        let service = KeychainService(testingLoad: { [:] }, testingSave: { _ in })
        XCTAssertThrowsError(
            try service.importKeyIfPresent(from: importURL, for: "saystone-profile-sync")
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: importURL.path))
    }

    func testConcurrentStoresDoNotLoseUpdates() throws {
        let storageLock = NSLock()
        var storage: [String: String] = [:]
        let service = KeychainService(
            testingLoad: { storageLock.withLock { storage } },
            testingSave: { values in storageLock.withLock { storage = values } }
        )
        let box = KeychainServiceBox(service)
        let count = 200

        DispatchQueue.concurrentPerform(iterations: count) { index in
            try? box.service.storeKey("value-\(index)", for: "provider-\(index)")
        }

        XCTAssertEqual(try service.fetchAllKeys().count, count)
    }

    func testFailedLoadIsRetriedInsteadOfCached() throws {
        struct ExpectedFailure: Error {}

        var loadCount = 0
        let service = KeychainService(
            testingLoad: {
                loadCount += 1
                if loadCount == 1 { throw ExpectedFailure() }
                return ["openai": "secret"]
            },
            testingSave: { _ in }
        )

        XCTAssertThrowsError(try service.fetchAllKeys())
        XCTAssertEqual(try service.fetchAllKeys(), ["openai": "secret"])
        XCTAssertEqual(loadCount, 2)
    }

    func testFetchAllKeysLoadsOncePerProcess() throws {
        var loadCount = 0
        let service = KeychainService(
            testingLoad: {
                loadCount += 1
                return ["openai": "secret"]
            },
            testingSave: { _ in }
        )

        XCTAssertEqual(try service.fetchAllKeys(), ["openai": "secret"])
        XCTAssertEqual(try service.fetchAllKeys(), ["openai": "secret"])
        XCTAssertEqual(loadCount, 1)
    }

    func testSuccessfulStoreUpdatesCacheWithoutReloadingKeychain() throws {
        var loadCount = 0
        var stored: [String: String] = [:]
        let service = KeychainService(
            testingLoad: {
                loadCount += 1
                return ["openai": "old"]
            },
            testingSave: { stored = $0 }
        )

        try service.storeKey(" new ", for: "groq")

        XCTAssertEqual(stored, ["openai": "old", "groq": "new"])
        XCTAssertEqual(try service.fetchAllKeys(), stored)
        XCTAssertEqual(loadCount, 1)
    }

    func testFailedStoreKeepsPreviouslyLoadedCache() throws {
        struct ExpectedFailure: Error {}

        var loadCount = 0
        let service = KeychainService(
            testingLoad: {
                loadCount += 1
                return ["openai": "old"]
            },
            testingSave: { _ in throw ExpectedFailure() }
        )

        XCTAssertThrowsError(try service.storeKey("new", for: "groq"))
        XCTAssertEqual(try service.fetchAllKeys(), ["openai": "old"])
        XCTAssertEqual(loadCount, 1)
    }

    func testDeleteUpdatesCacheWithoutReloadingKeychain() throws {
        var loadCount = 0
        var stored: [String: String] = [:]
        let service = KeychainService(
            testingLoad: {
                loadCount += 1
                return ["openai": "secret", "groq": "secret"]
            },
            testingSave: { stored = $0 }
        )

        try service.deleteKey(for: "openai")

        XCTAssertEqual(stored, ["groq": "secret"])
        XCTAssertEqual(try service.fetchAllKeys(), stored)
        XCTAssertEqual(loadCount, 1)
    }

    func testStoreRefreshesBeforeMergingExternalChanges() throws {
        var storage = ["openai": "old"]
        let service = KeychainService(
            testingLoad: { storage },
            testingSave: { storage = $0 }
        )

        XCTAssertEqual(try service.fetchAllKeys(), storage)
        storage["anthropic"] = "external"

        try service.storeKey("new", for: "groq")

        XCTAssertEqual(
            storage,
            ["openai": "old", "anthropic": "external", "groq": "new"]
        )
        XCTAssertEqual(try service.fetchAllKeys(), storage)
    }

    func testExplicitRefreshObservesExternalChanges() throws {
        var loadCount = 0
        var storage = ["openai": "old"]
        let service = KeychainService(
            testingLoad: {
                loadCount += 1
                return storage
            },
            testingSave: { storage = $0 }
        )

        XCTAssertEqual(try service.fetchAllKeys(), ["openai": "old"])
        storage["openai"] = "external"

        try service.refreshCachedKeys()

        XCTAssertEqual(try service.fetchAllKeys(), ["openai": "external"])
        XCTAssertEqual(loadCount, 2)
    }

    func testCachedReadDoesNotWaitForBlockedRefresh() throws {
        let stateLock = NSLock()
        var loadCount = 0
        let refreshStarted = DispatchSemaphore(value: 0)
        let releaseRefresh = DispatchSemaphore(value: 0)
        let refreshFinished = self.expectation(description: "refresh finished")
        let service = KeychainService(
            testingLoad: {
                let currentLoad = stateLock.withLock {
                    loadCount += 1
                    return loadCount
                }
                if currentLoad > 1 {
                    refreshStarted.signal()
                    releaseRefresh.wait()
                }
                return ["openai": currentLoad == 1 ? "cached" : "refreshed"]
            },
            testingSave: { _ in }
        )
        let box = KeychainServiceBox(service)

        XCTAssertEqual(try service.fetchAllKeys(), ["openai": "cached"])
        DispatchQueue.global(qos: .utility).async {
            try? box.service.refreshCachedKeys()
            refreshFinished.fulfill()
        }
        XCTAssertEqual(refreshStarted.wait(timeout: .now() + 1), .success)

        XCTAssertEqual(try service.fetchAllKeys(), ["openai": "cached"])

        releaseRefresh.signal()
        self.wait(for: [refreshFinished], timeout: 1)
        XCTAssertEqual(try service.fetchAllKeys(), ["openai": "refreshed"])
    }
}

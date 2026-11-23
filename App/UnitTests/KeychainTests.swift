import Foundation
import Testing

@testable import PlateTally

/// These run against the real keychain of the simulator, under a service name of their own.
@Suite struct KeychainTests {
    private func store() -> KeychainKeyStore {
        KeychainKeyStore(service: "plate-tally-tests-\(UUID().uuidString)")
    }

    @Test func nothingIsStoredAtFirst() throws {
        #expect(try store().read() == nil)
    }

    @Test func aSavedKeyComesBackIsReplacedAndRemoved() throws {
        let store = store()
        try store.save("first-test-key")
        #expect(try store.read() == "first-test-key")
        try store.save("second-test-key")
        #expect(try store.read() == "second-test-key")
        try store.remove()
        #expect(try store.read() == nil)
    }

    @Test func removingWhatIsNotThereIsNotAnError() throws {
        try store().remove()
    }
}

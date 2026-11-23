import SwiftUI

extension Binding where Value: Sendable {
    /// A binding whose closures use main-actor state. SwiftUI calls them on the main thread, and this says
    /// so to the compiler whatever isolation the SDK declares for the closures of `Binding(get:set:)`.
    init(main get: @escaping @MainActor () -> Value, set: @escaping @MainActor (Value) -> Void) {
        self.init(
            get: { MainActor.assumeIsolated { get() } },
            set: { newValue in MainActor.assumeIsolated { set(newValue) } })
    }
}

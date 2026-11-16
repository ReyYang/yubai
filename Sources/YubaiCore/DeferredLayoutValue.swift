import Foundation

/// Main-thread geometry observations are delivered after the current update,
/// coalescing repeated values without publishing into an active layout pass.
public final class DeferredLayoutValue<Value: Equatable> {
    private let schedule: (@escaping () -> Void) -> Void
    private var pending: (value: Value, apply: (Value) -> Void)?
    private var delivered: Value?
    private var scheduled = false
    private var revision = 0

    public init(schedule: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) {
        self.schedule = schedule
    }

    public func submit(_ value: Value, apply: @escaping (Value) -> Void) {
        guard delivered != value else { pending = nil; return }
        pending = (value, apply)
        guard !scheduled else { return }
        scheduled = true
        let expected = revision
        schedule { [weak self] in
            guard let self, revision == expected else { return }
            scheduled = false
            guard let next = pending else { return }
            pending = nil
            delivered = next.value
            next.apply(next.value)
        }
    }

    public func cancel() {
        revision &+= 1
        pending = nil
        scheduled = false
    }
}

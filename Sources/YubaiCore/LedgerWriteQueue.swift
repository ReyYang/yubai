import Foundation

/// FIFO disk executor. Submission is synchronous so task scheduling cannot reorder
/// a manual save and an organization checkpoint. A failed manual save rejects all
/// dependent snapshots until the caller reloads the durable ledger with reset().
public final class LedgerWriteQueue: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.yubai.ledger-writes", qos: .userInitiated)
    private var failure: Error?
    public init() {}

    public func submit<Value: Sendable>(invalidatingOnFailure: Bool = true,
                                       _ operation: @escaping @Sendable () throws -> Value) -> LedgerWriteReceipt<Value> {
        let receipt = LedgerWriteReceipt<Value>()
        queue.async {
            if let failure = self.failure { receipt.finish(.failure(failure)); return }
            let result = Result { try operation() }
            if invalidatingOnFailure, case .failure(let error) = result { self.failure = error }
            receipt.finish(result)
        }
        return receipt
    }
    /// Recovery runs after all rejected dependent writes and reopens the queue
    /// only once a consistent disk snapshot has been read successfully.
    public func reset<Value: Sendable>(_ reload: @escaping @Sendable () throws -> Value) -> LedgerWriteReceipt<Value> {
        let receipt = LedgerWriteReceipt<Value>()
        queue.async {
            let result = Result { try reload() }
            if case .success = result { self.failure = nil }
            receipt.finish(result)
        }
        return receipt
    }
    public func flush() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }
    /// For synchronous destructive storage actions and OS suspension/termination.
    /// Ordinary edits always submit asynchronously.
    public func flushBlocking() { queue.sync {} }
}

public final class LedgerWriteReceipt<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var waiters: [CheckedContinuation<Value, Error>] = []
    fileprivate init() {}
    fileprivate func finish(_ result: Result<Value, Error>) {
        lock.lock(); self.result = result; let waiters = self.waiters; self.waiters = []; lock.unlock()
        for waiter in waiters { waiter.resume(with: result) }
    }
    public var value: Value {
        get async throws {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let result { lock.unlock(); continuation.resume(with: result) }
                else { waiters.append(continuation); lock.unlock() }
            }
        }
    }
}

import Foundation
import YubaiCore
#if canImport(BackgroundTasks) && os(iOS)
import BackgroundTasks
#endif

/// Spec-Currency 什么时候同步: when the app comes back (after iCloud has settled) and a daily background
/// refresh, fetch the ECB daily reference rates — only when 12 hours have passed since the last success,
/// with backoff after failures. Recording never waits for it. The rates live on this device only.
extension AppStore {
    /// Fixtures and UI tests never reach the network.
    private var mayFetchRates: Bool {
        guard !isDesignFixture else { return false }
        if ProcessInfo.processInfo.arguments.contains("--test-ledger") { return false }
        #if DEBUG && targetEnvironment(simulator)
        if UITestSupport.script != nil { return false }
        #endif
        return true
    }

    /// Rates are this device's own and touch no ledger file, so the lock and storage work never hold them
    /// up; only an automatic check waits for iCloud to settle, so it does not compete with a sync.
    private var mayCheckRates: Bool { loadFailure == nil && !loadingLedger && !syncBusy && !switchingLedgerLocation }

    /// 去更新 / 重试 and the background refresh: true when the rates are fresh afterwards.
    @discardableResult func syncExchangeRatesIfNeeded(force: Bool = false) async -> Bool {
        guard mayFetchRates, !rateSyncRunning, force || mayCheckRates, !loadingLedger else { return false }
        let auto = current.preferences.autoRateSync != false
        guard force || ExchangeRates.needsSync(autoSync: auto, state: rateSync, now: Date()) else { return false }
        rateSyncRunning = true
        defer { rateSyncRunning = false }
        var state = rateSync
        do {
            var request = URLRequest(url: ExchangeRates.sourceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("Yubai", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            try state.succeeded(ExchangeRates.parseECB(data, fetchedAt: Date()), at: Date())
        } catch is CancellationError {
            return false   // The system took the background time back: not a failure, no backoff.
        } catch let error as URLError where error.code == .cancelled {
            return false
        } catch let error as URLError {
            state.failed(error.code == .notConnectedToInternet || error.code == .networkConnectionLost ? "网络连不上" : "汇率服务没有回应", at: Date())
        } catch {
            state.failed("汇率数据读不懂", at: Date())
        }
        rateSync = state
        return state.failures == 0
    }

    /// The device-local rates changed: save them and redraw amounts in the main currency.
    func rateSyncChanged() {
        RateSyncStore.save(rateSync)
        // A new rate redraws every amount (and republishes the widget); an unchanged one changes nothing.
        if DisplayCurrency.configure(current, synced: rateSync.rates, now: Dates.now) { displayCurrencyChanged() }
    }
}

/// This device's rate sync state, kept out of the ledger (and so out of iCloud).
enum RateSyncStore {
    private static let key = "yubai.rateSync"

    static func load() -> RateSyncState {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(RateSyncState.self, from: data) else { return RateSyncState() }
        return state
    }

    static func save(_ state: RateSyncState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

#if os(iOS)
/// Spec-Currency 兜底: a once-a-day background refresh, in case the app is not opened.
enum RateRefreshTask {
    static let identifier = "app.yubai.personal.rates"

    @MainActor static func register(store: AppStore) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            // The scheduler guarantees .main here; BGTask is not Sendable.
            nonisolated(unsafe) let delivered = task
            MainActor.assumeIsolated {
                schedule()
                let work = Task { @MainActor in
                    // A background launch is still reading the ledger (for 每天自动更新).
                    await store.waitForLedger()
                    let ok = await store.syncExchangeRatesIfNeeded()
                    delivered.setTaskCompleted(success: ok)
                }
                delivered.expirationHandler = { work.cancel() }
            }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(ExchangeRates.refreshInterval * 2)
        try? BGTaskScheduler.shared.submit(request)
    }
}
#endif

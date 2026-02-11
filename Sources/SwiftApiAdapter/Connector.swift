import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public let DEFAULT_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36"

// MARK: - Connector Manager

/// A lightweight registry for per-context connectors.
///
/// Swift 6 migration notes:
/// - This is now an `actor` to make access to the connector cache data-race safe.
/// - All public APIs remain similar, but calls must be awaited when invoked off the actor.
public actor ApiConnectorManager {
    public static let shared = ApiConnectorManager()
    private init() {}

    private var connectors: [String: ApiConnector] = [:]

    public func getConnector(for tag: String) -> ApiConnector {
        if let existing = connectors[tag] {
            return existing
        }
        let newConnector = ApiConnector()
        connectors[tag] = newConnector
        return newConnector
    }

    public func clearConnector(for tag: String) async {
        if let connector = connectors[tag] {
            await connector.executor.stop()
            connectors[tag] = nil
        }
    }

    public func clearAllConnectors() async {
        for (_, connector) in connectors {
            await connector.executor.stop()
        }
        connectors.removeAll()
    }

    public func getRequester(for tag: String) -> ApiRequester {
        getConnector(for: tag).requester
    }

    public func getExecutor(for tag: String) -> ApiSerialExecutor {
        getConnector(for: tag).executor
    }
}

// MARK: - Connector

public struct ApiConnector: Sendable, Equatable {
    public let executor: ApiSerialExecutor
    public let requester: ApiRequester

    public init() {
        let executor = ApiSerialExecutor()
        self.executor = executor
        self.requester = ApiRequester(executor: executor)
    }

    public func initTransaction() async {
        await executor.initTransaction()
    }

    public func stop() async {
        await executor.stop()
    }

    public static func == (lhs: ApiConnector, rhs: ApiConnector) -> Bool {
        ObjectIdentifier(lhs.executor) == ObjectIdentifier(rhs.executor)
    }
}

// MARK: - Response

public struct ApiResponse: Sendable, Equatable {
    public let responseString: String?
    public let finalUrl: String?
    public let statusCode: Int?
    public let headers: [String: String]
    public let errorDescription: String?

    /// Backward-compatible initializer.
    ///
    /// - Parameters:
    ///   - responseString: Raw response body as UTF-8 string (if decodable).
    ///   - finalUrl: Final URL after redirects (if available).
    ///   - statusCode: HTTP status code (if available).
    ///   - headers: HTTP response headers (if available).
    ///   - errorDescription: Any execution error (e.g. network failures).
    public init(
        responseString: String?,
        finalUrl: String?,
        statusCode: Int? = nil,
        headers: [String: String] = [:],
        errorDescription: String? = nil
    ) {
        self.responseString = responseString
        self.finalUrl = finalUrl
        self.statusCode = statusCode
        self.headers = headers
        self.errorDescription = errorDescription
    }
}


// MARK: - Serial Executor

/// A single-threaded (serial) request executor implemented with structured concurrency.
///
/// - Requests submitted through `requestJsonApi` are executed strictly one-at-a-time.
/// - `executeJsonApiImmediately` bypasses the queue.
/// - `stop()` cancels the worker task and resumes any queued requests with an empty response.
public actor ApiSerialExecutor {
    public struct Metrics: Sendable, Equatable {
        public let cumulativeRequested: Int
        public let cumulativeExecuted: Int
    }

    private struct Job {
        let requestData: Data
        let endpoint: URL
        let method: String
        let headers: [String: String]
        let continuation: CheckedContinuation<ApiResponse?, Never>
    }

    private var enabled: Bool = false
    private var queue: [Job] = []

    // A single worker that drains `queue`.
    private var workerTask: Task<Void, Never>?
    private var waitForWorkContinuation: CheckedContinuation<Void, Never>?

    private let session: URLSession
    private let delayBetweenRequests: Duration

    // Observability via AsyncStream, for SwiftUI or other consumers.
    private var metricsContinuations: [UUID: AsyncStream<Metrics>.Continuation] = [:]

    public private(set) var cumulativeRequested: Int = 0
    public private(set) var cumulativeExecuted: Int = 0

    public init(
        delayBetweenRequests: Duration = .milliseconds(500),
        timeoutIntervalForRequest: TimeInterval = 180
    ) {
        self.delayBetweenRequests = delayBetweenRequests

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutIntervalForRequest
        self.session = URLSession(configuration: config)
    }

    deinit {
        workerTask?.cancel()
    }

    // MARK: Observability

    public func metrics() -> Metrics {
        Metrics(cumulativeRequested: cumulativeRequested, cumulativeExecuted: cumulativeExecuted)
    }

    /// Subscribe to metrics updates.
    ///
    /// The returned stream yields the current metrics immediately and then yields on every update.
    public func metricsUpdates() -> AsyncStream<Metrics> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.yield(self.metrics())
            self.metricsContinuations[id] = continuation

            continuation.onTermination = { _ in
                Task { await self.removeMetricsContinuation(id) }
            }
        }
    }

    private func removeMetricsContinuation(_ id: UUID) {
        metricsContinuations[id] = nil
    }

    private func broadcastMetrics() {
        let current = metrics()
        for continuation in metricsContinuations.values {
            continuation.yield(current)
        }
    }

    // MARK: Counters

    public func initTransaction() {
        cumulativeRequested = 0
        cumulativeExecuted = 0
        broadcastMetrics()
    }

    public func markRequested() {
        cumulativeRequested += 1
        broadcastMetrics()
    }

    public func markExecuted() {
        cumulativeExecuted += 1
        broadcastMetrics()
    }

    // MARK: Lifecycle

    public func start() {
        enabled = true
        ensureWorker()
    }

    public func stop() {
        enabled = false

        // Cancel the worker (wakes up sleeps and cancels URLSession async calls).
        workerTask?.cancel()

        // Resume any queued callers so nobody deadlocks.
        let pending = queue
        queue.removeAll()
        if !pending.isEmpty {
            for job in pending {
                job.continuation.resume(returning: ApiResponse(responseString: nil, finalUrl: nil))
            }
            cumulativeExecuted += pending.count
            broadcastMetrics()
        }

        // Wake the worker if it's waiting for work.
        waitForWorkContinuation?.resume()
        waitForWorkContinuation = nil
    }

    // MARK: Public API

    public func requestJsonApi(
        _ requestData: Data,
        endpoint: URL,
        method: String,
        headers: [String: String]
    ) async -> ApiResponse? {
        markRequested()
        if !enabled {
            start()
        }

        return await withCheckedContinuation { continuation in
            let job = Job(
                requestData: requestData,
                endpoint: endpoint,
                method: method,
                headers: headers,
                continuation: continuation
            )
            queue.append(job)
            waitForWorkContinuation?.resume()
            waitForWorkContinuation = nil
            ensureWorker()
        }
    }

    public func executeJsonApiImmediately(
        _ requestData: Data,
        endpoint: URL,
        method: String,
        headers: [String: String]
    ) async -> ApiResponse? {
        markRequested()
        let response = await executeRequest(
            requestData: requestData,
            endpoint: endpoint,
            method: method,
            headers: headers
        )
        markExecuted()
        return response
    }

    // MARK: Worker

    private func ensureWorker() {
        guard workerTask == nil else { return }

        workerTask = Task { [weak self] in
            guard let self else { return }
            await self.workerLoop()
            await self.workerFinished()
        }
    }

    private func workerFinished() {
        workerTask = nil

        // If we were restarted while the old worker was shutting down,
        // spin up a new worker to drain any pending work.
        if enabled, !queue.isEmpty {
            ensureWorker()
            waitForWorkContinuation?.resume()
            waitForWorkContinuation = nil
        }
    }

    private func workerLoop() async {
        while enabled, !Task.isCancelled {
            guard let job = await nextJob() else {
                continue
            }

            do {
                try await Task.sleep(for: delayBetweenRequests)
            } catch {
                // Cancellation: ensure the waiting caller doesn't hang.
                job.continuation.resume(returning: ApiResponse(responseString: nil, finalUrl: nil))
                markExecuted()
                return
            }

            let response = await executeRequest(
                requestData: job.requestData,
                endpoint: job.endpoint,
                method: job.method,
                headers: job.headers
            )
            job.continuation.resume(returning: response)
            markExecuted()
        }
    }

    private func nextJob() async -> Job? {
        while queue.isEmpty {
            if Task.isCancelled || !enabled {
                return nil
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waitForWorkContinuation = continuation
            }
            // After resuming, loop to re-check state.
            waitForWorkContinuation = nil
        }
        return queue.removeFirst()
    }

    // MARK: HTTP

    private func executeRequest(
        requestData: Data,
        endpoint: URL,
        method: String,
        headers: [String: String]
    ) async -> ApiResponse? {
        var request = URLRequest(url: endpoint)
        let httpMethod = method.uppercased()
        request.httpMethod = httpMethod

        // RFC discourages GET bodies; ignore them for compatibility.
        if httpMethod != "GET", !requestData.isEmpty {
            request.httpBody = requestData
        }

        request.setValue(DEFAULT_USER_AGENT, forHTTPHeaderField: "User-Agent")

        for (key, value) in headers where !key.isEmpty && !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await session.data(for: request)

            let responseString = String(data: data, encoding: .utf8)

            if let httpResponse = response as? HTTPURLResponse {
                let finalUrl = httpResponse.url?.absoluteString
                let headers: [String: String] = httpResponse.allHeaderFields.reduce(into: [:]) { acc, pair in
                    let key = String(describing: pair.key)
                    let value = String(describing: pair.value)
                    acc[key] = value
                }

                return ApiResponse(
                    responseString: responseString,
                    finalUrl: finalUrl,
                    statusCode: httpResponse.statusCode,
                    headers: headers,
                    errorDescription: nil
                )
            } else {
                return ApiResponse(
                    responseString: responseString,
                    finalUrl: nil,
                    statusCode: nil,
                    headers: [:],
                    errorDescription: nil
                )
            }
        } catch {
            #if DEBUG
            print("[ApiSerialExecutor] Request failed: \(error)")
            #endif
            return ApiResponse(
                responseString: nil,
                finalUrl: nil,
                statusCode: nil,
                headers: [:],
                errorDescription: error.localizedDescription
            )
        }
    }
}

// MARK: - Requester

public struct ApiRequester: Sendable {
    let executor: ApiSerialExecutor

    public init(executor: ApiSerialExecutor) {
        self.executor = executor
    }

    public func initTransaction() async {
        await executor.initTransaction()
    }

    public func processJsonApi(
        endpoint: URL,
        method: String,
        headers: [String: String],
        body: String,
        immediate: Bool = false
    ) async -> ApiResponse? {
        let requestData = Data(body.utf8)
        if immediate {
            #if DEBUG
            print("[ApiRequester] JSON API request will be immediately processed")
            #endif
            return await executor.executeJsonApiImmediately(
                requestData,
                endpoint: endpoint,
                method: method,
                headers: headers
            )
        } else {
            #if DEBUG
            print("[ApiRequester] JSON API request will be executed in serialized queue")
            #endif
            return await executor.requestJsonApi(
                requestData,
                endpoint: endpoint,
                method: method,
                headers: headers
            )
        }
    }
}

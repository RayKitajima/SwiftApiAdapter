import Foundation
import Combine
import SwiftSoup
import SwiftyJSON

let DEFAULT_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36"

public class ApiConnectorManager: ObservableObject {
    public static let shared = ApiConnectorManager()
    private init(){}

    private var connector: [String: ApiConnector] = [:]

    public func getConnector(for tag: String) -> ApiConnector {
        if let connector = connector[tag] {
            return connector
        }
        let connector = ApiConnector()
        self.connector[tag] = connector
        return connector
    }

    public func clearConnector(for tag: String) {
        connector[tag]?.executor.stop()
        connector[tag] = nil
    }

    public func clearAllConnectors() {
        connector = [:]
    }

    public func getRequester(for tag: String) -> ApiRequester {
        return getConnector(for: tag).requester
    }

    public func getExecutor(for tag: String) -> ApiSerialExecutor {
        return getConnector(for: tag).executor
    }
}

public class ApiConnector: Equatable {
    public let executor: ApiSerialExecutor
    public let requester: ApiRequester

    init() {
        executor = ApiSerialExecutor()
        requester = ApiRequester(executor: executor)
    }

    func initTransaction() {
        DispatchQueue.main.async {
            self.executor.cumulativeRequested = 0
            self.executor.cumulativeExecuted = 0
        }
    }

    func stop() {
        executor.stop()
    }

    public static func == (lhs: ApiConnector, rhs: ApiConnector) -> Bool {
        return lhs.executor === rhs.executor && lhs.requester === rhs.requester
    }
}

public struct ApiRequest {
    let requestData: Data
    let continuation: CheckedContinuation<String?, Never>

    let endpointURL: URL?
    let httpMethod: String?
    let headers: [String: String]?

    init(requestData: Data, continuation: CheckedContinuation<String?, Never>) {
        self.requestData = requestData
        self.continuation = continuation
        self.endpointURL = nil
        self.httpMethod = nil
        self.headers = nil
    }

    // Initializer for generic JSON APIs or Page Request
    init(requestData: Data, continuation: CheckedContinuation<String?, Never>, endpointURL: URL, httpMethod: String, headers: [String: String]) {
        self.requestData = requestData
        self.continuation = continuation
        self.endpointURL = endpointURL
        self.httpMethod = httpMethod
        self.headers = headers
    }
}

public class ApiExecutionQueue {
    private var dispatchQueue = DispatchQueue(label: "SwiftApiAdapter.ApiExecutionQueue")
    private var queue: [ApiRequest] = []

    func push(_ request: ApiRequest?) {
        guard let request = request else {
            return
        }
        dispatchQueue.async {
            self.queue.append(request)
        }
    }

    func insertAtBeginning(_ request: ApiRequest?) {
        guard let request = request else {
            return
        }
        dispatchQueue.async {
            self.queue.insert(request, at: 0)
        }
    }

    /// NOTE: Potential for Deadlocks with sync
    ///
    /// While using sync, be cautious. If another task running on dispatchQueue tries to call pop(),
    /// you'll have a deadlock. Given you're using a global queue, this is especially concerning.
    ///
    func pop() -> ApiRequest? {
        var request: ApiRequest? = nil
        dispatchQueue.sync {
            guard !self.queue.isEmpty else {
                return
            }
            request = self.queue.removeFirst()
        }
        return request
    }

    func clear() {
        dispatchQueue.async {
            self.queue.removeAll()
        }
    }
}

public class ApiSerialExecutor {
    var enabled: Bool = false
    let queue = ApiExecutionQueue()

    @Published var cumulativeRequested: Int = 0
    @Published var cumulativeExecuted: Int = 0

    private let executionContext = DispatchQueue(label: "SwiftApiAdapter.ApiSerialExecutor.executionContext", qos: .userInitiated)

    public struct Response: Codable {
        var id: String
        var object: String
        var created: Int
    }

    public struct ResponseHandler {
        func decodeJson(jsonString: String) -> ApiSerialExecutor.Response? {
            let json = jsonString.data(using: .utf8)!

            let decoder = JSONDecoder()
            do {
                let product = try decoder.decode(ApiSerialExecutor.Response.self, from: json)
                return product
            } catch {
                #if DEBUG
                print("[ApiSerialExecutor] Error decoding API Response: \(error)")
                #endif
                return nil
            }
        }
    }

    func initTransaction() {
        DispatchQueue.main.async {
            self.cumulativeRequested = 0
            self.cumulativeExecuted = 0
        }
    }

    func start() {
        #if DEBUG
        print("[ApiSerialExecutor] starting exec loop")
        #endif
        self.enabled = true
        self.executeNextRequest()
    }

    func stop() {
        #if DEBUG
        print("[ApiSerialExecutor] stopping exec loop")
        #endif
        self.enabled = false
    }

    func request(_ requestData: Data) async -> String? {
        DispatchQueue.main.async {
            self.cumulativeRequested = self.cumulativeRequested + 1
        }
        return await withCheckedContinuation { continuation in
            executionContext.async {
                let request = ApiRequest(
                    requestData: requestData, /// JSON Data
                    continuation: continuation
                )
                self.queue.push(request)
            }
        }
    }

    // MARK: - JSON API

    func requestJsonApi(_ requestData: Data, endpoint: URL, method: String, headers: [String: String]) async -> String? {
        DispatchQueue.main.async {
            self.cumulativeRequested = self.cumulativeRequested + 1
        }
        return await withCheckedContinuation { continuation in
            executionContext.async {
                let request = ApiRequest(
                    requestData: requestData, /// JSON Data
                    continuation: continuation,
                    endpointURL: endpoint,
                    httpMethod: method,
                    headers: headers
                )
                self.queue.push(request)
            }
        }
    }

    func executeJsonApiRequest(
        executionRequest: ApiRequest,
        endpoint: URL,
        method: String,
        headers: [String: String],
        continuation: CheckedContinuation<String?, Never>,
        goNextRequest: (() -> Void)? = nil
    ) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.addValue(DEFAULT_USER_AGENT, forHTTPHeaderField: "User-Agent")
        for (key, value) in headers {
            if !key.isEmpty && !value.isEmpty {
                request.addValue(value, forHTTPHeaderField: key)
            }
        }

        if let requestJson = try? JSONSerialization.jsonObject(with: executionRequest.requestData, options: []) as? [String: Any] {
            if let requestBody = try? JSONSerialization.data(withJSONObject: requestJson, options: []) {
                request.httpBody = requestBody
            }
        }

        let defaultConfig = URLSessionConfiguration.default
        defaultConfig.timeoutIntervalForRequest = 180

        let session = URLSession(configuration: defaultConfig)

        let task = session.dataTask(with: request) { data, response, error in
            self.executionContext.async {
                if let error = error {
                    #if DEBUG
                    print(error.localizedDescription)
                    #endif
                    continuation.resume(returning: nil)
                } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data {
                    let responseString = String(data: data, encoding: .utf8)
                    continuation.resume(returning: responseString)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            DispatchQueue.main.async {
                self.cumulativeExecuted = self.cumulativeExecuted + 1
            }
            goNextRequest?()
        }
        task.resume()
    }

    func executeJsonApiImmediately(_ requestData: Data, endpoint: URL, method: String, headers: [String: String]) async -> String? {
        DispatchQueue.main.async {
            self.cumulativeRequested = self.cumulativeRequested + 1
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            executionContext.async {
                let request = ApiRequest(
                    requestData: requestData,
                    continuation: continuation,
                    endpointURL: endpoint,
                    httpMethod: method,
                    headers: headers
                )
                self.executeJsonApiRequest(
                    executionRequest: request,
                    endpoint: endpoint,
                    method: method,
                    headers: headers,
                    continuation: continuation
                )
            }
        }
    }

    // MARK: - Execution Loop

    func executeNextRequest() {
        if !enabled {
            #if DEBUG
            print("[ApiSerialExecutor] exec loop stopped by flag")
            #endif
            return
        }
        if let executionRequest = queue.pop() {
            Task {
                try await Task.sleep(nanoseconds: UInt64(0.5 * Double(NSEC_PER_SEC)))
                guard let endpointURL = executionRequest.endpointURL,
                      let httpMethod = executionRequest.httpMethod,
                      let headers = executionRequest.headers else {
                    self.executeNextRequest()
                    return
                }
                self.executeJsonApiRequest(
                    executionRequest: executionRequest,
                    endpoint: endpointURL,
                    method: httpMethod,
                    headers: headers,
                    continuation: executionRequest.continuation
                ) {
                    self.executeNextRequest()
                }
            }
        } else {
            Task {
                try await Task.sleep(nanoseconds: UInt64(2.0 * Double(NSEC_PER_SEC)))
                self.executeNextRequest()
            }
        }
    }
}

public class ApiRequester {
    let executor: ApiSerialExecutor

    init(executor: ApiSerialExecutor){
        self.executor = executor
    }

    public struct Request: Codable {
        var messages: [Message]
    }

    public struct Message: Codable {
        var key: String
        var value: String
    }

    static func makeMessage(key: String, value: String) -> Message {
        return Message(key: key, value: value)
    }

    public func initTransaction() {
        self.executor.initTransaction()
    }

    public func processJsonApi(endpoint: URL, method: String, headers: [String: String], body: String, immediate: Bool = false) async -> String? {
        let requestData: Data = Data(body.utf8)
        if immediate {
            #if DEBUG
            print("[ApiRequester] JSON API request will be immediately processed")
            #endif
            return await executor.executeJsonApiImmediately(requestData, endpoint: endpoint, method: method, headers: headers)
        } else {
            if !executor.enabled {
                executor.start()
            }
            #if DEBUG
            print("[ApiRequester] JSON API request will be executed in serialized queue")
            #endif
            return await executor.requestJsonApi(requestData, endpoint: endpoint, method: method, headers: headers)
        }
    }
}

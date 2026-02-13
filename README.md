# SwiftApiAdapter

SwiftApiAdapter is a Swift Package that streamlines retrieving remote content (JSON, text, images, and web pages) from Swift apps. It’s especially handy for calling generative AI APIs and for loading + extracting web page content.

This version targets **Swift 6** and uses **structured concurrency** throughout (actors + `async`/`await`) to provide a thread-safe, serial request pipeline.

## Features

- **Actor-based connector manager** (`ApiConnectorManager`) for safe, concurrent access to per-tag connectors.
- **Serial execution / rate limiting** via `ApiSerialExecutor` (an actor with a single worker task).
- **Async/await networking** using `URLSession`.
- **Immediate vs queued requests**: bypass the serial queue when needed.
- **Progress / metrics reporting** via `AsyncStream` (no polling required).
- **Flexible headers** per request, including custom `User-Agent`.
- **Web page extraction** (content + OpenGraph image) via `ApiContentLoader`.

### Important note about `GET` requests

In compliance with standard HTTP usage, **SwiftApiAdapter does not attach a request body if the HTTP method is `GET`**.

If you call an endpoint with `GET` and provide a non-empty body, the body is ignored. If you need to send a payload, use `POST`, `PUT`, etc.

## Installation

### Swift Package Manager

Add SwiftApiAdapter to your project via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/RayKitajima/SwiftApiAdapter.git", from: "1.0.0")
]
```

## Usage

### Importing

```swift
import SwiftApiAdapter
```

## Making JSON API requests

Use `ApiRequester.processJsonApi(...)` to call a JSON endpoint.

```swift
import SwiftApiAdapter

let requester = await ApiConnectorManager.shared.getRequester(for: "ExampleAPI")

let endpoint = URL(string: "https://example.com/api")!
let headers = [
    "User-Agent": "Your Custom User-Agent",
    "Content-Type": "application/json"
]

let response = await requester.processJsonApi(
    endpoint: endpoint,
    method: "POST",
    headers: headers,
    body: #"{"hello":"world"}"#,
    immediate: false // false = serialized queue, true = bypass queue
)

print(response?.responseString ?? "<no response>")
```

### Immediate vs queued execution

- `immediate: false` (default): request is enqueued, executed **serially**, and rate-limited.
- `immediate: true`: request bypasses the serial queue and executes immediately.

## Loading API content via `ApiContentLoader`

`ApiContentLoader` provides a higher-level interface for calling APIs and extracting values out of the JSON response using a path.

### Example: load a value from JSON

```swift
let apiContent = ApiContent(
    id: UUID(),
    name: "Example API Content",
    endpoint: "https://exampleapi.com/data",
    method: .get,
    headers: ["Authorization": "Bearer your_access_token"],
    body: "",
    arguments: [
        // Extract: response["data"]["result"]
        "result": "[\"data\"][\"result\"]"
    ],
    extraData: ["info": "additional info"]
)

do {
    let rack = try await ApiContentLoader.load(
        contextId: UUID(),
        apiContent: apiContent
    )

    if let rack {
        print("Result:", rack.arguments["result"] ?? "<missing>")
    } else {
        print("Failed to load API data")
    }
} catch {
    print("Load failed:", error)
}
```

## Loading web page content

You can also load and extract web page content using the same interface.

```swift
let page = ApiContent(
    id: UUID(),
    name: "Web Page Content",
    endpoint: "https://example.com/page",
    method: .get,
    headers: [:],
    body: "",
    contentType: .page
)

do {
    let rack = try await ApiContentLoader.load(
        contextId: UUID(),
        apiContent: page
    )

    if let rack {
        print("content:", rack.arguments["content"] ?? "<missing>")
        print("url:", rack.arguments["url"] ?? "<missing>")
        print("ogimage:", rack.arguments["ogimage"] ?? "<missing>")
        print("finalUrl:", rack.arguments["finalUrl"] ?? "<missing>")
    }
} catch {
    print("Load failed:", error)
}
```

## Observing request metrics (structured concurrency)

`ApiSerialExecutor` reports progress via `AsyncStream`.

```swift
let executor = await ApiConnectorManager.shared.getExecutor(for: "ExampleAPI")

Task {
    for await metrics in await executor.metricsUpdates() {
        print("Executed \(metrics.cumulativeExecuted) / \(metrics.cumulativeRequested)")
    }
}
```

This works well for logging, CLI tools, or bridging into UI state.

## SwiftUI integration

Below is one simple way to bridge `AsyncStream` metrics into SwiftUI using an `ObservableObject`.

```swift
import SwiftUI
import SwiftApiAdapter

@MainActor
final class ApiController: ObservableObject {
    @Published var cumulativeRequested: Int = 0
    @Published var cumulativeExecuted: Int = 0

    private var metricsTask: Task<Void, Never>?

    func observeMetrics(tag: String) {
        metricsTask?.cancel()
        metricsTask = Task {
            let executor = await ApiConnectorManager.shared.getExecutor(for: tag)
            for await metrics in await executor.metricsUpdates() {
                cumulativeRequested = metrics.cumulativeRequested
                cumulativeExecuted  = metrics.cumulativeExecuted
            }
        }
    }

    deinit {
        metricsTask?.cancel()
    }
}

struct ApiView: View {
    @StateObject var apiController = ApiController()

    var body: some View {
        HStack(spacing: 6) {
            Text("Generating")
            Text("(\(apiController.cumulativeExecuted)/\(apiController.cumulativeRequested))")
                .foregroundStyle(.secondary)
            Image(systemName: "ellipsis")
        }
        .task {
            apiController.observeMetrics(tag: "ExampleAPI")
        }
    }
}
```

## Managing connectors

`ApiConnectorManager` is an **actor**, so calls from outside the actor require `await`.

```swift
// Get a connector / requester / executor
let connector  = await ApiConnectorManager.shared.getConnector(for: "Tag")
let requester  = await ApiConnectorManager.shared.getRequester(for: "Tag")
let executor   = await ApiConnectorManager.shared.getExecutor(for: "Tag")

// Clear one connector (stops its executor)
await ApiConnectorManager.shared.clearConnector(for: "Tag")

// Clear all connectors
await ApiConnectorManager.shared.clearAllConnectors()
```

## Contributing

Contributions are welcome — feel free to open issues or submit PRs.

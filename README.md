# SwiftApiAdapter

SwiftApiAdapter is a Swift package designed to streamline the process of retrieving remote content, such as text and images, in Swift applications. It provides a robust framework for managing API connectors, handling requests asynchronously, and processing responses, focusing on efficiency and effectiveness. This package is especially well-suited for calling generative AI APIs and loading web page content.

## Features

- **Singleton Connector Manager**: Simplify the management of API connectors with a singleton manager.
- **Asynchronous API Requests**: Leverage Swift's async-await patterns for efficient, non-blocking API requests.
- **Serial Execution of Requests**: Maintain order and consistency with serialized request handling.
- **Customizable Request and Response Handling**: Tailor request setups and response processes to your needs.
- **Concurrency and Thread Safety**: Designed to be thread-safe and support concurrent operations.
- **Flexible Header Management**: Customize request headers, including `User-Agent`, on a per-request basis.
- **SwiftUI Integration**: Utilize SwiftUI to reactively update UI components based on API activity.
- **Extra Data Management**: Store additional necessary information about the API using the `extraData` field.
- **Web Page Content Loading**: Load and process web page content using the same interface as for API content.

## Installation

### Swift Package Manager

Add SwiftApiAdapter to your project via Swift Package Manager by including it in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/SwiftApiAdapter.git", from: "1.0.0")
]
```

Ensure the repository URL matches the location of your Swift package.

## Usage

### Importing the Package

Import SwiftApiAdapter in Swift files where API handling is needed:

```swift
import SwiftApiAdapter
```

### Example Usage

#### Sending an API request with custom headers

1. **Obtain an ApiConnector**:

```swift
let apiConnector = ApiConnectorManager.shared.getConnector(for: "ExampleAPI")
```

2. **Send an API request** with custom headers including `User-Agent`:

```swift
let endpoint = URL(string: "https://example.com/api")!
let headers = [
    "User-Agent": "Your Custom User-Agent",
    "Content-Type": "application/json"
]
let response = await apiConnector.requester.processJsonApi(
    endpoint: endpoint,
    method: "GET",
    headers: headers,
    body: "" // Empty body for GET request
)
```

#### Using ApiContentLoader to Load API Content

This example demonstrates how to use `ApiContentLoader` to load specific data from an API response into your application. The example fetches a value keyed by `"result"` within the nested `"data"` JSON object.

1. **Define ApiContent**:

   Configure your API content by specifying the endpoint, HTTP method, headers, and any arguments necessary to extract specific data from the API response. You can also add any extra data needed for managing the API using the `extraData` field.

```swift
let apiContent = ApiContent(
    id: UUID(),
    name: "Example API Content",
    endpoint: "https://exampleapi.com/data",
    method: .get,
    headers: ["Authorization": "Bearer your_access_token"],
    body: "",  // No body needed for GET request
    arguments: ["result": "[\"data\"][\"result\"]"],  // Path to extract `result` from the JSON response
    extraData: ["info": "additional info"]  // Additional data
)
```

2. **Load content using ApiContentLoader**:

   Use the `ApiContentLoader.load` method to make the API call and process the response, extracting the `result` value based on the provided path.

```swift
do {
    let apiContentRack = try await ApiContentLoader.load(
        contextId: UUID(),  // Context ID to uniquely identify this load operation
        apiContent: apiContent
    )
    if let apiContentRack = apiContentRack {
        let resultValue = apiContentRack.arguments["result"] ?? "No result found"
        print("API Data Loaded: \(resultValue)")
        if let extraInfo = apiContent.extraData?["info"] as? String {
            print("Extra Info: \(extraInfo)")
        }
    } else {
        print("Failed to load API data.")
    }
} catch {
    print("An error occurred: \(error)")
}
```

#### Loading Web Page Content

You can also use `ApiContentLoader` to load and process web page content using the same interface.

1. **Define ApiContent** for a web page:

```swift
let apiContentPage = ApiContent(
    id: UUID(),
    name: "Web Page Content",
    endpoint: "https://example.com/page",
    method: .get,
    headers: ["Authorization": "Bearer your_access_token"],
    body: "",  // No body needed for GET request
    contentType: .page
)
```

2. **Load web page content using ApiContentLoader**:

   Use the `ApiContentLoader.load` method to make the request and process the web page content. The `content`, `url`, `ogimage` and `finalUrl` fields are automatically extracted and set for the `ApiContentRack`.

```swift
do {
    let apiContentRack = try await ApiContentLoader.load(
        contextId: UUID(),  // Context ID to uniquely identify this load operation
        apiContent: apiContentPage
    )
    if let apiContentRack = apiContentRack {
        let content = apiContentRack.arguments["content"] ?? "No content found"
        let url = apiContentRack.arguments["url"] ?? "No URL found"
        let ogimage = apiContentRack.arguments["ogimage"] ?? "No image found"
        let finalUrl = apiContentRack.arguments["finalUrl"] ?? "Actual endpoint" 
        print("Web Page Content Loaded: \(content)")
        print("URL: \(url)")
        print("OpenGraph Image: \(ogimage)")
        print("Actual endpoint: \(finalUrl)")
    } else {
        print("Failed to load web page content.")
    }
} catch {
    print("An error occurred: \(error)")
}
```

#### Integrating with SwiftUI

The following example demonstrates how to integrate `SwiftApiAdapter` with SwiftUI, enabling you to reactively update the UI based on API request counts and other dynamic data.

##### Controller

Create a controller that manages API interactions and updates observable properties:

```swift
import SwiftUI

class ApiController: NSObject, ObservableObject {
    @Published var cumulativeRequested: Int = 0
    @Published var cumulativeExecuted: Int = 0

    var apiConnector: ApiConnector?

    func generate() async throws {
        let connector = ApiConnectorManager.shared.getConnector(for: "ExampleAPI")
        self.apiConnector = connector
        connector.initTransaction()

        DispatchQueue.main.async {
            self.apiConnector?.executor.$cumulativeRequested.assign(to: &self.$cumulativeRequested)
            self.apiConnector?.executor.$cumulativeExecuted.assign(to: &self.$cumulativeExecuted)
        }

        connector.executor.start()
    }
}
```

##### View

Utilize SwiftUI views to reflect the state of API operations:

```swift
import SwiftUI

struct ApiView: View {
    @ObservedObject var apiController: ApiController

    var body: some View {
        HStack(spacing: 5) {
            Text("Generating")
            Text("(\(apiController.cumulativeExecuted)/\(apiController.cumulativeRequested))")
                .foregroundColor(.secondary)
            Image(systemName: "ellipsis")
                .animation(.easeInOut, value: apiController.cumulativeExecuted)
        }
    }
}
```

#### Using ApiContentLoader to Load API Content in SwiftUI

SwiftUI can dynamically update views based on data fetched from APIs. Below, we demonstrate how to use `ApiContentLoader` within a SwiftUI view to load and display both base64 encoded images and text content.

##### Example 1: Displaying a Base64 Encoded Image

1. **Define ApiContent** for a base64 image:

```swift
let apiContentImage = ApiContent(
    id: UUID(),
    name: "Image API Content",
    endpoint: "https://exampleapi.com/image",
    method: .get,
    headers: ["Authorization": "Bearer your_access_token"],
    body: "",
    arguments: ["image": "[\"data\"][0][\"message\"][\"content\"]"],
    contentType: .base64image,
    extraData: ["info": "additional image info"]
)
```

2. **SwiftUI View** to display the image:

```swift
import SwiftUI

struct ImageView: View {
    @ObservedObject var apiController: ApiController

    var body: some View {
        VStack {
            if let imageData = apiController.imageData {
                Image(uiImage: UIImage(data: imageData)!)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Text("Loading Image...")
            }
        }
        .onAppear {
            Task {
                await apiController.loadImageContent()
            }
        }
    }
}
```

3. **ApiController to load image content**:

```swift
import Combine

class ApiController: ObservableObject {
    @Published var imageData: Data?

    func loadImageContent() async {
        do {
            let apiContentRack = try await ApiContentLoader.load(
                contextId: UUID(),
                apiContent: apiContentImage
            )
            if let apiContentRack = apiContentRack, let base64String = apiContentRack.arguments["image"],
               let imageData = Data(base64Encoded: base64String) {
                DispatchQueue.main.async {
                    self.imageData = imageData
                }
            }
        } catch {
            print("Error loading image: \(error)")
        }
    }
}
```

##### Example 2: Displaying Text Content

1. **Define ApiContent** for text:

```swift
let apiContentText = ApiContent(
    id: UUID(),
    name: "Text API Content",
    endpoint: "https://exampleapi.com/text",
    method: .get,
    headers: ["Authorization": "Bearer your_access_token"],
    body: "",
    arguments: ["text": "[\"choices\"][0][\"message\"][\"content\"]"],
    contentType: .text,
    extraData: ["info": "additional text info"]
)
```

2. **SwiftUI View** to display the text:

```swift
import SwiftUI

struct TextView: View {
    @ObservedObject var apiController: ApiController

    var body: some View {
        Text(apiController.textData ?? "Loading Text...")
            .onAppear {
                Task {
                    await apiController.loadTextContent()
                }
            }
    }
}
```

3. **ApiController to load text content**:

```swift
import Combine

class ApiController: ObservableObject {
    @Published var textData: String?

    func loadTextContent() async {
        do {
            let apiContentRack = try await ApiContentLoader.load(
                contextId: UUID(),
                apiContent: apiContentText
            )
            if let apiContentRack = apiContentRack, let text = apiContentRack.arguments["text"] {
                DispatchQueue.main.async {
                    self.textData = text
                }
            }
        } catch {
            print("Error loading text: \(error)")
        }
    }
}
```

These examples illustrate how to fetch and display API content reactively in a SwiftUI application. They show a pattern of initiating API requests on view appearance and updating the view state based on the results, thus integrating network operations seamlessly within the SwiftUI lifecycle.

### Managing API Connectors

- **Retrieve a specific ApiConnector**:

```swift
let connector = ApiConnectorManager.shared.getConnector(for: "Tag")
```

- **Clear a specific connector**:

```swift
ApiConnectorManager.shared.clearConnector(for: "Tag")
```

- **Clear all connectors**:

```swift
ApiConnectorManager.shared.clearAllConnectors()
```

## Configuration

You can customize headers for each API request, allowing the setting of `User-Agent` and other necessary headers depending on the endpoint requirements.

## Contributing

We encourage contributions! Please feel free to submit pull requests or open issues to suggest features, improvements, or bug fixes.

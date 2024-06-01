import XCTest
import Foundation
import SwiftyJSON
@testable import SwiftApiAdapter

final class ApiContentLoaderTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testLoadValidApiContent() async throws {
        // Mocking ApiContent
        let mockApiContent = ApiContent(
            id: UUID(),
            name: "Test API",
            endpoint: "https://jsonplaceholder.typicode.com/posts/1",
            method: .get,
            headers: [:],
            body: "",
            arguments: ["title": "[\"title\"]"]
        )

        let mockContextId = UUID()

        let apiContentRack = try await ApiContentLoader.load(contextId: mockContextId, apiContent: mockApiContent)

        XCTAssertNotNil(apiContentRack)
        XCTAssertEqual(apiContentRack?.arguments["title"], "sunt aut facere repellat provident occaecati excepturi optio reprehenderit")
    }

    func testLoadInvalidUrl() async throws {
        let mockApiContent = ApiContent(
            id: UUID(),
            name: "Test API",
            endpoint: "invalid_url",
            method: .get,
            headers: [:],
            body: "",
            arguments: ["title": "$.title"]
        )

        let mockContextId = UUID()

        let apiContentRack = try await ApiContentLoader.load(contextId: mockContextId, apiContent: mockApiContent)

        XCTAssertNil(apiContentRack)
    }

    func testExtractValue() throws {
        let jsonString = """
        {
            "title": "sunt aut facere repellat provident occaecati excepturi optio reprehenderit",
            "userId": 1,
            "id": 1,
            "body": "quia et suscipit\\nsuscipit..."
        }
        """
        let jsonData = jsonString.data(using: .utf8)!
        let json = try JSON(data: jsonData)

        let title = ApiContentLoader.extractValue(from: json, withPath: "[\"title\"]")
        XCTAssertEqual(title, "sunt aut facere repellat provident occaecati excepturi optio reprehenderit")
    }
}

import XCTest
import Foundation
import SwiftyJSON
@testable import SwiftApiAdapter

class ApiConnectorManagerTests: XCTestCase {

    func testGetConnector() async {
        let tag = "testTag-\(UUID().uuidString)"

        let connector1 = await ApiConnectorManager.shared.getConnector(for: tag)
        XCTAssertNotNil(connector1)

        let connector2 = await ApiConnectorManager.shared.getConnector(for: tag)
        XCTAssertEqual(connector1, connector2)

        // Cleanup
        await ApiConnectorManager.shared.clearConnector(for: tag)
    }

    func testClearConnector() async {
        let tag = "testTag-\(UUID().uuidString)"
        let connector = await ApiConnectorManager.shared.getConnector(for: tag)
        XCTAssertNotNil(connector)

        await ApiConnectorManager.shared.clearConnector(for: tag)
        let newConnector = await ApiConnectorManager.shared.getConnector(for: tag)
        XCTAssertNotEqual(connector, newConnector)

        // Cleanup
        await ApiConnectorManager.shared.clearConnector(for: tag)
    }

    func testClearAllConnectors() async {
        let tag1 = "testTag1-\(UUID().uuidString)"
        let tag2 = "testTag2-\(UUID().uuidString)"
        let connector1 = await ApiConnectorManager.shared.getConnector(for: tag1)
        let connector2 = await ApiConnectorManager.shared.getConnector(for: tag2)

        await ApiConnectorManager.shared.clearAllConnectors()

        let newConnector1 = await ApiConnectorManager.shared.getConnector(for: tag1)
        let newConnector2 = await ApiConnectorManager.shared.getConnector(for: tag2)

        XCTAssertNotEqual(connector1, newConnector1)
        XCTAssertNotEqual(connector2, newConnector2)

        // Cleanup (avoid leaking state across the test bundle)
        await ApiConnectorManager.shared.clearAllConnectors()
    }
}

class ApiSerialExecutorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        JsonPlaceholderURLProtocol.register()
    }

    func testRequestJsonApi() async throws {
        let executor = ApiSerialExecutor()

        let endpoint = URL(string: "https://jsonplaceholder.typicode.com/posts/1")!
        let method = "GET"
        let headers = ["Content-Type": "application/json; charset=UTF-8"]

        let apiResponse = await executor.executeJsonApiImmediately(Data(), endpoint: endpoint, method: method, headers: headers)

        XCTAssertNotNil(apiResponse)

        if let apiResponse = apiResponse, let jsonString = apiResponse.responseString {
            let jsonData = jsonString.data(using: .utf8)!
            let json = try JSON(data: jsonData)

            XCTAssertEqual(json["title"].string, "sunt aut facere repellat provident occaecati excepturi optio reprehenderit")
            XCTAssertEqual(json["body"].string, "quia et suscipit\nsuscipit recusandae consequuntur expedita et cum\nreprehenderit molestiae ut ut quas totam\nnostrum rerum est autem sunt rem eveniet architecto")
            XCTAssertEqual(json["userId"].int, 1)
            XCTAssertEqual(json["id"].int, 1)
        }
    }
}

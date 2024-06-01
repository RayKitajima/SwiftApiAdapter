import XCTest
import Foundation
import SwiftyJSON
@testable import SwiftApiAdapter

class ApiConnectorManagerTests: XCTestCase {

    func testGetConnector() {
        let tag = "testTag"
        let connector1 = ApiConnectorManager.shared.getConnector(for: tag)
        XCTAssertNotNil(connector1)

        let connector2 = ApiConnectorManager.shared.getConnector(for: tag)
        XCTAssertEqual(connector1, connector2)
    }

    func testClearConnector() {
        let tag = "testTag"
        let connector = ApiConnectorManager.shared.getConnector(for: tag)
        XCTAssertNotNil(connector)

        ApiConnectorManager.shared.clearConnector(for: tag)
        let newConnector = ApiConnectorManager.shared.getConnector(for: tag)
        XCTAssertNotEqual(connector, newConnector)
    }

    func testClearAllConnectors() {
        let tag1 = "testTag1"
        let tag2 = "testTag2"
        let connector1 = ApiConnectorManager.shared.getConnector(for: tag1)
        let connector2 = ApiConnectorManager.shared.getConnector(for: tag2)

        ApiConnectorManager.shared.clearAllConnectors()

        let newConnector1 = ApiConnectorManager.shared.getConnector(for: tag1)
        let newConnector2 = ApiConnectorManager.shared.getConnector(for: tag2)

        XCTAssertNotEqual(connector1, newConnector1)
        XCTAssertNotEqual(connector2, newConnector2)
    }
}

class ApiSerialExecutorTests: XCTestCase {

    func testRequestJsonApi() async throws {
        let executor = ApiSerialExecutor()

        let endpoint = URL(string: "https://jsonplaceholder.typicode.com/posts/1")!
        let method = "GET"
        let headers = ["Content-Type": "application/json; charset=UTF-8"]

        let responseString = await executor.executeJsonApiImmediately(Data(), endpoint: endpoint, method: method, headers: headers)

        XCTAssertNotNil(responseString)
        if let responseString = responseString {
            let json = try JSON(data: responseString.data(using: .utf8)!)
            XCTAssertEqual(json["title"].string, "sunt aut facere repellat provident occaecati excepturi optio reprehenderit")
            XCTAssertEqual(json["body"].string, "quia et suscipit\nsuscipit recusandae consequuntur expedita et cum\nreprehenderit molestiae ut ut quas totam\nnostrum rerum est autem sunt rem eveniet architecto")
            XCTAssertEqual(json["userId"].int, 1)
            XCTAssertEqual(json["id"].int, 1)
        }
    }
}

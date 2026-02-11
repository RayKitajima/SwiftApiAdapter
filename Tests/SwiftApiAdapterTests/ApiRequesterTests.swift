import XCTest
import Foundation
import SwiftyJSON
@testable import SwiftApiAdapter

class ApiRequesterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        JsonPlaceholderURLProtocol.register()
    }

    func testProcessJsonApi() async throws {
        let executor = ApiSerialExecutor()
        let requester = ApiRequester(executor: executor)

        let endpoint = URL(string: "https://jsonplaceholder.typicode.com/posts/1")!
        let method = "GET"
        let headers = ["Content-Type": "application/json; charset=UTF-8"]
        let body = "" // GET request typically does not have a body

        let apiResponse = await requester.processJsonApi(
            endpoint: endpoint,
            method: method,
            headers: headers,
            body: body,
            immediate: true
        )

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

import XCTest
import Foundation
@testable import SwiftApiAdapter

class ApiContentTests: XCTestCase {

    func testApiContentInitialization() {
        let extraData: [String: Any] = [
            "info": "test info",
            "version": "1.0",  // Treating as string
            "count": 42,
            "price": 19.99,
            "active": true,
            "nullValue": NSNull()
        ]

        let apiContent = ApiContent(
            id: UUID(),
            name: "Test API",
            endpoint: "https://example.com/api",
            method: .get,
            headers: ["Authorization": "Bearer token"],
            body: "",
            arguments: ["arg": "value"],
            contentType: .text,
            description: "A test API",
            extraData: extraData
        )

        XCTAssertEqual(apiContent.extraData?.data["info"] as? String, "test info")
        XCTAssertEqual(apiContent.extraData?.data["version"] as? String, "1.0")
        XCTAssertEqual(apiContent.extraData?.data["count"] as? Int, 42)
        XCTAssertEqual(apiContent.extraData?.data["price"] as? Double, 19.99)
        XCTAssertEqual(apiContent.extraData?.data["active"] as? Bool, true)
        XCTAssertNotNil(apiContent.extraData?.data["nullValue"] as? NSNull)
    }

    func testApiContentCoding() throws {
        let extraData: [String: Any] = [
            "info": "test info",
            "version": "1.0",  // Treating as string
            "count": 42,
            "price": 19.99,
            "active": true,
            "nullValue": NSNull()
        ]

        let apiContent = ApiContent(
            id: UUID(),
            name: "Test API",
            endpoint: "https://example.com/api",
            method: .get,
            headers: ["Authorization": "Bearer token"],
            body: "",
            arguments: ["arg": "value"],
            contentType: .text,
            description: "A test API",
            extraData: extraData
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(apiContent)

        let decoder = JSONDecoder()
        let decodedApiContent = try decoder.decode(ApiContent.self, from: data)

        XCTAssertEqual(decodedApiContent.extraData?.data["info"] as? String, "test info")
        XCTAssertEqual(decodedApiContent.extraData?.data["version"] as? String, "1.0")
        XCTAssertEqual(decodedApiContent.extraData?.data["count"] as? Int, 42)
        XCTAssertEqual(decodedApiContent.extraData?.data["price"] as? Double, 19.99)
        XCTAssertEqual(decodedApiContent.extraData?.data["active"] as? Bool, true)
        XCTAssertNotNil(decodedApiContent.extraData?.data["nullValue"] as? NSNull)
    }
}

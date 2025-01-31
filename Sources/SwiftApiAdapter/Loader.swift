import Foundation
import SwiftyJSON
import SwiftSoup

public class ApiContentLoader {
    public static func load(contextId: UUID, apiContent: ApiContent) async throws -> ApiContentRack? {
        let endpoint = apiContent.endpoint

        guard let url = URL(string: endpoint) else {
            return nil
        }

        guard let apiResponse = await ApiConnectorManager.shared.getRequester(for: contextId.uuidString).processJsonApi(
            endpoint: url,
            method: apiContent.method.rawValue,
            headers: apiContent.headers,
            body: apiContent.body, /// String
            immediate: true
        ) else {
            #if DEBUG
            print("[ApiContentLoader] failed to call API")
            #endif
            return nil
        }

        guard let responseString = apiResponse.responseString else {
            #if DEBUG
            print("[ApiContentLoader] failed to get response string")
            #endif
            return nil
        }

        let responseData = responseString.data(using: .utf8, allowLossyConversion: false)
        guard let responseData = responseData else {
            #if DEBUG
            print("[ApiContentLoader] failed to get data")
            #endif
            return nil
        }

        if apiContent.contentType == .page {
            let result = extractPage(str: responseString)
            let plainText = result.plain_text
            let pageTitle = result.page_title
            let resourceUrl = apiResponse.finalUrl ?? endpoint
            let ogimage = await OpenGraphImageScraper.scrape(resourceUrl)

            var arguments: [String: String] = [:]
            arguments["pageTitle"] = pageTitle ?? ""
            arguments["content"] = plainText
            arguments["url"] = resourceUrl
            arguments["ogimage"] = ogimage ?? ""
            arguments["finalUrl"] = resourceUrl // For backward compatibility,`url` and `finalUrl` are the same.

            let apiContentRack = ApiContentRack(id: apiContent.id, arguments: arguments)
            return apiContentRack
        } else {
            let responseJson = try JSON(data: responseData)

            var arguments: [String: String] = [:] // extracted argument
            for argument in apiContent.arguments {
                let name = argument.key
                let path = argument.value
                let extractedString = ApiContentLoader.extractValue(from: responseJson, withPath: path)
                if let extractedString = extractedString {
                    arguments[name] = extractedString
                }
            }

            let apiContentRack = ApiContentRack(id: apiContent.id, arguments: arguments)

            return apiContentRack
        }
    }

    static func extractValue(from json: JSON, withPath path: String) -> String? {
        // Remove unwanted characters and split by "][" to get the keys
        let components = path.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).split(separator: "][").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }

        var currentJSON = json
        for component in components {
            if let index = Int(component) {
                currentJSON = currentJSON[index]
            } else {
                currentJSON = currentJSON[component]
            }
        }

        if currentJSON.exists() {
            if let stringValue = currentJSON.string {
                return stringValue
            } else if let intValue = currentJSON.int {
                return String(intValue)
            } else {
                // If the extracted JSON is neither a string nor an integer,
                // convert the entire JSON to a string representation.
                return currentJSON.rawString()
            }
        }

        return nil
    }

    static func extractPage(str: String) -> (plain_text: String, page_title: String?) {
        do {
            let doc = try SwiftSoup.parse(str)
            let title = try doc.title()
            let text = try doc.text()
            return (plain_text: text, page_title: title)
        } catch {
            return (plain_text: str, page_title: nil)
        }
    }
}

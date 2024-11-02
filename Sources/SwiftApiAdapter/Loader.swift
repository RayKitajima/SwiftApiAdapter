
import Foundation
import SwiftyJSON

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

        let finalUrl = apiResponse.finalUrl ?? endpoint

        if apiContent.contentType == .page {
            let result = extractPage(str: responseString)
            let plainText = result.plain_text
            let resourceUrl = result.finalUrl ?? finalUrl
            let ogimage = await OpenGraphImageScraper.scrape(resourceUrl)

            var arguments: [String: String] = [:] // extracted argument
            arguments["content"] = plainText
            arguments["url"] = resourceUrl
            arguments["ogimage"] = ogimage ?? ""
            arguments["finalUrl"] = finalUrl

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

            // Include the final URL in the arguments
            //arguments["finalUrl"] = finalUrl

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

    static func extractPage(str: String) -> (plain_text: String, finalUrl: String?) {
        let lines = str.split(separator: "\n")

        // Assuming the last line contains the finalUrl information
        let finalUrlLine = lines.last ?? ""

        let finalUrlPrefix = "finalUrl:"
        if finalUrlLine.hasPrefix(finalUrlPrefix) {
            let finalUrl = String(finalUrlLine.dropFirst(finalUrlPrefix.count))
            let plain_text = lines.dropLast().joined(separator: "\n")
            return (plain_text, finalUrl == "nil" ? nil : finalUrl)
        }
        return (str, nil)  // Return the original data and nil if finalUrl isn't found
    }
}

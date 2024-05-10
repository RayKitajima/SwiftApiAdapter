
import Foundation
import SwiftyJSON

public class ApiContentLoader {
    public static func load(contextId: UUID, apiContent: ApiContent) async throws -> ApiContentRack? {
        let endoint = apiContent.endpoint

        guard let url = URL(string: endoint) else {
            return nil
        }

        let responseString = await ApiConnectorManager.shared.getRequester(for: contextId.uuidString).processJsonApi(
            endpoint: url,
            method: apiContent.method.rawValue,
            headers: apiContent.headers,
            body: apiContent.body, /// String
            immediate: true
        )
        guard let responseString = responseString else {
            #if DEBUG
            print("[ApiContentLoader] failed to call API")
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
}

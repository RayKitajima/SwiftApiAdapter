import Foundation
import SwiftyJSON
import SwiftSoup

#if canImport(ImagePlayground)
import ImagePlayground
#endif

#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

#if canImport(ImagePlayground)
@available(iOS 18.4, macOS 15.4, visionOS 2.4, *)
extension ImagePlaygroundStyle {
    init?(string: String) {
        switch string.lowercased() {
        case "animation":    self = .animation
        case "illustration": self = .illustration
        case "sketch":       self = .sketch
        default:             return nil
        }
    }
}
#endif

private func ipgPNGData(from cgImage: CGImage) -> Data? {
    #if canImport(UIKit)
    return UIImage(cgImage: cgImage).pngData()
    #elseif canImport(AppKit) && !targetEnvironment(macCatalyst)
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:])
    #else
    return nil
    #endif
}

enum ImagePlaygroundGeneratorError: Error {
    case osTooOld
    case generationFailed
}

struct ImagePlaygroundGenerator {
    static func generate(prompt: String,
                         styleString: String,
                         limit: Int) async throws -> String {
        #if canImport(ImagePlayground)
        guard #available(iOS 18.4, macOS 15.4, visionOS 2.4, *) else {
            throw ImagePlaygroundGeneratorError.osTooOld
        }

        let style = ImagePlaygroundStyle(string: styleString) ?? .animation
        let creator = try await ImageCreator()
        let seq = creator.images(for: [.text(prompt)], style: style, limit: limit)

        if let first = try await seq.first(where: { _ in true }),
           let png = ipgPNGData(from: first.cgImage) {
            return png.base64EncodedString()
        }
        throw ImagePlaygroundGeneratorError.generationFailed
        #else
        throw ImagePlaygroundGeneratorError.osTooOld
        #endif
    }
}

private struct ImagePlaygroundRequestBody: Decodable {
    var prompt: String
    var style: String
    var limit: Int?
}

enum FoundationModelsGeneratorError: Error {
    case osTooOld
    case generationFailed
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
struct FoundationModelsGenerator {
    static func generate(prompt: String,
                         instructions: String? = nil,
                         temperature: Double? = nil,
                         maxTokens: Int? = nil) async throws -> String {

        #if canImport(FoundationModels)
        // Create or reuse a session
        let session: LanguageModelSession = {
            if let instructions, !instructions.isEmpty {
                return LanguageModelSession(instructions: instructions)
            } else {
                return LanguageModelSession()
            }
        }()

        // Prepare generation options (all are optional)
        var opts = GenerationOptions()
        if let temperature { opts.temperature            = temperature }
        if let maxTokens   { opts.maximumResponseTokens  = maxTokens }

        // Ask the model
        let response = try await session.respond(to: prompt, options: opts)
        return response.content
        #else
        throw FoundationModelsGeneratorError.osTooOld
        #endif
    }
}

private struct FoundationModelsRequestBody: Decodable {
    let prompt: String
    let instructions: String?
    let temperature: Double?
    let maxTokens: Int?
}

public class ApiContentLoader {
    public static func load(contextId: UUID, apiContent: ApiContent) async throws -> ApiContentRack? {
        if apiContent.endpoint.hasPrefix("imageplayground://") {
            if let data = apiContent.body.data(using: .utf8) {
                do {
                    let body = try JSONDecoder().decode(ImagePlaygroundRequestBody.self, from: data)
                    let base64 = try await ImagePlaygroundGenerator.generate(
                        prompt: body.prompt,
                        styleString: body.style,
                        limit: body.limit ?? 1
                    )
                    return ApiContentRack(id: apiContent.id, arguments: ["base64image": base64])
                } catch {
                    #if DEBUG
                    print("[ApiContentLoader] ImagePlayground generation failed: \(error)")
                    #endif
                    return nil
                }
            } else {
                return nil
            }
        }

        if apiContent.endpoint.hasPrefix("foundationmodels://") {
            guard let data = apiContent.body.data(using: .utf8) else { return nil }

            do {
                let body = try JSONDecoder().decode(FoundationModelsRequestBody.self, from: data)

                #if canImport(FoundationModels)
                if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                    let generated = try await FoundationModelsGenerator.generate(
                        prompt:       body.prompt,
                        instructions: body.instructions,
                        temperature:  body.temperature,
                        maxTokens:    body.maxTokens
                    )

                    return ApiContentRack(
                        id: apiContent.id,
                        arguments: ["content": generated]
                    )
                } else {
                    #if DEBUG
                    print("[ApiContentLoader] FoundationModels not supported on this OS version")
                    #endif
                    return nil
                }
                #else
                return nil
                #endif

            } catch {
                #if DEBUG
                print("[ApiContentLoader] FoundationModels generation failed: \(error)")
                #endif
                return nil
            }
        }

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

import Foundation
@preconcurrency import SwiftyJSON
@preconcurrency import SwiftSoup

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
    /// Marks the start of a non-HTTP generation "request" (e.g., imageplayground/foundationmodels)
    /// and returns a closure that must be called to mark completion.
    /// This aligns the counters with how ApiSerialExecutor tracks HTTP requests.
    private static func markRequestStart(for contextId: UUID) async -> () -> Void {
        // Non-HTTP generations should contribute to the same metrics as HTTP requests.
        let executor = await ApiConnectorManager.shared.getExecutor(for: contextId.uuidString)
        await executor.markRequested()

        // `defer` cannot `await`, so return a sync closure that updates counters via a Task.
        return {
            Task { await executor.markExecuted() }
        }
    }

    public static func load(contextId: UUID, apiContent: ApiContent) async throws -> ApiContentRack? {
        if apiContent.endpoint.hasPrefix("imageplayground://") {
            if let data = apiContent.body.data(using: .utf8) {
                do {
                    let body = try JSONDecoder().decode(ImagePlaygroundRequestBody.self, from: data)

                    // Track request/execute for ImagePlayground generation
                    let finish = await Self.markRequestStart(for: contextId)
                    defer { finish() }

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

                // Track request/execute for FoundationModels generation
                let finish = await Self.markRequestStart(for: contextId)
                defer { finish() }

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
                        arguments: ["text": generated]
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

        let requester = await ApiConnectorManager.shared.getRequester(for: contextId.uuidString)
        guard let apiResponse = await requester.processJsonApi(
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

        // Backward-compatible behaviour: only treat HTTP 200 as success for `load(...)`.
        if let code = apiResponse.statusCode, code != 200 {
            #if DEBUG
            print("[ApiContentLoader] HTTP status \(code) (treating as failure for load())")
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


    /// A testing-oriented variant of `load(...)` that returns raw response information
    /// (status code / headers / body) even when the status code is non-200.
    ///
    /// This is useful for tools such as StarlightApiLab, where users expect to inspect
    /// error payloads and response metadata.
    public static func loadDetailed(contextId: UUID, apiContent: ApiContent) async throws -> ApiLoadDetailedResult {
        // Non-HTTP generators
        if apiContent.endpoint.hasPrefix("imageplayground://") {
            guard let data = apiContent.body.data(using: .utf8) else {
                return ApiLoadDetailedResult(
                    rack: nil,
                    responseString: nil,
                    finalUrl: nil,
                    statusCode: nil,
                    headers: [:],
                    errorDescription: "Invalid request body (expected JSON)."
                )
            }

            do {
                let body = try JSONDecoder().decode(ImagePlaygroundRequestBody.self, from: data)

                let finish = await Self.markRequestStart(for: contextId)
                defer { finish() }

                let base64 = try await ImagePlaygroundGenerator.generate(
                    prompt: body.prompt,
                    styleString: body.style,
                    limit: body.limit ?? 1
                )

                let rack = ApiContentRack(id: apiContent.id, arguments: ["base64image": base64])
                return ApiLoadDetailedResult(
                    rack: rack,
                    responseString: base64,
                    finalUrl: nil,
                    statusCode: nil,
                    headers: [:],
                    errorDescription: nil
                )
            } catch {
                #if DEBUG
                print("[ApiContentLoader] ImagePlayground generation failed: \(error)")
                #endif
                return ApiLoadDetailedResult(
                    rack: nil,
                    responseString: nil,
                    finalUrl: nil,
                    statusCode: nil,
                    headers: [:],
                    errorDescription: error.localizedDescription
                )
            }
        }

        if apiContent.endpoint.hasPrefix("foundationmodels://") {
            guard let data = apiContent.body.data(using: .utf8) else {
                return ApiLoadDetailedResult(
                    rack: nil,
                    responseString: nil,
                    finalUrl: nil,
                    statusCode: nil,
                    headers: [:],
                    errorDescription: "Invalid request body (expected JSON)."
                )
            }

            do {
                let body = try JSONDecoder().decode(FoundationModelsRequestBody.self, from: data)

                let finish = await Self.markRequestStart(for: contextId)
                defer { finish() }

                #if canImport(FoundationModels)
                if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                    let generated = try await FoundationModelsGenerator.generate(
                        prompt:       body.prompt,
                        instructions: body.instructions,
                        temperature:  body.temperature,
                        maxTokens:    body.maxTokens
                    )

                    let rack = ApiContentRack(id: apiContent.id, arguments: ["text": generated])
                    return ApiLoadDetailedResult(
                        rack: rack,
                        responseString: generated,
                        finalUrl: nil,
                        statusCode: nil,
                        headers: [:],
                        errorDescription: nil
                    )
                } else {
                    return ApiLoadDetailedResult(
                        rack: nil,
                        responseString: nil,
                        finalUrl: nil,
                        statusCode: nil,
                        headers: [:],
                        errorDescription: "FoundationModels is not supported on this OS version."
                    )
                }
                #else
                return ApiLoadDetailedResult(
                    rack: nil,
                    responseString: nil,
                    finalUrl: nil,
                    statusCode: nil,
                    headers: [:],
                    errorDescription: "FoundationModels framework is not available."
                )
                #endif

            } catch {
                #if DEBUG
                print("[ApiContentLoader] FoundationModels generation failed: \(error)")
                #endif
                return ApiLoadDetailedResult(
                    rack: nil,
                    responseString: nil,
                    finalUrl: nil,
                    statusCode: nil,
                    headers: [:],
                    errorDescription: error.localizedDescription
                )
            }
        }

        // HTTP request path
        guard let url = URL(string: apiContent.endpoint) else {
            return ApiLoadDetailedResult(
                rack: nil,
                responseString: nil,
                finalUrl: nil,
                statusCode: nil,
                headers: [:],
                errorDescription: "Invalid URL: \(apiContent.endpoint)"
            )
        }

        let requester = await ApiConnectorManager.shared.getRequester(for: contextId.uuidString)
        guard let apiResponse = await requester.processJsonApi(
            endpoint: url,
            method: apiContent.method.rawValue,
            headers: apiContent.headers,
            body: apiContent.body,
            immediate: true
        ) else {
            return ApiLoadDetailedResult(
                rack: nil,
                responseString: nil,
                finalUrl: nil,
                statusCode: nil,
                headers: [:],
                errorDescription: "Failed to call API."
            )
        }

        let rawBody = apiResponse.responseString
        var rack: ApiContentRack? = nil
        var parseError: String? = nil

        if apiContent.contentType == .page {
            if let html = rawBody {
                let result = extractPage(str: html)
                let resourceUrl = apiResponse.finalUrl ?? apiContent.endpoint
                let ogimage = await OpenGraphImageScraper.scrape(resourceUrl)

                var args: [String: String] = [:]
                args["pageTitle"] = result.page_title ?? ""
                args["content"] = result.plain_text
                args["url"] = resourceUrl
                args["ogimage"] = ogimage ?? ""
                args["finalUrl"] = resourceUrl

                rack = ApiContentRack(id: apiContent.id, arguments: args)
            } else {
                parseError = "No response body."
            }
        } else {
            if let body = rawBody,
               let data = body.data(using: .utf8, allowLossyConversion: false) {
                do {
                    let responseJson = try JSON(data: data)

                    var args: [String: String] = [:]
                    for argument in apiContent.arguments {
                        let name = argument.key
                        let path = argument.value
                        if let extracted = ApiContentLoader.extractValue(from: responseJson, withPath: path) {
                            args[name] = extracted
                        }
                    }
                    rack = ApiContentRack(id: apiContent.id, arguments: args)
                } catch {
                    parseError = "Failed to parse JSON response: \(error.localizedDescription)"
                }
            } else {
                parseError = "No response body."
            }
        }

        let combinedError = [apiResponse.errorDescription, parseError]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return ApiLoadDetailedResult(
            rack: rack,
            responseString: rawBody,
            finalUrl: apiResponse.finalUrl,
            statusCode: apiResponse.statusCode,
            headers: apiResponse.headers,
            errorDescription: combinedError.isEmpty ? nil : combinedError
        )
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

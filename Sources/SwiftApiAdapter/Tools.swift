import Foundation
import SwiftSoup

class OpenGraphImageScraper {
    /// Asynchronously scrapes the Open Graph image URL from the given source URL.
    /// - Parameter source: The URL of the webpage to scrape.
    /// - Returns: The Open Graph image URL as a `String`, or `nil` if not found or an error occurs.
    static func scrape(_ source: String) async -> String? {
        #if DEBUG
        print("[OpenGraphImageScraper] Scraping \(source)")
        #endif

        guard let url = URL(string: source) else {
            #if DEBUG
            print("[OpenGraphImageScraper] Invalid URL: \(source)")
            #endif
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                #if DEBUG
                print("[OpenGraphImageScraper] HTTP error: \(httpResponse.statusCode)")
                #endif
                return nil
            }

            guard let html = String(data: data, encoding: .utf8) else {
                #if DEBUG
                print("[OpenGraphImageScraper] Unable to decode HTML")
                #endif
                return nil
            }

            let doc: Document = try SwiftSoup.parseBodyFragment(html)
            let imageUrl = Self.extractOgImage(from: doc, baseUrl: source)
            #if DEBUG
            print("[OpenGraphImageScraper] Image URL: \(String(describing: imageUrl))")
            #endif

            return imageUrl
        } catch {
            #if DEBUG
            print("[OpenGraphImageScraper] Scrape failed: \(error)")
            #endif
            return nil
        }
    }

    /// Extracts the Open Graph image URL from the parsed HTML document.
    /// - Parameters:
    ///   - doc: The parsed HTML document.
    ///   - baseUrl: The base URL of the webpage.
    /// - Returns: The Open Graph image URL as a `String`, or `nil` if not found.
    static func extractOgImage(from doc: Document, baseUrl: String) -> String? {
        do {
            guard let metaTag = try doc.select("meta[property=og:image]").first() else {
                #if DEBUG
                print("[OpenGraphImageScraper] No meta tag with property=og:image found.")
                #endif
                return nil
            }

            let href = try metaTag.attr("content")

            guard !href.isEmpty else {
                #if DEBUG
                print("[OpenGraphImageScraper] 'content' attribute is empty.")
                #endif
                return nil
            }
            guard let url = URL(string: href, relativeTo: URL(string: baseUrl)) else {
                #if DEBUG
                print("[OpenGraphImageScraper] Invalid og:image URL: \(href)")
                #endif
                return nil
            }

            return url.absoluteString
        } catch {
            #if DEBUG
            print("[OpenGraphImageScraper] Failed to extract og:image: \(error)")
            #endif
            return nil
        }
    }
}

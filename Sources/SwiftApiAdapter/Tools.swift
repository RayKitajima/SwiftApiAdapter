import Foundation
import SwiftSoup

class OpenGraphImageScraper {
    static func scrape(_ source: String) -> String? {
        #if DEBUG
        print("[OpenGraphImageScraper] scraping \(source)")
        #endif
        guard let url = URL(string: source) else {
            return nil
        }
        do {
            let html = try String(contentsOf: url) // NOTE: sync but in async block
            let doc: Document = try SwiftSoup.parseBodyFragment(html)
            let imageUrl = Self.extractOgimage(doc:doc, baseUrl:source)
            #if DEBUG
            print("[OpenGraphImageScraper] imageUrl: \(String(describing: imageUrl))")
            #endif
            return imageUrl
        } catch {
            #if DEBUG
            print("[OpenGraphImageScraper] scrape failed: \(error)")
            #endif
            return nil
        }
    }

    static func extractOgimage(doc:Document, baseUrl:String) -> String? {
        do {
            guard let href = try doc.select("meta[property=og:image]").first()?.attr("content") else {
                return nil
            }
            guard let url = URL(string: href, relativeTo: URL(string: baseUrl)) else {
                return nil
            }
            return url.absoluteString
        } catch {
            return nil
        }
    }
}

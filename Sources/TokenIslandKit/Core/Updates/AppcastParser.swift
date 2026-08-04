import Foundation

/// Minimal reader for a Sparkle appcast (RSS with `sparkle:` extensions):
///
///     <item>
///       <title>Version 0.2.0</title>
///       <sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>
///       <pubDate>Sat, 26 Jul 2026 10:00:00 +0000</pubDate>
///       <sparkle:releaseNotesLink>https://…/notes.html</sparkle:releaseNotesLink>
///       <enclosure url="https://…/TokenIsland-0.2.0.zip" sparkle:version="0.2.0"/>
///     </item>
///
/// Deliberately tolerant: an item missing a version or an enclosure is skipped
/// rather than failing the whole feed, and unknown elements are ignored.
enum AppcastParser {
    struct Item: Equatable, Sendable {
        var version: String
        var downloadURL: URL
        var releaseNotesURL: URL?
        var publishedAt: Date?
    }

    static func items(in data: Data) -> [Item] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else { return [] }
        return delegate.items
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var items: [Item] = []

        private var shortVersion: String?
        private var enclosureVersion: String?
        private var downloadURL: URL?
        private var releaseNotesURL: URL?
        private var publishedAt: Date?
        private var titleVersion: String?
        private var currentElement: String?
        private var buffer = ""

        private static let pubDateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            return formatter
        }()

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            currentElement = elementName
            buffer = ""

            switch elementName {
            case "item":
                shortVersion = nil
                enclosureVersion = nil
                downloadURL = nil
                releaseNotesURL = nil
                publishedAt = nil
                titleVersion = nil
            case "enclosure":
                downloadURL = (attributes["url"]).flatMap(URL.init(string:))
                enclosureVersion = attributes["sparkle:shortVersionString"]
                    ?? attributes["sparkle:version"]
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            buffer += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "sparkle:shortVersionString":
                shortVersion = text
            case "sparkle:releaseNotesLink", "releaseNotesLink":
                releaseNotesURL = URL(string: text)
            case "pubDate":
                publishedAt = Self.pubDateFormatter.date(from: text)
            case "title":
                // "Version 0.2.0" — the last resort when the feed omits the
                // sparkle version elements entirely.
                titleVersion = text
                    .split(whereSeparator: { !$0.isNumber && $0 != "." })
                    .first
                    .map(String.init)
            case "item":
                if let version = shortVersion ?? enclosureVersion ?? titleVersion,
                   !version.isEmpty,
                   let downloadURL {
                    items.append(
                        Item(
                            version: version,
                            downloadURL: downloadURL,
                            releaseNotesURL: releaseNotesURL,
                            publishedAt: publishedAt
                        )
                    )
                }
            default:
                break
            }
            buffer = ""
            currentElement = nil
        }
    }
}

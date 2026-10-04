import Foundation

/// An event read from an invite page (Partiful, Luma, or any page that describes one).
struct ImportedEvent: Equatable {
    var title: String
    var start: Date?
    var end: Date?
    var location: String = ""
    var details: String = ""
    var link: String
    var host: String = ""

    /// Where the invite came from, for labels like "Open in Luma".
    var sourceName: String { EventImporter.sourceName(for: link) }

    /// Length in minutes for the timeline: the real length if known (up to a day), else 2 hours.
    var durationMinutes: Int {
        guard let start, let end, end > start else { return 120 }
        return min(Int(end.timeIntervalSince(start) / 60), 24 * 60)
    }

    /// Notes for the event: host and description, kept short.
    var note: String {
        var parts: [String] = []
        if !host.isEmpty { parts.append("Hosted by " + host) }
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append(trimmed.count > 600 ? String(trimmed.prefix(600)) + "…" : trimmed) }
        return parts.joined(separator: "\n\n")
    }
}

/// Reads invite pages without any API: structured data in the page first, then the page's own app data,
/// then (if there's an Anthropic key) AI reading the page text.
enum EventPageParser {
    // MARK: Structured data (schema.org Event in JSON-LD)

    static func jsonLD(html: String, link: String) -> ImportedEvent? {
        for block in scriptBodies(in: html, matching: "application/ld\\+json") {
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            for object in flatten(json) where isEventType(object["@type"]) {
                guard let name = (object["name"] as? String).map(decodeEntities), !name.isEmpty else { continue }
                var event = ImportedEvent(title: name, start: date(object["startDate"]), end: date(object["endDate"]),
                                          link: link)
                event.location = locationText(object["location"])
                event.details = decodeEntities(object["description"] as? String ?? "")
                event.host = organizerName(object["organizer"])
                return event
            }
        }
        return nil
    }

    private static func flatten(_ json: Any) -> [[String: Any]] {
        if let list = json as? [Any] { return list.flatMap(flatten) }
        guard let dict = json as? [String: Any] else { return [] }
        if let graph = dict["@graph"] { return [dict] + flatten(graph) }
        return [dict]
    }

    private static func isEventType(_ value: Any?) -> Bool {
        if let s = value as? String { return s.hasSuffix("Event") }
        if let list = value as? [String] { return list.contains { $0.hasSuffix("Event") } }
        return false
    }

    private static func locationText(_ value: Any?) -> String {
        if let s = value as? String { return decodeEntities(s) }
        if let list = value as? [Any] { return list.lazy.map(locationText).first { !$0.isEmpty } ?? "" }
        guard let dict = value as? [String: Any] else { return "" }
        if (dict["@type"] as? String) == "VirtualLocation" { return "Online" }
        let name = decodeEntities(dict["name"] as? String ?? "")
        let address: String = {
            if let s = dict["address"] as? String { return decodeEntities(s) }
            guard let a = dict["address"] as? [String: Any] else { return "" }
            return ["streetAddress", "addressLocality", "addressRegion"]
                .compactMap { a[$0] as? String }.filter { !$0.isEmpty }.joined(separator: ", ")
        }()
        if name.isEmpty { return address }
        if address.isEmpty || address.hasPrefix(name) { return address.isEmpty ? name : address }
        return name + ", " + address
    }

    private static func organizerName(_ value: Any?) -> String {
        if let dict = value as? [String: Any] { return dict["name"] as? String ?? "" }
        if let list = value as? [Any] {
            return list.compactMap { ($0 as? [String: Any])?["name"] as? String }.joined(separator: ", ")
        }
        return ""
    }

    // MARK: App data embedded in the page (e.g. Next.js __NEXT_DATA__)

    static let startKeys = ["startDate", "start_at", "startsAt", "startAt", "start_time", "startTime", "start"]
    static let endKeys = ["endDate", "end_at", "endsAt", "endAt", "end_time", "endTime", "end"]
    static let titleKeys = ["title", "name"]

    private typealias Candidate = (title: String, start: Date, end: Date?, location: String, details: String)

    /// Looks through any JSON the page ships for objects with a title and a start time. Pages often embed
    /// other events too ("more from this host"), so prefer the one whose title matches the page title.
    static func embedded(html: String, link: String) -> ImportedEvent? {
        var blocks = scriptBodies(in: html, matching: "application/json")
        blocks += scriptBodies(in: html, id: "__NEXT_DATA__")
        var found: [Candidate] = []
        for block in blocks {
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            collect(json, depth: 0, into: &found)
        }
        guard !found.isEmpty else { return nil }
        let meta = metaTags(html: html)
        let pageTitle = (meta["og:title"] ?? meta["twitter:title"] ?? "").lowercased()
        let best = found.first { !pageTitle.isEmpty && pageTitle.contains($0.title.lowercased()) } ?? found[0]
        return ImportedEvent(title: best.title, start: best.start, end: best.end,
                             location: best.location, details: best.details, link: link)
    }

    private static func collect(_ json: Any, depth: Int, into found: inout [Candidate]) {
        guard depth < 14, found.count < 40 else { return }
        if let dict = json as? [String: Any] {
            if let title = titleKeys.lazy.compactMap({ dict[$0] as? String }).first(where: { !$0.isEmpty }),
               let start = startKeys.lazy.compactMap({ date(dict[$0]) }).first {
                let end = endKeys.lazy.compactMap { date(dict[$0]) }.first
                let location = ["geo_address_info", "location", "locationInfo", "venue", "address"]
                    .lazy.map { embeddedLocation(dict[$0]) }.first { !$0.isEmpty } ?? ""
                let details = ["description", "description_md", "summary"].lazy
                    .compactMap { dict[$0] as? String }.first { !$0.isEmpty } ?? ""
                found.append((decodeEntities(title), start, end, location, details))
            }
            for key in dict.keys.sorted() {
                if let value = dict[key] { collect(value, depth: depth + 1, into: &found) }
            }
        } else if let list = json as? [Any] {
            for value in list.prefix(50) {
                collect(value, depth: depth + 1, into: &found)
            }
        }
    }

    private static func embeddedLocation(_ value: Any?) -> String {
        if let s = value as? String { return s }
        guard let dict = value as? [String: Any] else { return "" }
        for key in ["full_address", "address", "formattedAddress", "displayName", "name", "description"] {
            if let s = dict[key] as? String, !s.isEmpty { return s }
            if let nested = dict[key] as? [String: Any] {
                let s = embeddedLocation(nested)
                if !s.isEmpty { return s }
            }
        }
        return ""
    }

    // MARK: Meta tags and page text (for the AI fallback, or just a title)

    static func metaTags(html: String) -> [String: String] {
        var out: [String: String] = [:]
        for tag in matches(of: "<meta\\b[^>]*>", in: html) {
            let attrs = attributes(of: tag)
            guard let key = attrs["property"] ?? attrs["name"], let content = attrs["content"] else { continue }
            out[key.lowercased()] = decodeEntities(content)
        }
        return out
    }

    /// Visible text, without scripts and styles, cut to `limit` characters.
    static func pageText(html: String, limit: Int = 6000) -> String {
        var text = html
        for tag in ["script", "style", "noscript", "svg"] {
            text = text.replacingOccurrences(of: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>", with: " ",
                                             options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = decodeEntities(text)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(limit))
    }

    // MARK: Helpers

    static func date(_ value: Any?) -> Date? {
        if let n = value as? Double, n > 1_000_000_000 {
            return Date(timeIntervalSince1970: n > 10_000_000_000 ? n / 1000 : n)
        }
        guard let s = value as? String, s.count >= 16 else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return d }
        // "2026-10-10T19:00" with no zone: read it as local time.
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            local.dateFormat = format
            if let d = local.date(from: s) { return d }
        }
        return nil
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        let named = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&apos;": "'",
                     "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&#x2F;": "/"]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        for m in matches(of: "&#(x?)([0-9a-fA-F]+);", in: out) {
            let hex = m.hasPrefix("&#x") || m.hasPrefix("&#X")
            let digits = m.dropFirst(hex ? 3 : 2).dropLast()
            if let code = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                out = out.replacingOccurrences(of: m, with: String(Character(scalar)))
            }
        }
        return out
    }

    private static func scriptBodies(in html: String, matching type: String) -> [String] {
        groups(of: "<script\\b[^>]*type=[\"']\(type)[\"'][^>]*>([\\s\\S]*?)</script>", in: html)
    }

    private static func scriptBodies(in html: String, id: String) -> [String] {
        groups(of: "<script\\b[^>]*id=[\"']\(id)[\"'][^>]*>([\\s\\S]*?)</script>", in: html)
    }

    private static func attributes(of tag: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: "([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*=\\s*(\"([^\"]*)\"|'([^']*)')") else { return [:] }
        var out: [String: String] = [:]
        let ns = tag as NSString
        for m in regex.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: m.range(at: 1)).lowercased()
            let valueRange = m.range(at: 3).location != NSNotFound ? m.range(at: 3) : m.range(at: 4)
            out[key] = valueRange.location != NSNotFound ? ns.substring(with: valueRange) : ""
        }
        return out
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private static func groups(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

enum EventImportError: LocalizedError {
    case badLink
    case notAnEvent(title: String?)

    var errorDescription: String? {
        switch self {
        case .badLink: return "That doesn't look like a link."
        case .notAnEvent: return "Couldn't find a date and time on that page."
        }
    }
}

enum EventImporter {
    static let eventHosts = ["partiful.com", "lu.ma", "luma.com", "eventbrite.com", "posh.vip", "dice.fm", "withfriends.co"]

    static func host(of link: String) -> String {
        (URL(string: link)?.host ?? "").lowercased().replacingOccurrences(of: "www.", with: "")
    }

    /// The link without tracking bits, for spotting an invite you already imported.
    static func canonical(_ link: String) -> String {
        guard var parts = URLComponents(string: link) else { return link }
        parts.query = nil
        parts.fragment = nil
        parts.host = parts.host?.lowercased().replacingOccurrences(of: "www.", with: "")
        var out = parts.string ?? link
        while out.hasSuffix("/") { out.removeLast() }
        return out
    }

    /// Links that open the event importer (everything else shared to Daily goes to the recipe importer).
    static func isEventLink(_ link: String) -> Bool {
        let h = host(of: link)
        return eventHosts.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    static func sourceName(for link: String) -> String {
        let h = host(of: link)
        if h.hasSuffix("partiful.com") { return "Partiful" }
        if h.hasSuffix("lu.ma") || h.hasSuffix("luma.com") { return "Luma" }
        if h.hasSuffix("eventbrite.com") { return "Eventbrite" }
        if h.isEmpty { return "the invite" }
        return h
    }

    /// The first link in some shared text (Partiful shares "You're invited to … https://partiful.com/e/…").
    static func firstLink(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true { return trimmed }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return detector.firstMatch(in: trimmed, options: [], range: range)?.url?.absoluteString
    }

    /// What the page says, best source first. Returns nil start only if nothing found a time.
    static func parse(html: String, link: String) -> ImportedEvent? {
        let fromLD = EventPageParser.jsonLD(html: html, link: link)
        if let e = fromLD, e.start != nil { return e }
        if let e = EventPageParser.embedded(html: html, link: link) {
            // Fill gaps from the structured data if it had them.
            var merged = e
            if let ld = fromLD {
                if merged.location.isEmpty { merged.location = ld.location }
                if merged.details.isEmpty { merged.details = ld.details }
                merged.host = ld.host
            }
            return merged
        }
        return fromLD
    }

    /// Fetches the invite and reads it. Falls back to AI when the page has no machine-readable time.
    static func load(_ link: String) async throws -> ImportedEvent {
        guard let url = URL(string: link), url.scheme?.hasPrefix("http") == true else { throw EventImportError.badLink }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)

        let parsed = parse(html: html, link: link)
        if let parsed, parsed.start != nil { return parsed }

        let meta = EventPageParser.metaTags(html: html)
        let title = parsed?.title ?? meta["og:title"] ?? meta["twitter:title"]
        guard Keychain.hasKey else { throw EventImportError.notAnEvent(title: title) }
        let text = EventPageParser.pageText(html: html)
        guard var event = try? await EventImportAI.extract(link: link, meta: meta, text: text), event.start != nil else {
            throw EventImportError.notAnEvent(title: title)
        }
        if event.details.isEmpty { event.details = parsed?.details ?? meta["og:description"] ?? "" }
        return event
    }
}

/// Last resort: let the AI read the page.
enum EventImportAI {
    private struct Reply: Decodable {
        var title: String
        var start: String?
        var end: String?
        var location: String?
        var host: String?
        var details: String?
    }

    static func prompt(link: String, meta: [String: String], text: String, now: Date = Date(),
                       timeZone: TimeZone = .current) -> String {
        let metaLines = ["og:title", "og:description", "description", "twitter:title", "twitter:description"]
            .compactMap { key in meta[key].map { key + ": " + $0 } }
            .joined(separator: "\n")
        return """
        This is an event invite page (\(EventImporter.sourceName(for: link))). Pull out the event.
        Give start and end as ISO 8601 with a UTC offset, e.g. 2026-10-10T19:00:00-07:00. \
        If the page shows a time without a zone, assume \(timeZone.identifier). \
        Today is \(now.formatted(date: .complete, time: .omitted)). Leave end out if it isn't shown. \
        Leave start out if the page has no date.
        Link: \(link)
        \(metaLines)

        Page text:
        \(text)
        """
    }

    static func extract(link: String, meta: [String: String], text: String) async throws -> ImportedEvent {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "Event name"],
                "start": ["type": "string", "description": "Start, ISO 8601 with offset"],
                "end": ["type": "string", "description": "End, ISO 8601 with offset"],
                "location": ["type": "string", "description": "Venue and address, or 'Online'"],
                "host": ["type": "string", "description": "Host name(s)"],
                "details": ["type": "string", "description": "Short description, under 400 characters"]
            ],
            "required": ["title"]
        ]
        let reply = try await AIClient.structured(prompt: prompt(link: link, meta: meta, text: text),
                                                  toolName: "event", toolDescription: "Report the event",
                                                  schema: schema, as: Reply.self, maxTokens: 1024)
        return ImportedEvent(title: reply.title, start: EventPageParser.date(reply.start),
                             end: EventPageParser.date(reply.end), location: reply.location ?? "",
                             details: reply.details ?? "", link: link, host: reply.host ?? "")
    }
}

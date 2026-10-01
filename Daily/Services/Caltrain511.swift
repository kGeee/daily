import Foundation

/// Live Caltrain departures from 511.org (free API key from https://511.org/open-data/token).
enum Caltrain511 {
    struct Station: Identifiable, Hashable {
        let name: String
        let stopIDs: [String]
        var id: String { name }
    }

    struct Departure: Identifiable {
        let id = UUID()
        let scheduled: Date
        let expected: Date?
        let line: String
        let destination: String

        var time: Date { expected ?? scheduled }
        /// Minutes late (positive) or early (negative), nil if no live estimate.
        var delayMinutes: Int? {
            guard let expected else { return nil }
            return Int((expected.timeIntervalSince(scheduled) / 60).rounded())
        }
    }

    enum Failure: LocalizedError {
        case noKey, noStation, server(String)
        var errorDescription: String? {
            switch self {
            case .noKey: return "Add a free 511.org key in Settings to see live trains."
            case .noStation: return "Pick your home station in Settings."
            case .server(let message): return message
            }
        }
    }

    private static func get(_ path: String, query: [URLQueryItem]) async throws -> Any {
        guard let key = Keychain.read(Keychain.fiveOneOne), !key.isEmpty else { throw Failure.noKey }
        var components = URLComponents(string: "https://api.511.org/transit/" + path)
        components?.queryItems = [URLQueryItem(name: "api_key", value: key),
                                  URLQueryItem(name: "format", value: "json")] + query
        guard let url = components?.url else { throw Failure.server("Bad request.") }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Failure.server(http.statusCode == 401 ? "511 didn't accept the key." : "511 returned an error (\(http.statusCode)).")
        }
        // 511 responses start with a byte-order mark.
        var body = data
        if body.starts(with: [0xEF, 0xBB, 0xBF]) { body = body.dropFirst(3) }
        return try JSONSerialization.jsonObject(with: body)
    }

    /// All Caltrain stations, each with its stop IDs (one per direction).
    static func stations() async throws -> [Station] {
        let json = try await get("stops", query: [URLQueryItem(name: "operator_id", value: "CT")])
        let points = (((json as? [String: Any])?["Contents"] as? [String: Any])?["dataObjects"] as? [String: Any])?["ScheduledStopPoint"]
        let list = (points as? [[String: Any]]) ?? []

        var grouped: [String: [String]] = [:]
        for point in list {
            guard let id = point["id"] as? String, let rawName = point["Name"] as? String else { continue }
            let name = cleanName(rawName)
            grouped[name, default: []].append(id)
        }
        return grouped.map { Station(name: $0.key, stopIDs: $0.value.sorted()) }.sorted { $0.name < $1.name }
    }

    private static func cleanName(_ raw: String) -> String {
        var name = raw
        for word in [" Caltrain Station", " Caltrain", " Station", " Northbound", " Southbound", " NB", " SB"] {
            name = name.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// Upcoming departures at a station going one way ("N" or "S").
    static func departures(stopIDs: [String], direction: String) async throws -> [Departure] {
        guard !stopIDs.isEmpty else { throw Failure.noStation }
        var result: [Departure] = []
        for stop in stopIDs {
            let json = try await get("StopMonitoring", query: [URLQueryItem(name: "agency", value: "CT"),
                                                               URLQueryItem(name: "stopCode", value: stop)])
            let delivery = ((json as? [String: Any])?["ServiceDelivery"] as? [String: Any])?["StopMonitoringDelivery"]
            let deliveries: [[String: Any]] = (delivery as? [[String: Any]]) ?? [(delivery as? [String: Any]) ?? [:]]
            for d in deliveries {
                for visit in (d["MonitoredStopVisit"] as? [[String: Any]]) ?? [] {
                    guard let journey = visit["MonitoredVehicleJourney"] as? [String: Any] else { continue }
                    let dir = (journey["DirectionRef"] as? String ?? "").uppercased()
                    guard dir.hasPrefix(direction.uppercased()) else { continue }
                    let call = journey["MonitoredCall"] as? [String: Any] ?? [:]
                    guard let aimed = parseDate(call["AimedDepartureTime"] as? String ?? call["AimedArrivalTime"] as? String) else { continue }
                    let expected = parseDate(call["ExpectedDepartureTime"] as? String ?? call["ExpectedArrivalTime"] as? String)
                    result.append(Departure(scheduled: aimed, expected: expected,
                                            line: journey["PublishedLineName"] as? String ?? journey["LineRef"] as? String ?? "",
                                            destination: journey["DestinationName"] as? String ?? ""))
                }
            }
        }
        return result.filter { $0.time > Date().addingTimeInterval(-60) }.sorted { $0.time < $1.time }
    }

    private static func parseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}

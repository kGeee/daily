import Foundation
import MapKit

/// A place found by searching (Apple Maps, optionally with Yelp details).
struct PlaceResult: Identifiable, Hashable {
    struct Yelp: Hashable {
        var id: String
        var rating: Double
        var reviews: Int
        var url: String
    }

    var id = UUID()
    var name: String
    var address: String = ""
    var latitude: Double? = nil
    var longitude: Double? = nil
    var cuisine: String = ""
    var price: String = ""
    var phone: String = ""
    var website: String = ""
    var yelp: Yelp? = nil
}

/// Finding restaurants. Apple Maps is free and needs nothing set up; Yelp ratings show up
/// too if you add a Yelp API key in Settings (Yelp charges for its API).
enum PlaceSearch {
    static let yelpAccount = "yelpKey"

    static var hasYelpKey: Bool { !(Keychain.read(yelpAccount) ?? "").isEmpty }

    /// Around the places you've saved, or the Bay Area to start.
    static func searchRegion(near restaurants: [Restaurant]) -> MKCoordinateRegion {
        let points = restaurants.compactMap { r -> CLLocationCoordinate2D? in
            guard let lat = r.latitude, let lng = r.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        guard !points.isEmpty else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.55, longitude: -122.2),
                                      span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0))
        }
        let lats = points.map(\.latitude), lngs = points.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lngs.min()! + lngs.max()!) / 2)
        return MKCoordinateRegion(center: center,
                                  span: MKCoordinateSpan(latitudeDelta: max(lats.max()! - lats.min()!, 0.2) * 1.5,
                                                         longitudeDelta: max(lngs.max()! - lngs.min()!, 0.2) * 1.5))
    }

    // MARK: Apple Maps

    static func appleMaps(_ query: String, region: MKCoordinateRegion) async throws -> [PlaceResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket
        ])
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map { item in
            PlaceResult(name: item.name ?? query,
                        address: item.placemark.title ?? "",
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude,
                        cuisine: categoryName(item.pointOfInterestCategory),
                        phone: item.phoneNumber ?? "",
                        website: item.url?.absoluteString ?? "")
        }
    }

    private static func categoryName(_ category: MKPointOfInterestCategory?) -> String {
        switch category {
        case .some(.cafe): return "Café"
        case .some(.bakery): return "Bakery"
        case .some(.brewery): return "Brewery"
        case .some(.winery): return "Winery"
        case .some(.foodMarket): return "Market"
        default: return ""
        }
    }

    // MARK: Yelp

    enum YelpError: LocalizedError {
        case noKey, http(Int)
        var errorDescription: String? {
            switch self {
            case .noKey: return "Add a Yelp API key in Settings to see Yelp ratings."
            case .http(let code): return code == 401 ? "Yelp didn't accept the API key." : "Yelp returned an error (\(code))."
            }
        }
    }

    static func yelp(_ term: String, latitude: Double, longitude: Double, limit: Int = 15) async throws -> [PlaceResult] {
        guard let key = Keychain.read(yelpAccount), !key.isEmpty else { throw YelpError.noKey }
        var components = URLComponents(string: "https://api.yelp.com/v3/businesses/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "categories", value: "restaurants,food"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw YelpError.http(http.statusCode) }
        return try parseYelp(data)
    }

    /// Yelp details for a place picked from Apple Maps (closest name match nearby).
    static func yelpMatch(for place: PlaceResult) async -> PlaceResult.Yelp? {
        guard hasYelpKey, let lat = place.latitude, let lng = place.longitude,
              let results = try? await yelp(place.name, latitude: lat, longitude: lng, limit: 5) else { return nil }
        let wanted = normalized(place.name)
        let match = results.first { normalized($0.name) == wanted }
            ?? results.first { normalized($0.name).contains(wanted) || wanted.contains(normalized($0.name)) }
        return match?.yelp
    }

    static func normalized(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private struct YelpResponse: Decodable {
        struct Business: Decodable {
            struct Category: Decodable { let title: String }
            struct Coordinates: Decodable { let latitude: Double?; let longitude: Double? }
            struct Location: Decodable { let display_address: [String]? }
            let id: String
            let name: String
            let rating: Double?
            let review_count: Int?
            let price: String?
            let url: String?
            let display_phone: String?
            let categories: [Category]?
            let coordinates: Coordinates?
            let location: Location?
        }
        let businesses: [Business]
    }

    static func parseYelp(_ data: Data) throws -> [PlaceResult] {
        let response = try JSONDecoder().decode(YelpResponse.self, from: data)
        return response.businesses.map { b in
            PlaceResult(name: b.name,
                        address: (b.location?.display_address ?? []).joined(separator: ", "),
                        latitude: b.coordinates?.latitude,
                        longitude: b.coordinates?.longitude,
                        cuisine: b.categories?.first?.title ?? "",
                        price: b.price ?? "",
                        phone: b.display_phone ?? "",
                        yelp: PlaceResult.Yelp(id: b.id, rating: b.rating ?? 0, reviews: b.review_count ?? 0,
                                               url: b.url ?? ""))
        }
    }
}

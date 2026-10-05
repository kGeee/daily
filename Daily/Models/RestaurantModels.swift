import SwiftUI
import SwiftData

/// How a place was, the first cut before ranking it against others.
enum RestaurantFeeling: String, CaseIterable, Identifiable {
    case loved, fine, disliked
    var id: String { rawValue }

    var title: String {
        switch self {
        case .loved: return "I liked it"
        case .fine: return "It was fine"
        case .disliked: return "I didn't like it"
        }
    }

    var symbol: String {
        switch self {
        case .loved: return "heart.fill"
        case .fine: return "hand.thumbsup.fill"
        case .disliked: return "hand.thumbsdown.fill"
        }
    }

    var color: Color {
        switch self {
        case .loved: return Palette.food
        case .fine: return Palette.gym
        case .disliked: return Palette.danger
        }
    }

    /// Scores in this group fall in this range (best of the group gets the top).
    var scoreRange: ClosedRange<Double> {
        switch self {
        case .loved: return 6.7...10
        case .fine: return 3.4...6.7
        case .disliked: return 0...3.3
        }
    }
}

/// A place you've eaten at (or want to try). Visits are the "Ate out" meals linked to it.
@Model
final class Restaurant {
    var id: UUID = UUID()
    var name: String = ""
    var address: String = ""
    var latitude: Double? = nil
    var longitude: Double? = nil
    var cuisine: String = ""
    var price: String = ""
    var phone: String = ""
    var website: String = ""
    var yelpID: String = ""
    var yelpRating: Double? = nil
    var yelpReviews: Int? = nil
    var yelpURL: String = ""
    var googlePlaceID: String = ""
    var googleRating: Double? = nil
    var googleReviews: Int? = nil
    var googleURL: String = ""
    /// "" until you've rated it.
    var feelingRaw: String = ""
    /// 0 = your favorite within its feeling group.
    var rank: Int = 0
    var notes: String = ""
    var wantToTry: Bool = false
    var createdAt: Date = Date()

    init(name: String, address: String = "", latitude: Double? = nil, longitude: Double? = nil,
         cuisine: String = "", price: String = "", phone: String = "", website: String = "",
         wantToTry: Bool = false) {
        self.id = UUID()
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.cuisine = cuisine
        self.price = price
        self.phone = phone
        self.website = website
        self.yelpID = ""
        self.yelpRating = nil
        self.yelpReviews = nil
        self.yelpURL = ""
        self.feelingRaw = ""
        self.rank = 0
        self.notes = ""
        self.wantToTry = wantToTry
        self.createdAt = .now
    }

    var feeling: RestaurantFeeling? { RestaurantFeeling(rawValue: feelingRaw) }
    var isRanked: Bool { feeling != nil }

    var subtitle: String {
        [cuisine, shortAddress, price].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The first part of the address (street or neighborhood).
    var shortAddress: String {
        address.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    func apply(_ place: PlaceResult) {
        if !place.address.isEmpty { address = place.address }
        if let lat = place.latitude, let lng = place.longitude { latitude = lat; longitude = lng }
        if !place.cuisine.isEmpty { cuisine = place.cuisine }
        if !place.price.isEmpty { price = place.price }
        if !place.phone.isEmpty { phone = place.phone }
        if !place.website.isEmpty { website = place.website }
        if let yelp = place.yelp {
            yelpID = yelp.id
            yelpRating = yelp.rating
            yelpReviews = yelp.reviews
            yelpURL = yelp.url
        }
        if let google = place.google {
            googlePlaceID = google.id
            googleRating = google.rating
            googleReviews = google.reviews
            googleURL = google.url
        }
    }
}

/// Beli-style ranking: you pick a feeling, then compare against places in that group
/// (a binary search) to find where the new one fits. Scores come from the position.
enum RestaurantRanking {
    /// Score for the place at `position` (0 = best) in a group of `count`.
    static func score(position: Int, count: Int, feeling: RestaurantFeeling) -> Double {
        let range = feeling.scoreRange
        guard count > 1 else { return range.upperBound }
        let step = (range.upperBound - range.lowerBound) / Double(count)
        let raw = range.upperBound - step * Double(min(max(position, 0), count - 1))
        return (raw * 10).rounded() / 10
    }

    /// Scores for every ranked place.
    static func scores(_ restaurants: [Restaurant]) -> [UUID: Double] {
        var result: [UUID: Double] = [:]
        for feeling in RestaurantFeeling.allCases {
            let group = ordered(restaurants, feeling: feeling)
            for (i, r) in group.enumerated() {
                result[r.id] = score(position: i, count: group.count, feeling: feeling)
            }
        }
        return result
    }

    static func ordered(_ restaurants: [Restaurant], feeling: RestaurantFeeling) -> [Restaurant] {
        restaurants.filter { $0.feeling == feeling }
            .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.createdAt < $1.createdAt }
    }

    /// Everything you've ranked, best first.
    static func list(_ restaurants: [Restaurant]) -> [Restaurant] {
        RestaurantFeeling.allCases.flatMap { ordered(restaurants, feeling: $0) }
    }

    /// Where a new place goes among `count` others, found by asking "which was better?".
    struct Insertion: Equatable {
        var low: Int
        var high: Int

        init(count: Int) {
            low = 0
            high = count
        }

        var isDone: Bool { low >= high }
        /// Index of the place to compare against next.
        var middle: Int { (low + high) / 2 }
        var position: Int { low }

        mutating func answer(newIsBetter: Bool) {
            guard !isDone else { return }
            if newIsBetter { high = middle } else { low = middle + 1 }
        }

        /// "Too close to call": put it right above the one being compared.
        mutating func tie() {
            guard !isDone else { return }
            low = middle
            high = middle
        }
    }

    /// Puts `restaurant` into its feeling group at `position`, renumbering the group.
    static func insert(_ restaurant: Restaurant, feeling: RestaurantFeeling, at position: Int, among all: [Restaurant]) {
        var group = ordered(all.filter { $0.id != restaurant.id }, feeling: feeling)
        group.insert(restaurant, at: min(max(position, 0), group.count))
        restaurant.feelingRaw = feeling.rawValue
        restaurant.wantToTry = false
        for (i, r) in group.enumerated() { r.rank = i }
    }

    /// Takes a place out of its group (before ranking it again), closing the gap.
    static func remove(_ restaurant: Restaurant, among all: [Restaurant]) {
        guard let feeling = restaurant.feeling else { return }
        let group = ordered(all.filter { $0.id != restaurant.id }, feeling: feeling)
        for (i, r) in group.enumerated() { r.rank = i }
        restaurant.feelingRaw = ""
        restaurant.rank = 0
    }
}

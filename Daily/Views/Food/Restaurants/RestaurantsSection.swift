import SwiftUI
import SwiftData
import MapKit

extension MealSlot {
    /// The meal you'd most likely be eating at this time.
    static func guess(for date: Date) -> MealSlot {
        let minutes = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
        switch minutes {
        case ..<(10 * 60 + 30): return .breakfast
        case ..<(15 * 60): return .lunch
        case ..<(21 * 60 + 30): return .dinner
        default: return .snack
        }
    }
}

/// Your score for a place, Beli style.
struct ScoreBadge: View {
    let score: Double?
    let feeling: RestaurantFeeling?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.card)
            Circle()
                .strokeBorder(feeling?.color ?? Palette.idle, lineWidth: size > 50 ? 4 : 2.5)
            if let score {
                Text(String(format: "%.1f", score))
                    .font(.system(size: size * 0.34, weight: .heavy).monospacedDigit())
                    .foregroundStyle(feeling?.color ?? Palette.muted)
            } else {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(score.map { "Score \(String(format: "%.1f", $0))" } ?? "Not ranked")
    }
}

/// Food → Restaurants: a personal, ranked list of where you've eaten, a map, and places to try.
struct RestaurantsSection: View {
    enum ListMode: String, CaseIterable { case ranked = "My list", map = "Map", want = "Want to try" }
    enum SearchMode: String, Identifiable { case ate, want; var id: String { rawValue } }

    @Environment(\.modelContext) private var context
    @Query(sort: \Restaurant.createdAt) private var restaurants: [Restaurant]
    @Query(sort: \FoodEntry.date, order: .reverse) private var entries: [FoodEntry]

    @State private var listMode: ListMode = .ranked
    @State private var searchMode: SearchMode?
    @State private var pendingRank: Restaurant?
    @State private var ranking: Restaurant?
    @State private var viewing: Restaurant?
    @State private var filter = ""

    private var scores: [UUID: Double] { RestaurantRanking.scores(restaurants) }

    private var visitCounts: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for e in entries { if let id = e.restaurantID { counts[id, default: 0] += 1 } }
        return counts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statsCard
            HStack(spacing: 10) {
                addButton("I ate somewhere", symbol: "fork.knife", filled: true) { searchMode = .ate }
                addButton("Want to try", symbol: "bookmark", filled: false) { searchMode = .want }
            }
            PillSegment(ListMode.allCases, selection: $listMode) { $0.rawValue }
            switch listMode {
            case .ranked: rankedList
            case .map: mapCard
            case .want: wantList
            }
        }
        .animation(.snappy(duration: 0.3), value: listMode)
        .sheet(item: $searchMode, onDismiss: {
            if let next = pendingRank {
                pendingRank = nil
                ranking = next
            }
        }) { mode in
            RestaurantSearchSheet(title: mode == .ate ? "Where did you eat?" : "Save a place to try") { place in
                pick(place, mode: mode)
            }
        }
        .sheet(item: $ranking) { r in
            RankRestaurantSheet(restaurant: r, offerLog: true)
        }
        .sheet(item: $viewing) { r in
            RestaurantDetailSheet(restaurant: r)
        }
    }

    // MARK: Header

    private var statsCard: some View {
        let ranked = restaurants.filter(\.isRanked)
        let cal = Calendar.current
        let thisMonth = entries.filter { $0.source == .out && cal.isDate($0.date, equalTo: .now, toGranularity: .month) }
        let favorite = RestaurantRanking.list(restaurants).first
        return HStack(spacing: 0) {
            stat("\(ranked.count)", "places ranked")
            Rectangle().fill(Palette.line).frame(width: 1, height: 36)
            stat("\(thisMonth.count)", "meals out this month")
            Rectangle().fill(Palette.line).frame(width: 1, height: 36)
            VStack(spacing: 2) {
                Text(favorite?.name ?? "—")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("your #1")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
        }
        .padding(.vertical, 16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func addButton(_ title: String, symbol: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(filled ? Palette.onAccent : Palette.foodText)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(filled ? Palette.food : Palette.foodTint,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Lists

    private var filtered: [Restaurant] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return restaurants }
        return restaurants.filter { ($0.name + " " + $0.cuisine + " " + $0.address).lowercased().contains(q) }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.faint)
            TextField("Search your places", text: $filter)
                .submitLabel(.search)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Palette.card, in: Capsule())
    }

    @ViewBuilder
    private var rankedList: some View {
        let list = RestaurantRanking.list(filtered)
        let unranked = filtered.filter { !$0.isRanked && !$0.wantToTry }
        let scoreMap = self.scores
        let visits = visitCounts
        if restaurants.count > 6 { searchField }
        if list.isEmpty && unranked.isEmpty {
            emptyCard("Your list starts with one place",
                      "Tap \"I ate somewhere\" after a meal out. Rate it, compare it with a couple of others, and it lands in the right spot.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, r in
                    row(r, rank: index + 1, score: scoreMap[r.id], visits: visits[r.id] ?? 0)
                    if index < list.count - 1 { Rectangle().fill(Palette.line).frame(height: 1).padding(.leading, 52) }
                }
            }
            .padding(.horizontal, 14)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            if !unranked.isEmpty {
                SectionLabel(text: "Not ranked yet").padding(.top, 4)
                VStack(spacing: 0) {
                    ForEach(unranked) { r in
                        HStack(spacing: 12) {
                            Button { viewing = r } label: {
                                rowLabel(r, rank: nil, score: nil, visits: visits[r.id] ?? 0)
                            }
                            .buttonStyle(.plain)
                            Button("Rank") { ranking = r }
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(Palette.onAccent)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(Palette.food, in: Capsule())
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private func row(_ r: Restaurant, rank: Int?, score: Double?, visits: Int) -> some View {
        Button {
            viewing = r
        } label: {
            rowLabel(r, rank: rank, score: score, visits: visits)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rank again", systemImage: "arrow.up.arrow.down") {
                RestaurantRanking.remove(r, among: restaurants)
                ranking = r
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                RestaurantRanking.remove(r, among: restaurants)
                context.delete(r)
            }
        }
    }

    private func rowLabel(_ r: Restaurant, rank: Int?, score: Double?, visits: Int) -> some View {
        HStack(spacing: 12) {
            Text(rank.map { "\($0)" } ?? "–")
                .font(.subheadline.weight(.heavy).monospacedDigit())
                .foregroundStyle(Palette.faint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text([r.subtitle, visits > 0 ? "\(visits) visit\(visits == 1 ? "" : "s")" : ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let rating = r.yelpRating ?? r.googleRating, rating > 0 {
                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.gymText)
                    .labelStyle(.titleAndIcon)
            }
            ScoreBadge(score: score, feeling: r.feeling, size: 40)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var wantList: some View {
        let want = filtered.filter(\.wantToTry)
        if want.isEmpty {
            emptyCard("Nothing saved yet", "Save places you hear about so they're here when you're hungry.")
        } else {
            VStack(spacing: 0) {
                ForEach(want) { r in
                    HStack(spacing: 12) {
                        Button { viewing = r } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "bookmark.fill")
                                    .foregroundStyle(Palette.food)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.name).font(.subheadline.weight(.bold)).foregroundStyle(Palette.ink)
                                    Text(r.subtitle).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                                }
                                Spacer(minLength: 6)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button("Been") { ranking = r }
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Palette.foodText)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Palette.foodTint, in: Capsule())
                            .buttonStyle(.plain)
                    }
                    .padding(.vertical, 12)
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { context.delete(r) }
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var mapCard: some View {
        let scoreMap = self.scores
        let located = restaurants.filter { $0.latitude != nil && $0.longitude != nil && ($0.isRanked || $0.wantToTry) }
        return Map(initialPosition: .region(PlaceSearch.searchRegion(near: located))) {
            ForEach(located) { r in
                Annotation(r.name, coordinate: CLLocationCoordinate2D(latitude: r.latitude ?? 0, longitude: r.longitude ?? 0)) {
                    Button {
                        viewing = r
                    } label: {
                        ScoreBadge(score: scoreMap[r.id], feeling: r.feeling, size: 34)
                            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 440)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 12) {
                legend(Palette.food, "Liked")
                legend(Palette.gym, "Fine")
                legend(Palette.danger, "Didn't like")
                legend(Palette.idle, "Want to try")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Palette.card.opacity(0.92), in: Capsule())
            .padding(12)
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().strokeBorder(color, lineWidth: 2).frame(width: 10, height: 10)
            Text(text)
        }
    }

    private func emptyCard(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(Palette.ink)
            Text(text).font(.subheadline).foregroundStyle(Palette.muted)
        }
        .card()
    }

    // MARK: Adding

    private func pick(_ place: PlaceResult, mode: SearchMode) {
        let restaurant = RestaurantStore.findOrCreate(place, in: restaurants, context: context)
        if mode == .want && !restaurant.isRanked {
            restaurant.wantToTry = true
        }
        if mode == .ate { pendingRank = restaurant }
    }
}

/// Matching search results to places you've already saved.
enum RestaurantStore {
    @MainActor
    static func findOrCreate(_ place: PlaceResult, in restaurants: [Restaurant], context: ModelContext) -> Restaurant {
        if let existing = match(place, in: restaurants) {
            existing.apply(place)
            return existing
        }
        let r = Restaurant(name: place.name)
        r.apply(place)
        context.insert(r)
        if place.yelp == nil {
            Task {
                if let yelp = await PlaceSearch.yelpMatch(for: place) {
                    r.yelpID = yelp.id
                    r.yelpRating = yelp.rating
                    r.yelpReviews = yelp.reviews
                    r.yelpURL = yelp.url
                }
            }
        }
        return r
    }

    /// Same name, and close by if both have a location.
    static func match(_ place: PlaceResult, in restaurants: [Restaurant]) -> Restaurant? {
        let name = PlaceSearch.normalized(place.name)
        return restaurants.first { r in
            guard PlaceSearch.normalized(r.name) == name else { return false }
            guard let a = r.latitude, let b = r.longitude, let c = place.latitude, let d = place.longitude else { return true }
            return abs(a - c) < 0.005 && abs(b - d) < 0.005
        }
    }
}

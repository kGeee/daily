import SwiftUI
import SwiftData
import MapKit

// MARK: - Search

/// Find a place with Apple Maps (and Yelp, if you added a key).
struct RestaurantSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var restaurants: [Restaurant]

    let title: String
    let onPick: (PlaceResult) -> Void

    @State private var query = ""
    @State private var results: [PlaceResult] = []
    @State private var yelpResults: [PlaceResult] = []
    @State private var loading = false
    @State private var message: String?
    @FocusState private var focused: Bool
    @AppStorage(MapsApp.searchKey) private var provider = MapsApp.apple.rawValue

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.faint)
                    TextField("Restaurant, café, dish…", text: $query)
                        .focused($focused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                    if loading { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Palette.card, in: Capsule())
                .padding(.horizontal, 16)

                if PlaceSearch.hasGoogleKey {
                    PillSegment(MapsApp.allCases.map(\.rawValue), selection: $provider) {
                        $0 == MapsApp.google.rawValue ? "Google" : "Apple Maps"
                    }
                    .padding(.horizontal, 16)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !yelpResults.isEmpty {
                            group("Yelp", yelpResults)
                        }
                        if !results.isEmpty {
                            group(PlaceSearch.searchesGoogle ? "Google" : (yelpResults.isEmpty ? "Places" : "Apple Maps"), results)
                        }
                        if let message {
                            Text(message).font(.footnote).foregroundStyle(Palette.muted)
                        }
                        let typed = query.trimmingCharacters(in: .whitespaces)
                        if !typed.isEmpty && !loading {
                            Button {
                                choose(PlaceResult(name: typed))
                            } label: {
                                Label("Just add \"\(typed)\"", systemImage: "plus.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.foodText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.top, 8)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = true }
            .task(id: query + "|" + provider) {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await search()
            }
        }
    }

    private func group(_ label: String, _ places: [PlaceResult]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: label)
            VStack(spacing: 0) {
                ForEach(places) { place in
                    Button {
                        choose(place)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "fork.knife")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.food)
                                .frame(width: 34, height: 34)
                                .background(Palette.foodTint, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Text([place.cuisine, place.price, place.address].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(Palette.muted)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            if let rating = place.yelp?.rating ?? place.google?.rating, rating > 0 {
                                VStack(alignment: .trailing, spacing: 0) {
                                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Palette.gymText)
                                    Text("\(place.yelp?.reviews ?? place.google?.reviews ?? 0)")
                                        .font(.caption2)
                                        .foregroundStyle(Palette.faint)
                                }
                            }
                            if RestaurantStore.match(place, in: restaurants) != nil {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.food)
                            }
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func choose(_ place: PlaceResult) {
        onPick(place)
        dismiss()
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []
            yelpResults = []
            message = nil
            return
        }
        loading = true
        message = nil
        let region = PlaceSearch.searchRegion(near: restaurants)
        if PlaceSearch.searchesGoogle {
            do {
                results = try await PlaceSearch.google(q, region: region)
            } catch {
                message = error.localizedDescription
                results = (try? await PlaceSearch.appleMaps(q, region: region)) ?? []
            }
        } else {
            results = (try? await PlaceSearch.appleMaps(q, region: region)) ?? []
        }
        guard !Task.isCancelled else { return }
        if PlaceSearch.hasYelpKey {
            do {
                yelpResults = try await PlaceSearch.yelp(q, latitude: region.center.latitude, longitude: region.center.longitude)
            } catch {
                yelpResults = []
                message = error.localizedDescription
            }
        }
        if results.isEmpty && yelpResults.isEmpty && message == nil {
            message = "No matches nearby. You can still add it by name."
        }
        loading = false
    }
}

// MARK: - Ranking

/// "How was it?" then a few "which did you like more?" questions to find its spot.
struct RankRestaurantSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var restaurants: [Restaurant]

    let restaurant: Restaurant
    var offerLog: Bool = false

    @State private var feeling: RestaurantFeeling?
    @State private var group: [Restaurant] = []
    @State private var insertion = RestaurantRanking.Insertion(count: 0)
    @State private var finished = false
    @State private var logIt: Bool
    @State private var slot: MealSlot

    init(restaurant: Restaurant, offerLog: Bool = false) {
        self.restaurant = restaurant
        self.offerLog = offerLog
        _logIt = State(initialValue: offerLog)
        _slot = State(initialValue: MealSlot.guess(for: Date()))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 36, height: 36)
                        .background(Palette.card, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(16)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(restaurant.name)
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                    if !restaurant.subtitle.isEmpty {
                        Text(restaurant.subtitle).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                }
                if finished {
                    doneView
                } else if feeling == nil {
                    feelingView
                } else {
                    compareView
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .animation(.snappy(duration: 0.3), value: feeling)
            .animation(.snappy(duration: 0.3), value: insertion)
            .animation(.snappy(duration: 0.3), value: finished)
        }
        .background(Palette.bg.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: insertion)
        .sensoryFeedback(.success, trigger: finished)
    }

    private var feelingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How was it?")
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.ink)
            ForEach(RestaurantFeeling.allCases) { f in
                Button {
                    choose(f)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: f.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(f.color)
                            .frame(width: 44, height: 44)
                            .background(Palette.circle, in: Circle())
                        Text(f.title)
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .padding(12)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if offerLog {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $logIt) {
                        Text("Also log it as a meal today")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                    }
                    .tint(Palette.food)
                    if logIt {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(MealSlot.allCases) { s in
                                    ChoiceChip(title: s.title, symbol: s.symbol, isOn: slot == s, tint: Palette.food) { slot = s }
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var compareView: some View {
        if !insertion.isDone, insertion.middle < group.count {
            let other = group[insertion.middle]
            let remaining = Int(ceil(log2(Double(insertion.high - insertion.low + 1))))
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Which did you like more?")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(remaining <= 1 ? "Last one" : "About \(remaining) more")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                }
                compareCard(restaurant, highlight: true) { answer(newIsBetter: true) }
                Text("or")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.faint)
                    .frame(maxWidth: .infinity)
                compareCard(other, highlight: false) { answer(newIsBetter: false) }
                HStack {
                    Button("Too close to call") {
                        insertion.tie()
                        if insertion.isDone { finish() }
                    }
                    Spacer()
                    Button("Change rating") {
                        feeling = nil
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .padding(.top, 4)
            }
            .id(insertion.middle)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    private func compareCard(_ r: Restaurant, highlight: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(r.name)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Text(r.subtitle.isEmpty ? (highlight ? "Just now" : " ") : r.subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(highlight ? (feeling?.color ?? Palette.food) : Palette.line, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var doneView: some View {
        let score = RestaurantRanking.scores(restaurants)[restaurant.id]
        let list = RestaurantRanking.list(restaurants)
        let place = (list.firstIndex { $0.id == restaurant.id } ?? 0) + 1
        return VStack(spacing: 16) {
            ScoreBadge(score: score, feeling: feeling, size: 120)
                .padding(.top, 20)
            Text("#\(place) of \(list.count) places")
                .font(.title3.weight(.heavy))
                .foregroundStyle(Palette.ink)
            if logIt && offerLog {
                Label("Logged as today's \(slot.title.lowercased())", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.foodText)
            }
            DetailPrimaryButton(title: "Done", fill: Palette.food) { dismiss() }
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
    }

    private func choose(_ f: RestaurantFeeling) {
        feeling = f
        group = RestaurantRanking.ordered(restaurants.filter { $0.id != restaurant.id }, feeling: f)
        insertion = RestaurantRanking.Insertion(count: group.count)
        if insertion.isDone { finish() }
    }

    private func answer(newIsBetter: Bool) {
        insertion.answer(newIsBetter: newIsBetter)
        if insertion.isDone { finish() }
    }

    private func finish() {
        guard let feeling else { return }
        RestaurantRanking.insert(restaurant, feeling: feeling, at: insertion.position, among: restaurants)
        if offerLog && logIt {
            let entry = FoodEntry(slot: slot, name: restaurant.name, source: .out)
            entry.restaurantID = restaurant.id
            context.insert(entry)
        }
        finished = true
    }
}

// MARK: - Detail

struct RestaurantDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var restaurants: [Restaurant]
    @Query(sort: \FoodEntry.date, order: .reverse) private var entries: [FoodEntry]

    @Bindable var restaurant: Restaurant

    @State private var ranking: Restaurant?
    @State private var draft: LogDraft?
    @State private var confirmDelete = false

    private var visits: [FoodEntry] { entries.filter { $0.restaurantID == restaurant.id } }

    var body: some View {
        DetailSheetLayout {
            DetailHero(background: BlockCategory.food.hero, symbol: restaurant.wantToTry ? "bookmark.fill" : "fork.knife",
                       iconColor: Palette.food, timeText: restaurant.subtitle.isEmpty ? "Restaurant" : restaurant.subtitle,
                       onClose: { dismiss() }) {
                Text(restaurant.name)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        } content: {
            scoreCard
            if let lat = restaurant.latitude, let lng = restaurant.longitude {
                let spot = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                Map(initialPosition: .region(MKCoordinateRegion(center: spot, latitudinalMeters: 900, longitudinalMeters: 900))) {
                    Marker(restaurant.name, systemImage: "fork.knife", coordinate: spot)
                        .tint(Palette.food)
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .allowsHitTesting(false)
            }
            infoCard
            visitsCard
            DetailNotesCard(text: $restaurant.notes, placeholder: "What to order, who you went with, what to skip…")
            DetailDeleteButton(title: "Delete place") { confirmDelete = true }
        }
        .confirmationDialog("Delete \(restaurant.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                RestaurantRanking.remove(restaurant, among: restaurants)
                for visit in visits { visit.restaurantID = nil }
                context.delete(restaurant)
                dismiss()
            }
        } message: {
            Text("Your logged meals stay; they just won't be linked to this place.")
        }
        .sheet(item: $ranking) { r in
            RankRestaurantSheet(restaurant: r, offerLog: r.wantToTry)
        }
        .sheet(item: $draft) { d in
            LogMealSheet(draft: d)
        }
    }

    private static func rankLine(position: Int, count: Int, feeling: RestaurantFeeling) -> String {
        let group: String
        switch feeling {
        case .loved: group = "you liked"
        case .fine: group = "that were fine"
        case .disliked: group = "you didn't like"
        }
        return "#\(position) of \(count) " + group
    }

    private var scoreCard: some View {
        let score = RestaurantRanking.scores(restaurants)[restaurant.id]
        let feeling = restaurant.feeling
        let group = feeling.map { RestaurantRanking.ordered(restaurants, feeling: $0) } ?? []
        let position = (group.firstIndex { $0.id == restaurant.id } ?? 0) + 1
        return HStack(spacing: 16) {
            ScoreBadge(score: score, feeling: feeling, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                if let feeling {
                    Text(Self.rankLine(position: position, count: group.count, feeling: feeling))
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                } else {
                    Text(restaurant.wantToTry ? "On your want-to-try list" : "Not ranked yet")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                }
                if let rating = restaurant.yelpRating, rating > 0 {
                    Label("\(String(format: "%.1f", rating)) on Yelp · \(restaurant.yelpReviews ?? 0) reviews", systemImage: "star.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.gymText)
                }
                if let rating = restaurant.googleRating, rating > 0 {
                    Label("\(String(format: "%.1f", rating)) on Google · \(restaurant.googleReviews ?? 0) reviews", systemImage: "star.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.gymText)
                }
                Button(feeling == nil ? (restaurant.wantToTry ? "I've been – rank it" : "Rank it") : "Rank again") {
                    if feeling != nil { RestaurantRanking.remove(restaurant, among: restaurants) }
                    ranking = restaurant
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Palette.foodText)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var infoCard: some View {
        DetailCard {
            if !restaurant.address.isEmpty {
                Button {
                    openInMaps()
                } label: {
                    DetailRowLabel(symbol: "mappin.and.ellipse", tint: Palette.food, title: restaurant.address,
                                   value: MapsApp.current == .google ? "Google Maps" : "Maps")
                }
                .buttonStyle(.plain)
                DetailDivider()
            }
            if !restaurant.phone.isEmpty, let url = URL(string: "tel:" + restaurant.phone.filter { $0.isNumber || $0 == "+" }) {
                Button { openURL(url) } label: {
                    DetailRowLabel(symbol: "phone.fill", tint: Palette.food, title: restaurant.phone)
                }
                .buttonStyle(.plain)
                DetailDivider()
            }
            if let url = URL(string: restaurant.yelpURL), !restaurant.yelpURL.isEmpty {
                Button { openURL(url) } label: {
                    DetailRowLabel(symbol: "star.bubble.fill", tint: Palette.gym, title: "See it on Yelp")
                }
                .buttonStyle(.plain)
                DetailDivider()
            }
            if let url = URL(string: restaurant.website), !restaurant.website.isEmpty {
                Button { openURL(url) } label: {
                    DetailRowLabel(symbol: "safari.fill", tint: Palette.food, title: "Website")
                }
                .buttonStyle(.plain)
                DetailDivider()
            }
            HStack(spacing: 14) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Palette.food)
                    .frame(width: 30)
                TextField("Cuisine", text: $restaurant.cuisine)
                TextField("$$", text: $restaurant.price)
                    .frame(width: 50)
                    .multilineTextAlignment(.trailing)
            }
            .frame(minHeight: 58)
        }
    }

    private var visitsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: visits.isEmpty ? "Visits" : "Visits · \(visits.count)")
                Spacer()
                Button {
                    draft = LogDraft(slot: MealSlot.guess(for: Date()), source: .out, name: restaurant.name,
                                     restaurantID: restaurant.id)
                } label: {
                    Label("Log a visit", systemImage: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.onAccent)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Palette.food, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if visits.isEmpty {
                Text("No meals logged here yet.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
            let photos = visits.filter { $0.photo != nil }
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos.prefix(12)) { visit in
                            Button {
                                draft = LogDraft(slot: visit.slot, source: visit.source, name: visit.name, entry: visit,
                                                 restaurantID: restaurant.id)
                            } label: {
                                PhotoThumbnail(data: visit.photo!, maxPixel: 300)
                                    .frame(width: 88, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(alignment: .bottomLeading) {
                                        Text(visit.date.formatted(.dateTime.month(.abbreviated).day()))
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Palette.onAccent)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Palette.ink.opacity(0.55), in: Capsule())
                                            .padding(5)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            ForEach(visits.prefix(12)) { visit in
                Button {
                    draft = LogDraft(slot: visit.slot, source: visit.source, name: visit.name, entry: visit,
                                     restaurantID: restaurant.id)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(visit.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.muted)
                            Text(visit.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        if let cal = visit.calories {
                            Text("\(cal) cal").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func openInMaps() {
        if let url = MapsApp.url(for: MapsApp.current, name: restaurant.name, address: restaurant.address,
                                 latitude: restaurant.latitude, longitude: restaurant.longitude,
                                 googlePlaceID: restaurant.googlePlaceID) {
            openURL(url)
        }
    }
}

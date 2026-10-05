import SwiftUI
import SwiftData

/// Add or edit a photo check-in.
struct CheckInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let entry: JournalEntry?

    @State private var photo: Data?
    @State private var caption: String
    @State private var mood: Mood?
    @State private var date: Date
    @State private var confirmDelete = false

    init(entry: JournalEntry? = nil, photo: Data? = nil) {
        self.entry = entry
        _photo = State(initialValue: entry?.photo ?? photo)
        _caption = State(initialValue: entry?.caption ?? "")
        _mood = State(initialValue: entry?.mood)
        _date = State(initialValue: entry?.date ?? Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    photoArea
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "How's it going?")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Mood.allCases) { m in
                                    ChoiceChip(title: m.title, symbol: m.symbol, isOn: mood == m, tint: m.color) {
                                        withAnimation(.snappy) { mood = mood == m ? nil : m }
                                    }
                                }
                            }
                        }
                        Rectangle().fill(Palette.line).frame(height: 1)
                        TextField("A line about today (optional)", text: $caption, axis: .vertical)
                            .lineLimit(2...6)
                            .foregroundStyle(Palette.ink)
                    }
                    .padding(16)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    DatePicker("When", selection: $date)
                        .padding(.horizontal, 16)
                        .frame(height: 54)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    if entry != nil {
                        DetailDeleteButton(title: "Delete check-in") { confirmDelete = true }
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(entry == nil ? "Check-in · " + date.formatted(date: .omitted, time: .shortened) : "Check-in")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(photo == nil && caption.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this check-in?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let entry { context.delete(entry) }
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var photoArea: some View {
        if let photo {
            PhotoThumbnail(data: photo, maxPixel: 1400)
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Menu {
                        Button("Remove photo", systemImage: "trash", role: .destructive) {
                            withAnimation { self.photo = nil }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 36, height: 36)
                            .background(Palette.card.opacity(0.92), in: Circle())
                    }
                    .padding(12)
                }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Palette.focus)
                    .frame(width: 64, height: 64)
                    .background(Palette.focusTint, in: Circle())
                Text("Snap whatever's in front of you")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                PhotoSourceButtons(tint: Palette.focus) { data in
                    withAnimation(.snappy) { photo = data }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 260)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func save() {
        let text = caption.trimmingCharacters(in: .whitespaces)
        if let entry {
            entry.photo = photo
            entry.caption = text
            entry.moodRaw = mood?.rawValue ?? ""
            entry.date = date
        } else {
            context.insert(JournalEntry(date: date, photo: photo, caption: text, mood: mood))
        }
        dismiss()
    }
}

/// Today's prompt to check in, plus this week's photos.
struct CheckInCard: View {
    let entries: [JournalEntry]
    let meals: [FoodEntry]
    let now: Date
    var onOpenJournal: () -> Void
    var onPhoto: (Data) -> Void

    init(entries: [JournalEntry], meals: [FoodEntry], now: Date,
         onOpenJournal: @escaping () -> Void, onPhoto: @escaping (Data) -> Void) {
        self.entries = entries
        self.meals = meals
        self.now = now
        self.onOpenJournal = onOpenJournal
        self.onPhoto = onPhoto
    }

    private var weekItems: [JournalItem] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return JournalItem.days(entries: entries.filter { week.contains($0.date) },
                                meals: meals.filter { week.contains($0.date) })
            .flatMap(\.items).filter { $0.photo != nil }
    }

    var body: some View {
        let prompt = CheckIn.shouldPrompt(at: now, entries: entries)
        let photos = weekItems
        if prompt || !photos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if prompt {
                    HStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Palette.focus)
                            .frame(width: 44, height: 44)
                            .background(Palette.focusTint, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Midday check-in")
                                .font(.headline)
                                .foregroundStyle(Palette.ink)
                            Text("How's today going? Snap whatever's in front of you.")
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    PhotoSourceButtons(tint: Palette.focus, onPhoto: onPhoto)
                }
                if !photos.isEmpty {
                    if prompt { Rectangle().fill(Palette.line).frame(height: 1) }
                    Button(action: onOpenJournal) {
                        HStack {
                            SectionLabel(text: "This week")
                            Spacer()
                            Text("Journal")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Palette.commuteText)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Palette.commuteText)
                        }
                    }
                    .buttonStyle(.plain)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(photos.prefix(12)) { item in
                                if let data = item.photo {
                                    Button(action: onOpenJournal) {
                                        PhotoThumbnail(data: data, maxPixel: 200)
                                            .frame(width: 62, height: 62)
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                            .overlay(alignment: .bottomLeading) {
                                                Text(item.date.formatted(.dateTime.weekday(.abbreviated)))
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(Palette.onAccent)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(Palette.ink.opacity(0.55), in: Capsule())
                                                    .padding(4)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .card()
        }
    }
}

/// Every check-in and meal photo, by day.
struct JournalView: View {
    enum Layout: String, CaseIterable { case feed = "Feed", grid = "Grid" }

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @Query(sort: \FoodEntry.date, order: .reverse) private var meals: [FoodEntry]
    @Query private var restaurants: [Restaurant]

    @State private var layout: Layout = .feed
    @State private var editing: JournalEntry?
    @State private var newPhoto: PhotoDraft?
    @State private var editingMeal: LogDraft?
    @State private var showAdd = false

    struct PhotoDraft: Identifiable {
        let id = UUID()
        let data: Data?
    }

    var body: some View {
        let days = JournalItem.days(entries: entries, meals: meals)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .bottom) {
                        ScreenHeader(eyebrow: Date().formatted(.dateTime.month(.wide)), title: "Journal")
                        Spacer()
                        Button {
                            newPhoto = PhotoDraft(data: nil)
                        } label: {
                            Label("Check in", systemImage: "camera.fill")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Palette.onAccent)
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .background(Palette.focus, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    PillSegment(Layout.allCases, selection: $layout) { $0.rawValue }
                    if days.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No photos yet").font(.headline).foregroundStyle(Palette.ink)
                            Text("Check in around midday with a photo of how it's going. Meal photos show up here too.")
                                .font(.subheadline)
                                .foregroundStyle(Palette.muted)
                        }
                        .card()
                    } else if layout == .feed {
                        ForEach(days, id: \.day) { day in
                            Text(day.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                                .font(.headline.weight(.heavy))
                                .foregroundStyle(Palette.ink)
                                .padding(.top, 6)
                            ForEach(day.items) { item in
                                feedCard(item)
                            }
                        }
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                            ForEach(days.flatMap(\.items).filter { $0.photo != nil }) { item in
                                Button { open(item) } label: {
                                    PhotoThumbnail(data: item.photo!, maxPixel: 300)
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .background(Palette.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $editing) { e in CheckInSheet(entry: e) }
        .sheet(item: $newPhoto) { draft in CheckInSheet(photo: draft.data) }
        .sheet(item: $editingMeal) { d in LogMealSheet(draft: d) }
    }

    private func open(_ item: JournalItem) {
        switch item.kind {
        case .checkIn(let e): editing = e
        case .meal(let m):
            editingMeal = LogDraft(slot: m.slot, source: m.source, name: m.name, entry: m, restaurantID: m.restaurantID)
        }
    }

    private func feedCard(_ item: JournalItem) -> some View {
        Button { open(item) } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let data = item.photo {
                    PhotoThumbnail(data: data, maxPixel: 1000)
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.date.formatted(date: .omitted, time: .shortened))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Palette.muted)
                        tags(item)
                    }
                    if let text = text(item), !text.isEmpty {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tags(_ item: JournalItem) -> some View {
        switch item.kind {
        case .checkIn(let e):
            if let mood = e.mood {
                Label(mood.title, systemImage: mood.symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(mood.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Palette.card2, in: Capsule())
            }
        case .meal(let m):
            let place = m.restaurantID.flatMap { id in restaurants.first { $0.id == id }?.name }
            Label(place ?? m.slot.title, systemImage: "fork.knife")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Palette.foodText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Palette.foodTint, in: Capsule())
        }
    }

    private func text(_ item: JournalItem) -> String? {
        switch item.kind {
        case .checkIn(let e): return e.caption
        case .meal(let m): return m.name
        }
    }
}

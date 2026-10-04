import SwiftUI
import SwiftData

/// Reads a Partiful / Luma (or other) invite and opens it in the event editor, ready to add.
/// Importing the same invite again updates the event you already have.
struct ImportEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var events: [CustomEvent]
    let link: String
    var onSaved: (() -> Void)? = nil

    private enum Phase {
        case loading
        case loaded(ImportedEvent)
        case failed(message: String, title: String?)
    }

    @State private var phase: Phase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                loadingView
            case .loaded(let imported):
                EventEditor(event: existing, defaultDay: imported.start ?? Date(), imported: imported, onSaved: onSaved)
            case .failed(let message, let title):
                failedView(message: message, title: title)
            }
        }
        .task { await load() }
    }

    private var existing: CustomEvent? {
        let key = EventImporter.canonical(link)
        return events.first { !$0.link.isEmpty && EventImporter.canonical($0.link) == key }
    }

    private func load() async {
        guard case .loading = phase else { return }
        do {
            let imported = try await EventImporter.load(link)
            withAnimation(.snappy) { phase = .loaded(imported) }
        } catch let error as EventImportError {
            var title: String?
            if case .notAnEvent(let t) = error { title = t }
            let message = Keychain.hasKey
                ? "Couldn't find a date and time on that page. You can add it yourself."
                : "Couldn't find a date and time on that page. Add your Anthropic key in Settings and Daily can read invites like this one."
            withAnimation(.snappy) { phase = .failed(message: message, title: title) }
        } catch {
            withAnimation(.snappy) {
                phase = .failed(message: "Couldn't open the invite. Check your connection and try again.", title: nil)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(Palette.general)
            Text("Reading the invite…")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text(EventImporter.sourceName(for: link))
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg.ignoresSafeArea())
    }

    private func failedView(message: String, title: String?) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "ticket")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Palette.general)
            Text(title ?? "Couldn't read that invite")
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            DetailPrimaryButton(title: "Add it myself", symbol: "plus", fill: Palette.general) {
                let draft = ImportedEvent(title: title ?? "", start: nil, link: link)
                withAnimation(.snappy) { phase = .loaded(draft) }
            }
            Button("Cancel") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.muted)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg.ignoresSafeArea())
    }
}

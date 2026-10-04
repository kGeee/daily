import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// "Share → Daily" from Instagram, Safari, Partiful or Luma. Saves the link (and any text) for the app,
/// which opens the event importer (invites) or the recipe importer next time it's opened.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: SavedView())
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        Task {
            let (link, text) = await extract()
            if !link.isEmpty || !text.isEmpty {
                SharedStore.addPendingImport(link: link, text: text)
            }
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func extract() async -> (String, String) {
        var link = ""
        var text = ""
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            if let content = item.attributedContentText?.string, !content.isEmpty {
                text += (text.isEmpty ? "" : "\n") + content
            }
            for provider in item.attachments ?? [] {
                if link.isEmpty, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let value = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) {
                    if let url = value as? URL { link = url.absoluteString }
                    else if let string = value as? String { link = string }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil),
                          let string = value as? String {
                    if link.isEmpty, let found = Self.firstURL(in: string) {
                        link = found
                    }
                    if string != link {
                        text += (text.isEmpty ? "" : "\n") + string
                    }
                }
            }
        }
        return (link, text)
    }

    private static func firstURL(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.url?.absoluteString
    }
}

private struct SavedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color(red: 0x23 / 255, green: 0x74 / 255, blue: 0x4A / 255))
            Text("Saved to Daily")
                .font(.title3.weight(.bold))
            Text("Open Daily to finish importing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}

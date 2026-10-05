import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Small differences between iPhone and Mac, kept in one place so screens can stay shared.

#if canImport(UIKit)
typealias PlatformImage = UIImage
#else
typealias PlatformImage = NSImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

/// Keyboard kinds we use. On the Mac there's no on-screen keyboard, so these do nothing.
enum PlatformKeyboard {
    case numberPad, decimalPad, url
}

extension View {
    /// Small centered title on iPhone; the Mac has no large titles, so nothing changes.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformKeyboard(_ kind: PlatformKeyboard) -> some View {
        #if os(iOS)
        switch kind {
        case .numberPad: self.keyboardType(.numberPad)
        case .decimalPad: self.keyboardType(.decimalPad)
        case .url: self.keyboardType(.URL)
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func noAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    /// The spinning wheel on iPhone; a compact field on the Mac.
    @ViewBuilder
    func wheelDatePickerStyle() -> some View {
        #if os(iOS)
        self.datePickerStyle(.wheel)
        #else
        self.datePickerStyle(.stepperField)
        #endif
    }

    /// Swipeable pages on iPhone; on the Mac, plain tabs (use the arrows or tap to move on).
    @ViewBuilder
    func pagedTabViewStyle() -> some View {
        #if os(iOS)
        self.tabViewStyle(.page(indexDisplayMode: .never))
        #else
        self
        #endif
    }

    /// Full screen on iPhone; a large sheet on the Mac.
    @ViewBuilder
    func fullScreenSheet<Content: View>(isPresented: Binding<Bool>,
                                        @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented) {
            content().frame(minWidth: 640, minHeight: 640)
        }
        #endif
    }
}

enum Platform {
    static var isMac: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    /// Copies text to the clipboard.
    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    static func pasteboardString() -> String? {
        #if canImport(UIKit)
        return UIPasteboard.general.string
        #else
        return NSPasteboard.general.string(forType: .string)
        #endif
    }

    /// Keeps the screen awake (cooking mode). The Mac doesn't need it.
    static func keepScreenOn(_ on: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = on
        #endif
    }
}

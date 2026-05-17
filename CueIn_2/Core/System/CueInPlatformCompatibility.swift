import SwiftUI

enum CueInNavigationTitleDisplayMode {
    case inline
    case large
}

enum CueInToolbarPlacement {
    static var topBarLeading: ToolbarItemPlacement {
        #if os(macOS)
        return .navigation
        #else
        return .topBarLeading
        #endif
    }

    static var topBarTrailing: ToolbarItemPlacement {
        #if os(macOS)
        return .primaryAction
        #else
        return .topBarTrailing
        #endif
    }
}

enum CueInSearchPlacement {
    static var navigationBarDrawerAlways: SearchFieldPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .navigationBarDrawer(displayMode: .always)
        #endif
    }
}

extension View {
    @ViewBuilder
    func cueInNavigationBarTitleDisplayMode(_ displayMode: CueInNavigationTitleDisplayMode) -> some View {
        #if os(macOS)
        self
        #else
        switch displayMode {
        case .inline:
            self.navigationBarTitleDisplayMode(.inline)
        case .large:
            self.navigationBarTitleDisplayMode(.large)
        }
        #endif
    }

    @ViewBuilder
    func cueInNavigationToolbarMaterial() -> some View {
        #if os(macOS)
        self
        #else
        self
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #endif
    }

    @ViewBuilder
    func cueInNavigationToolbarChrome(isVisible: Bool) -> some View {
        #if os(macOS)
        self
        #else
        self
            .toolbarBackground(isVisible ? .visible : .hidden, for: .navigationBar)
            .toolbarBackground(isVisible ? Material.bar : Material.ultraThin, for: .navigationBar)
            .toolbarColorScheme(CueInThemePreference.current.colorScheme, for: .navigationBar)
        #endif
    }

    @ViewBuilder
    func cueInNavigationToolbarColorScheme() -> some View {
        #if os(macOS)
        self
        #else
        self.toolbarColorScheme(CueInThemePreference.current.colorScheme, for: .navigationBar)
        #endif
    }

    @ViewBuilder
    func cueInSentencesAutocapitalization() -> some View {
        #if os(macOS)
        self
        #else
        self.textInputAutocapitalization(.sentences)
        #endif
    }

    @ViewBuilder
    func cueInNoAutocapitalization() -> some View {
        #if os(macOS)
        self
        #else
        self.textInputAutocapitalization(.never)
        #endif
    }

    @ViewBuilder
    func cueInWheelPickerStyle() -> some View {
        #if os(macOS)
        self.pickerStyle(.menu)
        #else
        self.pickerStyle(.wheel)
        #endif
    }

    @ViewBuilder
    func cueInPageTabViewStyle() -> some View {
        #if os(macOS)
        self
        #else
        self.tabViewStyle(.page(indexDisplayMode: .never))
        #endif
    }
}

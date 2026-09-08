//
//  CrossPlatform.swift
//  Guardian
//
//  Small shims so the SwiftUI code compiles across the target's supported
//  platforms while remaining iPhone-first. iOS-only modifiers are wrapped here.
//

import SwiftUI

extension View {
    /// Inline navigation title on iOS; no-op elsewhere.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Full-screen cover on iOS; falls back to a sheet on platforms without it.
    @ViewBuilder
    func fullCover<Content: View>(isPresented: Binding<Bool>,
                                  @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }

    /// Phone-pad keyboard on iOS; no-op elsewhere.
    @ViewBuilder
    func phonePadKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.phonePad)
        #else
        self
        #endif
    }
}

extension ToolbarItemPlacement {
    /// Leading bar item that maps to a sensible placement per platform.
    static var guardianLeading: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .cancellationAction
        #endif
    }

    /// Trailing bar item that maps to a sensible placement per platform.
    static var guardianTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

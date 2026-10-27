import SwiftUI

extension View {
    /// A sheet over the Cards window, as `sheet(isPresented:content:)`
    /// presents it, whose `content` gets the tallest it can be to stay within
    /// the window, for what it holds to scroll beyond that.
    func sheetWithinWindow<Sheet: View>(
        isPresented: Binding<Bool>, @ViewBuilder content: @escaping (_ maximumHeight: CGFloat) -> Sheet
    ) -> some View {
        modifier(SheetWithinWindow(isPresented: isPresented, sheet: content))
    }

    /// Shows the scroll bar of a scroll view in such a sheet only while what
    /// it holds is taller than it is: with a mouse connected, macOS shows one
    /// on any scroll view.
    func scrollBarOnlyWhenItOverflows() -> some View {
        modifier(ScrollBarOnlyWhenItOverflows())
    }
}

/// What `scrollBarOnlyWhenItOverflows` does.
private struct ScrollBarOnlyWhenItOverflows: ViewModifier {
    /// Whether what the scroll view holds is taller than it is.
    @State private var overflows = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // A sheet's window is a whole number of points tall, which can
                // leave what scrolls half a point taller than its scroll view.
                geometry.contentSize.height - geometry.containerSize.height >= 1
            } action: { _, overflows in
                self.overflows = overflows
            }
            .scrollIndicators(overflows ? .automatic : .never)
    }
}

/// The sheet `sheetWithinWindow` presents, and the window's height it keeps
/// track of for it.
private struct SheetWithinWindow<Sheet: View>: ViewModifier {
    @Binding var isPresented: Bool
    let sheet: (_ maximumHeight: CGFloat) -> Sheet
    /// The height of the window under its toolbar, which the sheet stays
    /// within, once it's known.
    @State private var windowHeight: CGFloat?
    /// `maximumHeight` as it was when the sheet opened, which the sheet
    /// keeps: macOS keeps a sheet's window as tall as it opened, so the
    /// content keeps to that, even once the window's height is known.
    @State private var openingMaximumHeight: CGFloat?
    /// What the sheet leaves of the window's height under it: a margin over
    /// the window's bottom edge. macOS 26 draws a sheet as tall as its
    /// content, with no frame around it.
    private let bottomMargin: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                windowHeight = height
            }
            .sheet(isPresented: $isPresented) {
                let height = openingMaximumHeight ?? maximumHeight
                sheet(height)
                    // What the content was built with, not `maximumHeight`
                    // as it is once the sheet appears.
                    .onAppear {
                        openingMaximumHeight = height
                    }
                    .onDisappear {
                        openingMaximumHeight = nil
                    }
            }
    }

    /// The tallest the sheet's content gets: what the window has under its
    /// toolbar, or until that's known, as when the window opens with the
    /// sheet, the least it can have, less the margin, so that the sheet fits
    /// from the moment it opens.
    private var maximumHeight: CGFloat {
        (windowHeight ?? CardsWindow.minimumSize.height) - bottomMargin
    }
}

import AppKit
import FichaData
import SwiftUI

/// The image on a side of a card, as the review panel and the Cards window
/// show it: fitted to the width it's offered, never wider than the image
/// itself nor taller than `maximumHeight`, its height following its width, so
/// a panel or a column sizes it as it sizes text. When it couldn't be read,
/// it says so instead.
struct SideImage: View {
    /// The image, as a JPEG or a PNG, or why it couldn't be read, or nil
    /// while it isn't read.
    let image: Result<Data, EngineError>?
    /// The tallest it shows.
    var maximumHeight: CGFloat = .infinity

    var body: some View {
        switch image {
        case .success(let data):
            if let picture = NSImage(data: data), picture.size.width > 0, picture.size.height > 0 {
                FittedImage(size: picture.size, maximumHeight: maximumHeight) {
                    Image(nsImage: picture)
                        .resizable()
                        .clipShape(.rect(cornerRadius: 6))
                }
                .accessibilityElement()
                .accessibilityLabel(Text("Image", comment: "The accessibility label of an image on a card's side."))
            } else {
                unreadable(EngineError.notAnImage.localizedDescription)
            }
        case .failure(let error):
            unreadable(error.localizedDescription)
        case nil:
            EmptyView()
        }
    }

    /// That the image couldn't be shown, and why.
    private func unreadable(_ why: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't show this image.", comment: "In place of an image on a card's side that can't be read.")
                Text(why)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "photo.badge.exclamationmark")
        }
        .foregroundStyle(.secondary)
    }
}

/// Sizes a resizable image of `size` to the width it's offered, or less, so
/// it's never wider than `size` nor taller than `maximumHeight`, keeping its
/// proportions: its height follows its width, as a text's does, which the
/// review panel needs to fit a card without scrolling it (#215).
private struct FittedImage: Layout {
    let size: CGSize
    let maximumHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ratio = size.width / size.height
        let width = min(proposal.width ?? size.width, size.width, maximumHeight * ratio)
        return CGSize(width: width, height: width / ratio)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }
}

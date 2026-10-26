import AppKit
import FichaCore
import FichaData
import SwiftUI
import UniformTypeIdentifiers

/// Where a side of the card the user makes or edits takes its image, under the
/// side's text: an image dragged from Finder or a browser onto it, or pasted
/// with ⌘V once it has the focus, which a click or Tab gives it. With an
/// image, it shows it, with a button that removes it, as Delete does while it
/// has the focus, and a new image replaces it. The window decides whether
/// what came in is an image, and says so when it isn't.
struct ImageWell: View {
    /// The side's image, or nil for none.
    let image: ImageName?
    /// The images the window shows, the side's among them.
    let images: ShownImages
    /// Puts what was dragged or pasted on the side, as its image.
    let put: (DroppedImage) -> Void
    /// Removes the side's image.
    let remove: () -> Void
    /// Whether something is dragged over it.
    @State private var isTargeted = false
    /// Whether it has the focus, which it draws itself: macOS's focus ring
    /// keeps the size it had before an image came in.
    @FocusState private var isFocused: Bool

    var body: some View {
        // A stack, not a group, so the focus stays on one view when an image
        // comes in or goes: a group's modifiers go to each of its branches.
        ZStack {
            if let image {
                ZStack(alignment: .topTrailing) {
                    SideImage(image: images[image], maximumHeight: 120)
                        .overlay {
                            if isTargeted || isFocused {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(.tint, lineWidth: 3)
                            }
                        }
                    Button(action: remove) {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .accessibilityLabel(
                        Text("Remove Image", comment: "The button that removes the image on a side of a card.")
                    )
                    .help(
                        Text(
                            "Remove Image (⌫)",
                            comment: "The tooltip of the button that removes the image on a side of a card."))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label {
                    Text("Drop or paste an image", comment: "In the empty place for the image on a side of a card.")
                } icon: {
                    Image(systemName: "photo.badge.plus")
                }
                .font(.callout)
                .foregroundStyle(isTargeted || isFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(style: StrokeStyle(lineWidth: isFocused ? 2 : 1, dash: [4, 3]))
                        .foregroundStyle(isTargeted || isFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                }
                .contentShape(.rect)
            }
        }
        .focusable(interactions: .edit)
        .focused($isFocused)
        .focusEffectDisabled()
        .onPasteCommand(of: Self.imageTypes) { _ in
            take(from: .general)
        }
        .onDeleteCommand {
            if image != nil {
                remove()
            }
        }
        .onDrop(of: Self.imageTypes, isTargeted: $isTargeted) { _ in
            // The drag's own pasteboard, not the item providers SwiftUI hands
            // over: for an image a browser drags, those offer only the file
            // it promises, which can't be loaded (#229).
            take(from: NSPasteboard(name: .drag))
            return true
        }
    }

    /// What it takes: a file, as Finder drags or copies it, or an image's
    /// data, as a browser or the pasteboard holds it.
    private static let imageTypes: [UTType] = [.fileURL, .image]

    /// Puts the image in the first of `pasteboard`'s items that holds one on
    /// the side. What holds no image goes to the window as no data, which it
    /// refuses, saying so.
    private func take(from pasteboard: NSPasteboard) {
        let image = (pasteboard.pasteboardItems ?? []).lazy.compactMap { item in
            DroppedImage(pasteboardTypes: item.types.map(\.rawValue)) { item.data(forType: .init($0)) }
        }.first
        put(image ?? .data(Data()))
    }
}

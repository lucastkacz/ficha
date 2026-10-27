import AppKit
import FichaCore
import FichaData
import SwiftUI
import UniformTypeIdentifiers

/// Where a side of the card the user makes or edits takes its image, under the
/// side's text: an image dragged from Finder or a browser onto it, or pasted
/// with ⌘V once it has the focus, which a click or Tab gives it, or while the
/// side's text has it, as `pastesImages(while:put:)` says. With an
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

    /// Puts the image `pasteboard` holds on the side.
    private func take(from pasteboard: NSPasteboard) {
        put(DroppedImage(pasteboardItems: AppKitPasteboardItem.items(of: pasteboard)))
    }
}

extension View {
    /// Makes ⌘V, while `hasFocus`, put the image the clipboard holds on the
    /// side whose text field this is, through `put`, when it holds an image
    /// and no text. Otherwise the field pastes as it always does.
    func pastesImages(while hasFocus: Bool, put: @escaping (DroppedImage) -> Void) -> some View {
        background {
            // A hidden button, as ⌘N's, whose shortcut comes before the Edit
            // menu's Paste: that goes to the field's editor, which can't
            // paste an image.
            if hasFocus {
                Button {
                    if let image = DroppedImage(pastedIntoText: AppKitPasteboardItem.items(of: .general)) {
                        put(image)
                    } else {
                        // To the field's editor, as the Edit menu's Paste.
                        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                    }
                } label: {
                    Text(
                        "Paste",
                        comment:
                            "A hidden button of the Cards window: ⌘V in a side's text, which takes a copied image too."
                    )
                }
                .keyboardShortcut("v")
                .hidden()
            }
        }
    }
}

/// An item of an AppKit pasteboard, as FichaData reads it.
private struct AppKitPasteboardItem: PasteboardItem {
    let item: NSPasteboardItem

    var typeIdentifiers: [String] {
        item.types.map(\.rawValue)
    }

    func data(ofType type: String) -> Data? {
        item.data(forType: NSPasteboard.PasteboardType(type))
    }

    /// The items `pasteboard` holds.
    static func items(of pasteboard: NSPasteboard) -> [AppKitPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map(AppKitPasteboardItem.init)
    }
}

import AppKit
import FichaCore
import FichaData
import SwiftUI
import UniformTypeIdentifiers

/// Where a side of the card Lucas makes or edits takes its image, under the
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
    let put: (Data) -> Void
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
        .onPasteCommand(of: Self.imageTypes) { providers in
            take(providers)
        }
        .onDeleteCommand {
            if image != nil {
                remove()
            }
        }
        .onDrop(of: Self.imageTypes, isTargeted: $isTargeted) { providers in
            take(providers)
            return true
        }
    }

    /// What it takes: a file, as Finder drags or copies it, or an image's
    /// data, as a browser or the pasteboard holds it.
    private static let imageTypes: [UTType] = [.fileURL, .image]

    /// Puts the image in the first of `providers` on the side, once it's
    /// loaded. What doesn't load goes to the window as no data, which it
    /// refuses, saying so.
    private func take(_ providers: [NSItemProvider]) {
        Task {
            put(await imageData(in: providers) ?? Data())
        }
    }
}

/// The image in the first of `providers` that holds a local file or an
/// image's data: the file's contents, as Finder drags or copies it, or the
/// data, as a browser or the pasteboard holds it, or nil when none does. A
/// web address is never fetched: Ficha makes no network calls.
private func imageData(in providers: [NSItemProvider]) async -> Data? {
    for provider in providers {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
            let file = await localFile(in: provider),
            let data = try? Data(contentsOf: file)
        {
            return data
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
            let data = await imageRepresentation(in: provider)
        {
            return data
        }
    }
    return nil
}

/// The local file `provider` holds, or nil when it holds none, or a web
/// address.
private func localFile(in provider: NSItemProvider) async -> URL? {
    await withCheckedContinuation { continuation in
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            continuation.resume(returning: url.flatMap { $0.isFileURL ? $0 : nil })
        }
    }
}

/// The image's data `provider` holds, in its first image format, or nil when
/// it can't be loaded.
private func imageRepresentation(in provider: NSItemProvider) async -> Data? {
    await withCheckedContinuation { continuation in
        _ = provider.loadDataRepresentation(for: .image) { data, _ in
            continuation.resume(returning: data)
        }
    }
}

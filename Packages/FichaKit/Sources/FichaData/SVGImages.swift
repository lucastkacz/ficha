import FichaCore
import FichaSVG
import Foundation

// SVG images, which ImageIO can't read, as an import brings them in (#229):
// drawn by the SVG drawer the engine was given, which in the app is its XPC
// service (ADR 0018). The CLI and the iPhone don't import, so they give none,
// and there an SVG stays an image Ficha can't read.

extension CardImage {
    /// The SVG `data` as `svgs` draws it, at `longestImageSide` pixels on its
    /// long side, since a drawing has no size in pixels, and on white, as on
    /// Anki's cards, written as a PNG, as Anki's pictures of formulas are.
    /// Something the drawer can't draw as an SVG is refused, as is every SVG
    /// once it stopped answering, or without a drawer.
    init(drawing data: Data, with svgs: (any SVGDrawer)?) throws(EngineError) {
        guard let image = svgs?.image(of: data, longestSide: longestImageSide) else {
            throw .notAnImage
        }
        try self.init(writing: image, isDrawing: true)
    }
}

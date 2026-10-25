import CoreGraphics
import FichaCore
import Foundation
import Synchronization

#if os(macOS)
    import AppKit
    import WebKit
#endif

// SVG images, which ImageIO can't read, as an import brings them in (#229):
// drawn by WebKit, Safari's engine, since macOS's own SVG reader, which
// `NSImage` and Quick Look use, drew 33 of a shared deck's 227 flags wrong.
// WebKit draws an SVG as an `<img>` of a web page, where it runs none of its
// scripts and fetches nothing, from the web or the disk, as in a browser.
// Only on the Mac: the iPhone doesn't import yet, so there an SVG stays an
// image Ficha can't read.

extension CardImage {
    /// The SVG `data` as `svgs` draws it, at `longestImageSide` pixels on its
    /// long side, since a drawing has no size in pixels, and on white, as on
    /// Anki's cards, written as every image that comes in. Something WebKit
    /// can't draw as an SVG is refused.
    init(drawing data: Data, with svgs: SVGDrawer) throws(EngineError) {
        guard let image = svgs.image(of: data, longestSide: longestImageSide) else {
            throw .notAnImage
        }
        try self.init(writing: image)
    }
}

/// Draws SVGs one after another in one web view, which it opens for the
/// first and closes once it's gone. WebKit draws on the main thread, so a
/// drawing waits for it there, as an import does, which runs away from the
/// main actor; on the main thread itself, it draws nothing, rather than wait
/// on itself.
final class SVGDrawer: Sendable {
    #if os(macOS)
        /// The web view, once the first SVG opened it, or nil after WebKit
        /// stopped answering.
        private let page = Mutex<SVGPage?>(nil)
        /// Whether WebKit stopped answering, so that the rest of an import's
        /// SVGs don't each wait for it.
        private let gaveUp = Mutex(false)
    #endif

    #if os(macOS)
        deinit {
            if let page = page.withLock({ $0 }) {
                Task { @MainActor in page.close() }
            }
        }
    #endif

    /// The SVG `data` drawn `longestSide` pixels on its long side, on white,
    /// in sRGB, or nil when WebKit can't draw it as an SVG, or when called on
    /// the main thread.
    func image(of data: Data, longestSide: Int) -> CGImage? {
        #if os(macOS)
            guard !Thread.isMainThread, !gaveUp.withLock({ $0 }) else {
                return nil
            }
            let drawn = Drawn()
            let opened = page.withLock { $0 }
            Task { @MainActor [self] in
                let open = opened ?? SVGPage()
                if opened == nil {
                    page.withLock { $0 = open }
                }
                open.draw(data, longestSide: longestSide) { drawn.finish(with: $0) }
            }
            // Far longer than a drawing takes, some 15 ms for a flag.
            guard let image = drawn.wait(seconds: 10) else {
                logger.error("WebKit didn't draw an SVG in 10 seconds, so the import's other SVGs aren't drawn")
                gaveUp.withLock { $0 = true }
                return nil
            }
            return image
        #else
            return nil
        #endif
    }
}

/// What a drawing ends with, which another thread waits for.
private final class Drawn: Sendable {
    private let image = Mutex<CGImage??>(nil)
    private let done = DispatchSemaphore(value: 0)

    /// Ends the drawing with `image`, or nil when it couldn't be drawn.
    func finish(with image: CGImage?) {
        self.image.withLock { $0 = image }
        done.signal()
    }

    /// What the drawing ended with, once it ended: the image, or nil when it
    /// couldn't be drawn; or nil when it hasn't ended in `seconds`.
    func wait(seconds: Int) -> CGImage?? {
        guard done.wait(timeout: .now() + .seconds(seconds)) == .success else {
            return nil
        }
        return image.withLock { $0 }
    }
}

#if os(macOS)
    /// A web view that draws one SVG at a time, as an `<img>` of a page of
    /// its own, and snapshots it.
    @MainActor
    private final class SVGPage: NSObject, WKNavigationDelegate {
        private let webView: WKWebView
        /// The SVG being drawn: its page's navigation, and what to tell when
        /// it's drawn, or can't be.
        private var drawing: (navigation: WKNavigation, finish: @Sendable (CGImage?) -> Void)?
        /// How many pixels a snapshot has for each of the points it asks for,
        /// as its first one tells: two on a Retina display.
        private var pixelsPerPoint = 1.0

        override init() {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            webView = WKWebView(frame: .zero, configuration: configuration)
            super.init()
            webView.navigationDelegate = self
        }

        /// Draws `svg` `longestSide` pixels on its long side, and tells
        /// `finish`. The page sizes the SVG from its own width and height,
        /// or its view box.
        func draw(_ svg: Data, longestSide: Int, finish: @escaping @Sendable (CGImage?) -> Void) {
            end(with: nil)
            webView.setFrameSize(CGSize(width: longestSide, height: longestSide))
            let page = """
                <!doctype html><html><head><style>
                html, body { margin: 0; padding: 0; background: #fff; overflow: hidden; }
                img { display: block; }
                </style></head><body><img src="data:image/svg+xml;base64,\(svg.base64EncodedString())" \
                onload="var s = \(longestSide) / Math.max(this.naturalWidth, this.naturalHeight); \
                this.style.width = Math.round(this.naturalWidth * s) + 'px'; \
                this.style.height = Math.round(this.naturalHeight * s) + 'px';"></body></html>
                """
            guard let navigation = webView.loadHTMLString(page, baseURL: nil) else {
                finish(nil)
                return
            }
            drawing = (navigation, finish)
        }

        /// Ends the drawing, if one is under way, and lets the web view go.
        func close() {
            end(with: nil)
            webView.navigationDelegate = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard drawing?.navigation === navigation else { return }
            let size = "var i = document.images[0]; i.complete && i.naturalWidth > 0 ? [i.width, i.height] : [0, 0]"
            webView.evaluateJavaScript(size) { [self] value, _ in
                guard drawing?.navigation === navigation else { return }
                guard let size = value as? [Int], size.count == 2, size[0] > 0, size[1] > 0 else {
                    end(with: nil)
                    return
                }
                snapshot(width: size[0], height: size[1], of: navigation)
            }
        }

        /// Snapshots the SVG drawn `width` by `height` points in the page
        /// `navigation` loaded, at two pixels a point, and shrinks it to a
        /// pixel a point. A snapshot comes at as many pixels a point as the
        /// web view has, one or two, so its first is taken again once it
        /// tells how many. Drawn at two, an SVG comes in the same whatever
        /// the web view, so that it isn't kept twice.
        private func snapshot(width: Int, height: Int, of navigation: WKNavigation, isRetaken: Bool = false) {
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)
            configuration.snapshotWidth = NSNumber(value: Double(2 * width) / pixelsPerPoint)
            webView.takeSnapshot(with: configuration) { [self] taken, _ in
                guard drawing?.navigation === navigation else { return }
                guard let image = taken?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    end(with: nil)
                    return
                }
                if image.width == 2 * width, image.height == 2 * height {
                    end(with: sized(image, width, height))
                } else if !isRetaken {
                    pixelsPerPoint *= Double(image.width) / Double(2 * width)
                    snapshot(width: width, height: height, of: navigation, isRetaken: true)
                } else {
                    logger.error(
                        "WebKit snapshot an SVG at \(image.width)×\(image.height) pixels, not \(2 * width)×\(2 * height)"
                    )
                    end(with: nil)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            failed(navigation, error)
        }

        func webView(
            _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
        ) {
            failed(navigation, error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            logger.error("WebKit's process ended while it drew an SVG")
            end(with: nil)
        }

        /// Ends the drawing of the page `navigation` loads, which `error`
        /// stopped.
        private func failed(_ navigation: WKNavigation, _ error: any Error) {
            guard drawing?.navigation === navigation else { return }
            logger.error("WebKit couldn't load the page of an SVG: \(String(describing: error), privacy: .public)")
            end(with: nil)
        }

        /// Ends the drawing under way, if any, with `image`.
        private func end(with image: CGImage?) {
            guard let drawing else { return }
            self.drawing = nil
            drawing.finish(image)
        }
    }

    /// `image` drawn `width` by `height` pixels, in sRGB, or nil when it
    /// can't be.
    private func sized(_ image: CGImage, _ width: Int, _ height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
#endif

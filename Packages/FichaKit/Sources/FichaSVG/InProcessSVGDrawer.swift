import CoreGraphics
import Foundation
import Synchronization

#if os(macOS)
    import AppKit
    import WebKit

    // WebKit, Safari's engine, draws an SVG as an `<img>` of a web page, where
    // it runs none of its scripts and fetches nothing, from the web or the
    // disk, as in a browser. macOS's own SVG reader, which `NSImage` and Quick
    // Look use, drew 33 of a shared deck's 227 flags wrong (#229). Its page
    // also blocks every load with WebKit's content rules, as Safari's content
    // blockers do, in case WebKit ever fetches what an SVG names: the drawer's
    // XPC service holds the network entitlement only because WebKit needs it
    // in the sandbox (ADR 0018). The SVG itself, which the page shows from
    // its own bytes as a `data:` URL, still draws.

    /// Draws SVGs with WebKit in this process, one after another in one web
    /// view, which it opens for the first and closes once it's gone: in the
    /// SVG drawer's XPC service, and in `swift test`. WebKit draws on the main
    /// thread, so a drawing waits for it there, as an import does, which runs
    /// away from the main actor, and the service, which answers on a queue of
    /// its own; on the main thread itself, it draws nothing, rather than wait
    /// on itself.
    public final class InProcessSVGDrawer: SVGDrawer {
        /// The web view, once the first SVG opened it.
        private let page = Mutex<SVGPage?>(nil)
        /// Whether WebKit stopped answering, so that the rest of an import's
        /// SVGs don't each wait for it.
        private let gaveUp = Mutex(false)

        public init() {}

        deinit {
            if let page = page.withLock({ $0 }) {
                Task { @MainActor in page.close() }
            }
        }

        /// The SVG `svg` drawn `longestSide` pixels on its long side, on
        /// white, in sRGB, or nil when WebKit can't draw it as an SVG, when
        /// WebKit stopped answering, for this SVG or one before it, or when
        /// called on the main thread.
        public func image(of svg: Data, longestSide: Int) -> CGImage? {
            guard !Thread.isMainThread, !gaveUp.withLock({ $0 }) else {
                return nil
            }
            let drawing = PendingDrawing()
            let opened = page.withLock { $0 }
            Task { @MainActor [self] in
                if let opened {
                    opened.draw(svg, longestSide: longestSide) { drawing.finish(with: $0) }
                    return
                }
                withRulesBlockingEveryLoad { [self] rules in
                    guard let rules else {
                        drawing.finish(with: nil)
                        return
                    }
                    let open = SVGPage(blocking: rules)
                    page.withLock { $0 = open }
                    open.draw(svg, longestSide: longestSide) { drawing.finish(with: $0) }
                }
            }
            // Far longer than a drawing takes, some 25 ms for a flag.
            switch drawing.wait(seconds: 10) {
            case .drawn(let image):
                return image
            case .notDrawn:
                return nil
            case .unanswered:
                logger.error("WebKit didn't draw an SVG in 10 seconds, so the import's other SVGs aren't drawn")
                gaveUp.withLock { $0 = true }
                return nil
            }
        }
    }

    /// WebKit's content rules that block every load, from the web, the disk or
    /// anywhere else, compiled once for the process, whatever its drawers.
    @MainActor private var blockingEveryLoad = RulesBlockingEveryLoad.notAskedFor

    /// Where the content rules that block every load stand.
    private enum RulesBlockingEveryLoad {
        case notAskedFor
        /// Being compiled, for the drawings that wait for them.
        case compiling(waiting: [@MainActor (WKContentRuleList?) -> Void])
        /// Compiled, or nil when WebKit couldn't compile them.
        case compiled(WKContentRuleList?)
    }

    /// Hands `use` the content rules that block every load, compiled the
    /// first time, or nil when WebKit couldn't compile them, and then no SVG
    /// is drawn. It never awaits WebKit: its `async` compile resumes on a
    /// thread of Swift's concurrency pool, and an import waits for its drawing
    /// on one of those, so imports at once, as in `swift test` on GitHub's
    /// three-core Macs, can take them all, and the drawing waits for theirs to
    /// give up. WebKit calls the completion handler on the main thread.
    @MainActor
    private func withRulesBlockingEveryLoad(_ use: @escaping @MainActor (WKContentRuleList?) -> Void) {
        switch blockingEveryLoad {
        case .compiled(let rules):
            use(rules)
        case .compiling(let waiting):
            blockingEveryLoad = .compiling(waiting: waiting + [use])
        case .notAskedFor:
            // Compiled into a scratch folder, which WebKit keeps them in.
            guard let store = WKContentRuleListStore(url: URL.temporaryDirectory.appending(path: "SVGDrawerRules"))
            else {
                logger.error("WebKit gave no store for the rules that keep the SVG drawer off the network")
                blockingEveryLoad = .compiled(nil)
                use(nil)
                return
            }
            blockingEveryLoad = .compiling(waiting: [use])
            store.compileContentRuleList(
                forIdentifier: "BlockEveryLoad",
                encodedContentRuleList: #"[{"trigger": {"url-filter": ".*"}, "action": {"type": "block"}}]"#
            ) { rules, error in
                if let error {
                    logger.error(
                        "WebKit couldn't compile the rules that keep the SVG drawer off the network: \(error, privacy: .public)"
                    )
                }
                guard case .compiling(let waiting) = blockingEveryLoad else { return }
                blockingEveryLoad = .compiled(rules)
                for use in waiting {
                    use(rules)
                }
            }
        }
    }

    /// A web view that draws one SVG at a time, as an `<img>` of its first,
    /// empty page, and snapshots it, with every load blocked. It never loads a
    /// page: before loading one, WebKit asks macOS whether the app signs into
    /// it (AppSSO), and on GitHub's Macs the answer took a minute.
    @MainActor
    private final class SVGPage: NSObject, WKNavigationDelegate {
        private let webView: WKWebView
        /// The SVG being drawn: its number, and what to tell when it's drawn,
        /// or can't be.
        private var drawing: (number: Int, finish: @Sendable (CGImage?) -> Void)?
        /// How many SVGs it started drawing.
        private var started = 0
        /// How many pixels a snapshot has for each of the points it asks for,
        /// as its first one tells: two on a Retina display.
        private var pixelsPerPoint = 1.0

        /// A page whose every load `rules` block.
        init(blocking rules: WKContentRuleList) {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.userContentController.add(rules)
            webView = WKWebView(frame: .zero, configuration: configuration)
            super.init()
            webView.navigationDelegate = self
        }

        /// Draws `svg` `longestSide` pixels on its long side, and tells
        /// `finish`.
        func draw(_ svg: Data, longestSide: Int, finish: @escaping @Sendable (CGImage?) -> Void) {
            end(with: nil)
            started += 1
            let number = started
            drawing = (number, finish)
            webView.setFrameSize(CGSize(width: longestSide, height: longestSide))
            let arguments: [String: Any] = ["svg": svg.base64EncodedString(), "side": longestSide]
            webView.callAsyncJavaScript(Self.showing, arguments: arguments, in: nil, in: .defaultClient) {
                [self] result in
                guard drawing?.number == number else { return }
                guard case .success(let value) = result, let size = value as? [Int], size.count == 2, size[0] > 0,
                    size[1] > 0
                else {
                    end(with: nil)
                    return
                }
                snapshot(width: size[0], height: size[1], of: number)
            }
        }

        /// A script that shows the SVG `svg`, in base 64, alone on the page,
        /// `side` points on its long side, sized from its own width and
        /// height, or its view box, and returns its width and height, or
        /// fails when it isn't an SVG WebKit can draw.
        private static let showing = """
            const image = new Image();
            image.src = 'data:image/svg+xml;base64,' + svg;
            await image.decode();
            if (!(image.naturalWidth > 0 && image.naturalHeight > 0)) return null;
            const scale = side / Math.max(image.naturalWidth, image.naturalHeight);
            image.style.display = 'block';
            image.style.width = Math.round(image.naturalWidth * scale) + 'px';
            image.style.height = Math.round(image.naturalHeight * scale) + 'px';
            document.documentElement.style.cssText = 'margin: 0; padding: 0; background: #fff; overflow: hidden;';
            document.body.style.cssText = 'margin: 0; padding: 0; background: #fff; overflow: hidden;';
            document.body.replaceChildren(image);
            return [image.width, image.height];
            """

        /// Ends the drawing, if one is under way, and lets the web view go.
        func close() {
            end(with: nil)
            webView.navigationDelegate = nil
        }

        /// Snapshots the SVG drawing `number` shows `width` by `height`
        /// points, at two pixels a point, and shrinks it to a pixel a point.
        /// A snapshot comes at as many pixels a point as the web view has,
        /// one or two, so its first is taken again once it tells how many.
        /// Drawn at two, an SVG comes in the same whatever the web view, so
        /// that it isn't kept twice.
        private func snapshot(width: Int, height: Int, of number: Int, isRetaken: Bool = false) {
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)
            configuration.snapshotWidth = NSNumber(value: Double(2 * width) / pixelsPerPoint)
            webView.takeSnapshot(with: configuration) { [self] taken, _ in
                guard drawing?.number == number else { return }
                guard let image = taken?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    end(with: nil)
                    return
                }
                if image.width == 2 * width, image.height == 2 * height {
                    end(with: sized(image, width, height))
                } else if !isRetaken {
                    pixelsPerPoint *= Double(image.width) / Double(2 * width)
                    snapshot(width: width, height: height, of: number, isRetaken: true)
                } else {
                    logger.error(
                        "WebKit snapshot an SVG at \(image.width)×\(image.height) pixels, not \(2 * width)×\(2 * height)"
                    )
                    end(with: nil)
                }
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            logger.error("WebKit's process ended while it drew an SVG")
            end(with: nil)
        }

        /// Ends the drawing under way, if any, with `image`.
        private func end(with image: CGImage?) {
            guard let drawing else { return }
            self.drawing = nil
            drawing.finish(image)
        }
    }

    /// `image` drawn `width` by `height` pixels, in sRGB, without an alpha
    /// channel, since a snapshot is opaque, or nil when it can't be.
    private func sized(_ image: CGImage, _ width: Int, _ height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
#endif

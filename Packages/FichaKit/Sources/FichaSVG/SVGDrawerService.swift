import CoreGraphics
import Foundation
import Synchronization

#if os(macOS)
    // The SVG drawer's XPC service: a small process inside the app, and the
    // only part of Ficha that holds the network entitlement, which WebKit
    // needs in the sandbox, so that the app holds none (ADR 0018). The app asks
    // it to draw each SVG, and it hands the drawing back as its pixels, which
    // XPC carries as they are, so that an SVG comes in exactly as drawn in the
    // process. An XPC service to keep an entitlement apart is Apple's way
    // ("Creating XPC services"); handing a drawing over as pixels is our own.

    /// What the app asks the SVG drawer's XPC service, in Objective-C, which
    /// `NSXPCConnection` speaks.
    @objc protocol SVGDrawing {
        /// Draws `svg` `longestSide` pixels on its long side, as
        /// `InProcessSVGDrawer` does, and replies with the drawing: its
        /// pixels, four bytes each, in sRGB with no alpha, in rows of
        /// `bytesPerRow` bytes, and its width and height; or with no pixels
        /// when it can't be drawn.
        func draw(
            _ svg: Data, longestSide: Int,
            reply: @escaping @Sendable (_ pixels: Data?, _ width: Int, _ height: Int, _ bytesPerRow: Int) -> Void)
    }

    /// The SVG drawer's XPC service, which listens to the app: each connection
    /// draws with a drawer of its own, which lets go of its web view once the
    /// connection ends, with the import that opened it.
    public final class SVGDrawerService: NSObject, NSXPCListenerDelegate, Sendable {
        public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
            connection.exportedInterface = NSXPCInterface(with: SVGDrawing.self)
            connection.exportedObject = ConnectionDrawer()
            connection.resume()
            return true
        }
    }

    /// One connection's drawings, in the service, which XPC asks for on a
    /// queue of the connection's own, one at a time.
    private final class ConnectionDrawer: NSObject, SVGDrawing, Sendable {
        private let drawer = InProcessSVGDrawer()

        func draw(
            _ svg: Data, longestSide: Int,
            reply: @escaping @Sendable (_ pixels: Data?, _ width: Int, _ height: Int, _ bytesPerRow: Int) -> Void
        ) {
            guard let image = drawer.image(of: svg, longestSide: longestSide), let pixels = pixels(of: image) else {
                reply(nil, 0, 0, 0)
                return
            }
            reply(pixels, image.width, image.height, image.bytesPerRow)
        }
    }

    /// Draws an import's SVGs through the SVG drawer's XPC service, on one
    /// connection, which it closes once it's gone. A drawing waits for the
    /// service, as an import does, which runs away from the main actor, and
    /// takes the answer on the thread that waits: XPC hands an answer on to
    /// a thread of its own otherwise, which macOS holds back while every
    /// thread of Swift's concurrency pool waits, as imports at once make them.
    public final class ServiceSVGDrawer: SVGDrawer {
        /// The connection, which Foundation doesn't mark as safe to share
        /// between threads.
        private let connection: Mutex<NSXPCConnection>

        /// A drawer that asks the service inside this app whose bundle
        /// identifier is `serviceName`.
        public convenience init(serviceName: String) {
            self.init(connection: NSXPCConnection(serviceName: serviceName))
        }

        /// A drawer that asks the service listening at `endpoint`, as in
        /// `swift test`, where it listens in the process.
        public convenience init(endpoint: NSXPCListenerEndpoint) {
            self.init(connection: NSXPCConnection(listenerEndpoint: endpoint))
        }

        private init(connection: sending NSXPCConnection) {
            connection.remoteObjectInterface = NSXPCInterface(with: SVGDrawing.self)
            connection.resume()
            self.connection = Mutex(connection)
        }

        deinit {
            connection.withLock { $0.invalidate() }
        }

        /// The SVG `svg` as the service draws it, or nil when it can't draw
        /// it or can't be reached. It waits with no limit of its own: the
        /// service answers once it waited its 10 seconds for WebKit, and XPC
        /// tells when it quits or crashes.
        public func image(of svg: Data, longestSide: Int) -> CGImage? {
            let drawing = PendingDrawing()
            let isAsked = connection.withLock { connection in
                let service =
                    connection.synchronousRemoteObjectProxyWithErrorHandler { error in
                        logger.error("Couldn't reach the SVG drawer's XPC service: \(error, privacy: .public)")
                        drawing.finish(with: nil)
                    } as? SVGDrawing
                service?.draw(svg, longestSide: longestSide) { pixels, width, height, bytesPerRow in
                    drawing.finish(
                        with: pixels.flatMap { drawn($0, width: width, height: height, bytesPerRow: bytesPerRow) }
                    )
                }
                return service != nil
            }
            guard isAsked else {
                logger.error("The SVG drawer's XPC connection gave no service to ask")
                return nil
            }
            // XPC ended the drawing before `draw` returned.
            switch drawing.wait(seconds: 0) {
            case .drawn(let image):
                return image
            case .notDrawn:
                return nil
            case .unanswered:
                logger.error("The SVG drawer's XPC connection returned with no answer and no error")
                return nil
            }
        }
    }

    /// The pixels of `image`, a drawing as `InProcessSVGDrawer` draws them, in
    /// sRGB with no alpha, as XPC carries them, or nil when it isn't one.
    private func pixels(of image: CGImage) -> Data? {
        guard image.bitsPerComponent == 8, image.bitsPerPixel == 32, image.alphaInfo == .noneSkipLast,
            image.byteOrderInfo == .orderDefault, image.colorSpace?.name == CGColorSpace.sRGB,
            let pixels = image.dataProvider?.data
        else {
            logger.error("The SVG drawer drew an image it can't hand over, in a layout of its own")
            return nil
        }
        return pixels as Data
    }

    /// The drawing whose pixels XPC carried as `pixels(of:)` gave them, `width`
    /// by `height`, in rows of `bytesPerRow` bytes, or nil when they don't
    /// make one.
    private func drawn(_ pixels: Data, width: Int, height: Int, bytesPerRow: Int) -> CGImage? {
        guard width > 0, height > 0, bytesPerRow >= 4 * width, pixels.count >= bytesPerRow * height,
            let space = CGColorSpace(name: CGColorSpace.sRGB), let provider = CGDataProvider(data: pixels as CFData)
        else {
            logger.error("The SVG drawer's XPC service handed over pixels that make no image")
            return nil
        }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
#endif

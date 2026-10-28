import CoreGraphics
import FichaSVG
import Foundation
import Network
import Testing
import os

@testable import FichaData

/// Tests on the SVG drawer, the only part of Ficha allowed on the network
/// (ADR 0018), which draws the SVGs an import brings in.
struct SVGDrawerTests {
    // An SVG from a deck can name images, fonts and style sheets on the web,
    // and the drawer draws only what's already on the Mac.
    @Test("an SVG that names files on a server is drawn without them, and the server hears from nobody")
    func anSVGIsDrawnOffTheNetwork() async throws {
        let server = try await LocalServer()
        let web = "http://127.0.0.1:\(server.port)"
        let svg = Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" width="300" height="200">
            <style>@import url("\(web)/style.css"); @font-face { font-family: Web; src: url("\(web)/font.woff"); }
            text { font-family: Web; }</style>
            <rect width="300" height="200" fill="#f2b400"/>
            <image href="\(web)/bird.png" width="100" height="100"/>
            <use href="\(web)/shapes.svg#star"/>
            <text x="10" y="190">hornero</text>
            </svg>
            """.utf8)

        let image = try #require(InProcessSVGDrawer().image(of: svg, longestSide: 300))

        #expect(image.width == 300)
        #expect(image.height == 200)
        #expect(server.connections == 0)
    }

    // The app draws through the drawer's XPC service, which hands each
    // drawing back as its pixels; here the service listens in the process.
    @Test("an SVG drawn by the drawer's XPC service comes in as one drawn in the process, and a damaged one doesn't")
    func anSVGDrawnByTheServiceComesInTheSame() throws {
        let service = SVGDrawerService()
        let listener = NSXPCListener.anonymous()
        listener.delegate = service
        listener.resume()
        defer { listener.invalidate() }
        let drawer = ServiceSVGDrawer(endpoint: listener.endpoint)

        let sun = try CardImage(drawing: sunSVG, with: drawer)

        #expect(try sun == CardImage(drawing: sunSVG, with: InProcessSVGDrawer()))
        #expect(throws: EngineError.notAnImage) {
            try CardImage(drawing: Data("<svg xmlns=\"http://www.w3.org/2000/svg\"".utf8), with: drawer)
        }
    }
}

/// A web server on this Mac, on a port of its own, that counts the
/// connections it gets, and answers none.
private final class LocalServer: Sendable {
    let port: UInt16
    private let listener: NWListener
    private let counted = OSAllocatedUnfairLock(initialState: 0)

    /// How many connections it got.
    var connections: Int {
        counted.withLock { $0 }
    }

    init() async throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [counted] connection in
            counted.withLock { $0 += 1 }
            connection.cancel()
        }
        let listener = listener
        try await withCheckedThrowingContinuation { (ready: CheckedContinuation<Void, any Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    ready.resume()
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    ready.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: .global())
        }
        port = try #require(listener.port).rawValue
    }

    deinit {
        listener.cancel()
    }
}

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

    // An import waits for each drawing on a thread of Swift's concurrency
    // pool, which has one per core: on GitHub's three-core Macs, imports at
    // once take them all. One drawing, with one web view, while tasks hold
    // the pool's other threads, keeps WebKit's processes as few as an import
    // starts.
    @Test("an SVG is drawn while the drawing and other tasks hold every thread of Swift's concurrency pool")
    func anSVGIsDrawnWhileEveryThreadWaits() async {
        #expect(await isDrawnWhileEveryThreadWaits(by: InProcessSVGDrawer()))
    }

    // The app draws through the drawer's XPC service, which hands each
    // drawing back as its pixels; here the service listens in the process.
    @Test("an SVG drawn by the drawer's XPC service comes in as one drawn in the process, and a damaged one doesn't")
    func anSVGDrawnByTheServiceComesInTheSame() throws {
        let service = ServiceInTheProcess()
        defer { extendLifetime(service) }

        let sun = try CardImage(drawing: sunSVG, with: service.drawer)

        #expect(try sun == CardImage(drawing: sunSVG, with: InProcessSVGDrawer()))
        #expect(throws: EngineError.notAnImage) {
            try CardImage(drawing: Data("<svg xmlns=\"http://www.w3.org/2000/svg\"".utf8), with: service.drawer)
        }
    }

    // XPC hands the service's answer to the app on a thread that macOS holds
    // back while the pool's threads all wait.
    @Test(
        "an SVG is drawn by the drawer's XPC service while the drawing and other tasks hold every thread of Swift's concurrency pool"
    )
    func anSVGIsDrawnByTheServiceWhileEveryThreadWaits() async {
        let service = ServiceInTheProcess()
        defer { extendLifetime(service) }

        #expect(await isDrawnWhileEveryThreadWaits(by: service.drawer))
    }
}

/// The SVG drawer's XPC service, listening in the process, and a drawer that
/// asks it, as the app's drawer asks the service in its bundle.
private final class ServiceInTheProcess {
    let drawer: ServiceSVGDrawer
    /// The listener's delegate, which it holds weakly.
    private let service: SVGDrawerService
    private let listener: NSXPCListener

    init() {
        let service = SVGDrawerService()
        let listener = NSXPCListener.anonymous()
        listener.delegate = service
        listener.resume()
        self.service = service
        self.listener = listener
        drawer = ServiceSVGDrawer(endpoint: listener.endpoint)
    }

    deinit {
        listener.invalidate()
    }
}

/// Whether `drawer` draws an SVG while tasks hold every other thread of
/// Swift's concurrency pool, and the drawing holds its own.
private func isDrawnWhileEveryThreadWaits(by drawer: some SVGDrawer) async -> Bool {
    let others = ProcessInfo.processInfo.activeProcessorCount - 1
    let holding = DispatchSemaphore(value: 0)
    let done = DispatchSemaphore(value: 0)

    async let isDrawn = drawing(sunSVG, by: drawer, once: others, hold: holding, then: done)
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<others {
            group.addTask { holdingAThread(saying: holding, until: done) }
        }
    }
    return await isDrawn
}

/// Whether `drawer` draws `svg` once `count` tasks hold their threads, which
/// each tells through `held`, while this one holds its own; it lets them go
/// through `done` once it's drawn, or once they took 30 seconds to hold
/// theirs.
private func drawing(
    _ svg: Data, by drawer: some SVGDrawer, once count: Int, hold held: DispatchSemaphore, then done: DispatchSemaphore
) -> Bool {
    defer {
        for _ in 0..<count { done.signal() }
    }
    for _ in 0..<count where held.wait(timeout: .now() + 30) == .timedOut {
        return false
    }
    return drawer.image(of: svg, longestSide: 100) != nil
}

/// Holds its thread, once it tells so through `holding`, until `done` is
/// signalled, or for 30 seconds at most.
private func holdingAThread(saying holding: DispatchSemaphore, until done: DispatchSemaphore) {
    holding.signal()
    _ = done.wait(timeout: .now() + 30)
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

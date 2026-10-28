import FichaSVG
import Foundation

// The SVG drawer's XPC service, inside each app: it draws the SVGs an import
// brings in, with WebKit, and it's the only part of Ficha that holds the
// network entitlement (ADR 0018). Its Info.plist runs it on a run loop, which
// WebKit needs on the main thread.

/// The listener's delegate, kept here, since the listener holds it weakly.
let service = SVGDrawerService()
let listener = NSXPCListener.service()
listener.delegate = service
// It never returns: the service runs until macOS ends it.
listener.resume()

import AppKit
import FichaCLI

// The cards of the app this CLI is built with: Ficha Dev's when it's built for
// development, Lucas's when it's built into the real Ficha. Ficha Dev's CLI
// runs on the time Ficha Dev's debug menu moved forward, as Ficha Dev does.
// Whether that app runs, which a restore waits for, macOS says by its bundle
// identifier.
let variant = AppVariant.current
FichaCommand.main(dataFolder: variant.dataFolder, runsOnDebugTime: variant.hasDebugMenu, appName: variant.name) {
    !NSRunningApplication.runningApplications(withBundleIdentifier: variant.bundleIdentifier).isEmpty
}

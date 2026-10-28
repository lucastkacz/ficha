import AppKit
import FichaCLI

// The cards of the app this CLI is built with: Ficha Dev's when it's built for
// development, Lucas's when it's built into the real Ficha. Ficha Dev's CLI
// runs on the time Ficha Dev's debug menu moved forward, as Ficha Dev does.
// A CLI in its sandbox reads files from the Downloads folder alone, which it
// reaches through a link in its own container (ADR 0018). Whether its app
// runs, which a restore waits for, macOS says by its bundle identifier.
let variant = AppVariant.current
let readsOnlyDownloads = signedEntitlement("com.apple.security.files.downloads.read-only") as? Bool == true
await FichaCommand.main(
    dataFolder: { try variant.dataFolder }, refineFilesOnlyIn: readsOnlyDownloads ? URL.downloadsDirectory : nil,
    runsOnDebugTime: variant.hasDebugMenu, appName: variant.name,
    appIsRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: variant.bundleIdentifier).isEmpty }
)

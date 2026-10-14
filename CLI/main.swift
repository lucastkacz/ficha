import FichaCLI

// The cards of the app this CLI is built with: Ficha Dev's when it's built for
// development, Lucas's when it's built into the real Ficha. Ficha Dev's CLI
// runs on the time Ficha Dev's debug menu moved forward, as Ficha Dev does.
let variant = AppVariant.current
FichaCommand.main(dataFolder: variant.dataFolder, runsOnDebugTime: variant.hasDebugMenu)

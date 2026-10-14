import FichaCLI

// The cards of the app this CLI is built with: Ficha Dev's when it's built for
// development, Lucas's when it's built into the real Ficha.
FichaCommand.main(dataFolder: AppVariant.current.dataFolder)

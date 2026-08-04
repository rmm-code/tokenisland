import TokenIslandKit

// Sparkle is linked only by the executable, so the update installer is handed
// to the app here — before the environment that reads it is built.
let sparkle = SparkleUpdaterBridge()
TokenIslandLaunch.setUpdateInstaller { sparkle.install() }

TokenIslandApp.main()

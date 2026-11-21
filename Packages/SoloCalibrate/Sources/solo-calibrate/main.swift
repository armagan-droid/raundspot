import Foundation
import SoloCalibrateKit

let code = CLI.run(Array(CommandLine.arguments.dropFirst())) { print($0) }
exit(code)

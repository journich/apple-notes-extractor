import Foundation
import Notes2MyICORCore

@main
struct Notes2MyICORCLI {
    static func main() {
        let code = AppRunner().run(arguments: Array(CommandLine.arguments.dropFirst()))
        Foundation.exit(Int32(code))
    }
}

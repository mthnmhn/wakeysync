import Foundation

do {
    let argv = Array(CommandLine.arguments.dropFirst())
    let exitCode = try runCLI(argv: argv)
    exit(exitCode)
} catch let error as CLIError {
    fputs("error: \(error)\n", stderr)
    exit(1)
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}

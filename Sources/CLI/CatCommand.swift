import ArgumentParser
import Foundation
import ISO9660

/// Command for writing files to stdout
struct CatCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cat",
        abstract: "Write file contents to stdout"
    )

    @OptionGroup()
    var options: CLI

    @Argument
    var path: String

    mutating func run() throws {
        do {
            let fs = options.fs
            let content = try fs.readFile(try options.getFSEntry(path))
            defer {
                content.close()
            }
            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer {
                buffer.deallocate()
            }

            while content.hasBytesAvailable {
                try autoreleasepool {
                    let read = content.read(buffer, maxLength: bufferSize)
                    if read > 0 {
                        FileHandle.standardOutput.write(Data(bytes: buffer, count: read))
                    } else if let error = content.streamError {
                        throw error
                    } else {
                        return // EOF
                    }
                }
            }
        } catch {
            print("Error: \(error)")
            Thread.callStackSymbols.forEach{print($0)}
            Foundation.exit(EXIT_FAILURE)
        }
    }
}

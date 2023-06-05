import ArgumentParser
import Foundation
import ISO9660

@main
struct CLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "iso9660",
        abstract: "A tool for reading & creating ISO 9660 images",
        subcommands: [InfoCommand.self, LsCommand.self, CatCommand.self, CreateCommand.self]
    )

    @Option(name: .shortAndLong, help: "The path to the ISO image file")
    var iso: String

    @Flag(name: .long, help: "Use path table instead of directory records")
    var usePathTable: Bool = false

    @Option(name: .long, help: "Volume descriptor to use (primary | supplementary | enhanced | any)")
    var volumeDescriptor: UseVolumeDescriptor = .any

    func die(_ error: String) -> Never {
        print("error: \(error)")
        Foundation.exit(EXIT_FAILURE)
    }

    lazy var media: ISOImageMedia = {
        let url = URL(fileURLWithPath: iso)
        return try! ISOImageFileMedia(url)
    }()

    lazy var writableMedia: ISOImageMedia = {
        let url = URL(fileURLWithPath: iso)
        return try! ISOImageFileMedia(url, readOnly: false)
    }()

    /// The filesystem object corresponding to the given options
    lazy var fs: ISOFileSystem = {
        return try! ISOFileSystem(media)
    }()

    /// Returns the [FSEntry] corresponding to the given path
    /// - Parameter path: The path to the file or directory
    /// - Returns: The [FSEntry] corresponding to the given path
    mutating func getFSEntry(_ path: String) throws -> FSEntry {
        return try fs.getFSEntry(path, using: volumeDescriptor.toPathResolution(usePathTable))
    }
}

enum UseVolumeDescriptor: String, ExpressibleByArgument {
    case primary
    case supplementary
    case joliet
    case enhanced
    case any

    func toPathResolution(_ usePathTable: Bool) -> ISOFileSystem.PathResolution {
        let pt = usePathTable ? ISOFileSystem.PathTraversal.usePathTable : ISOFileSystem.PathTraversal.useDirectoryRecords
        switch self {
        case .primary:
            return .primary(pt)
        case .supplementary, .joliet:
            return .supplementary(pt)
        case .enhanced:
            return .enhanced(pt)
        case .any:
            return .any(pt)
        }
    }
}

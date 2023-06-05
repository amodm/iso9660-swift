import ArgumentParser
import Foundation
import ISO9660

/// Command for creating ISO images
struct CreateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create ISO image"
    )

    @OptionGroup()
    var options: CLI

    @Option
    var volumeIdentifier: String = "DATA"

    @Argument
    var rootDirectory: String

    mutating func run() throws {
        while rootDirectory.last == "/" {
            rootDirectory.removeLast()
        }
        do {
            let writeOptions = ISOWriter.WriteOptions(volumeIdentifier: volumeIdentifier)
            let rd = rootDirectory
            let writer = ISOWriter(media: options.writableMedia, options: writeOptions) { path in
                let localPath = "\(rd)\(path)"
                return InputStream(fileAtPath: localPath)!
            }

            let fm = FileManager.default
            if !fm.fileExists(atPath: rootDirectory) {
                options.die("\(rootDirectory) does not exist")
            }
            try walkAndAdd(writer, rootDirectory, "")
            try writer.writeAndClose()
        } catch {
            print("Error: \(error)")
            Thread.callStackSymbols.forEach{print($0)}
            Foundation.exit(EXIT_FAILURE)
        }
    }

    func walkAndAdd(_ writer: ISOWriter, _ localPath: String, _ volPath: String) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: localPath) {
            options.die("\(localPath) does not exist")
        }
        for name in try fm.contentsOfDirectory(atPath: localPath) {
            let localPath = "\(localPath)/\(name)"
            let volPath = "\(volPath)/\(name)"
            let attributes = try fm.attributesOfItem(atPath: localPath)
            let type = attributes[.type] as! FileAttributeType
            var metadata = FSEntry.Metadata()
            metadata.uid = attributes[.ownerAccountID] as? Int
            metadata.gid = attributes[.groupOwnerAccountID] as? Int
            metadata.creationDate = attributes[.creationDate] as? Date
            metadata.modificationDate = attributes[.modificationDate] as? Date
            metadata.mode = attributes[.posixPermissions] as? Int
            if type == .typeDirectory {
                try writer.addDirectory(
                    path: volPath,
                    metadata: metadata
                )
                try walkAndAdd(writer, localPath, volPath)
            } else if type == .typeRegular {
                try writer.addFile(
                    path: volPath,
                    size: attributes[.size] as! UInt64,
                    metadata: metadata
                )
            } else if type == .typeSymbolicLink {
                try writer.addSymlink(
                    path: volPath,
                    target: try fm.destinationOfSymbolicLink(atPath: localPath),
                    metadata: metadata
                )
            } else {
                options.die("Unsupported file type: \(type)")
            }
        }
    }
}

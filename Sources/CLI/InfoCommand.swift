import ArgumentParser
import Foundation
import ISO9660

struct InfoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Prints information about the ISO image"
    )

    @OptionGroup()
    var options: CLI

    func run() throws {
        do {
            let url = URL(fileURLWithPath: options.iso)
            let media = try ISOImageFileMedia(url)
            let fs = try ISOFileSystem(media)
            for vd in fs.descriptors {
                vd.printInfo()
            }
        } catch {
            print("Error: \(error)")
            Thread.callStackSymbols.forEach{print($0)}
            Foundation.exit(EXIT_FAILURE)
        }
    }
}

extension VolumeDirectoryDescriptor {
    func printInfo() {
        let typeStr = isPrimary ? "Primary" : isSupplementary ? "Supplementary" : isEnhanced ? "Enhanced" : "Unknown"
        print("[ISO 9660 Volume Directory Descriptor]:")
        print("  Type: \(typeStr)")
        print("  System Identifier: \(systemIdentifier)")
        print("  Volume Identifier: \(volumeIdentifier)")
        print("  Path Table Size: \(pathTableSize) bytes")
        print("  Path Table Location (LBA): \(lPathTableLocation)")
        print("  Volume Set Identifier: \(volumeSetIdentifier)")
        print("  Volumes in set: \(volumeSetSize)")
        print("  Size: \(volumeSizeInLogicalBlocks) blocks x \(logicalBlockSize) bytes/block = \(volumeSizeInBytes) bytes")
    }
}

extension VolumeBootDescriptor {
    func printInfo() {
        print("[ISO 9660 Volume Boot Descriptor]:")
        print("  System Identifier: \(systemIdentifier)")
        print("  Boot Identifier: \(bootIdentifier)")
    }
}

extension VolumePartitionDescriptor {
    func printInfo() {
        print("[ISO 9660 Volume Partition Descriptor]:")
        print("  System Identifier: \(systemIdentifier)")
        print("  Partition Identifier: \(partitionIdentifier)")
        print("  Partition Location (LBA): \(partitionLocation)")
        print("  Partition Size (blocks): \(partitionSizeInBlocks)")
    }
}

extension VolumeGenericDescriptor {
    func printInfo() {
        print("[ISO 9660 Volume Generic Descriptor]:")
        print("  Type: \(type)")
        print("  Version: \(version)")
    }
}

extension VolumeDescriptor {
    func printInfo() {
        switch self {
        case .terminator:
            print("[ISO 9660 Volume Terminator Descriptor]")
        case .boot(let desc):
            desc.printInfo()
        case .primary(let desc):
            desc.printInfo()
        case .supplementary(let desc):
            desc.printInfo()
        case .enhanced(let desc):
            desc.printInfo()
        case .partition(let desc):
            desc.printInfo()
        case .generic(let desc):
            desc.printInfo()
        }
    }
}

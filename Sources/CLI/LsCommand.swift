import ArgumentParser
import Foundation
import ISO9660

/// Command for listing contents of folders
struct LsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List files and folders"
    )

    @OptionGroup()
    var options: CLI

    @Flag(name: .customShort("R"), help: "Recursively traverse subdirectories")
    var recursive: Bool = false

    @Flag(name: .customShort("l"), help: "List files in the long format")
    var longListing: Bool = false

    @Flag(name: .customShort("a"), help: "Include hidden files")
    var includeHidden: Bool = false

    @Flag(name: .long, help: "Do not use alternate name (NM) extension")
    var ignoreAlternateName: Bool = false

    @Argument
    var path: String = "/"

    mutating func run() throws {
        do {
            let fs = options.fs
            let dir = try options.getFSEntry(path)
            try listDirectory(fs, dir, path)
        } catch {
            print("Error: \(error)")
            Thread.callStackSymbols.forEach{print($0)}
            Foundation.exit(EXIT_FAILURE)
        }
    }

    /// List the contents of `directory`
    func listDirectory(_ fs: ISOFileSystem, _ directory: FSEntry, _ path: String) throws {
        var lines: [[String]] = []
        var maxLinksLen = 0
        var maxUidLen = 0
        var maxGidLen = 0
        var maxSizeLen = 0
        var maxNameLen = 0
        let hasColor = (ProcessInfo.processInfo.environment["TERM"]?.contains("color") ?? false)
            && isatty(STDOUT_FILENO) == 1
        var directories: [FSEntry] = []
        for child in try fs.list(directory: directory) {
            if !includeHidden && child.name.starts(with: ".") {
                continue
            }
            let metadata = child.metadata
            let permissions = child.permissions
            let links = String(format: "%d", metadata?.links ?? 0)
            let uid = uidToName(metadata?.uid ?? 0)
            let gid = gidToName(metadata?.gid ?? 0)
            let size = String(format: "%d", metadata?.length ?? 0)
            let mDate = metadata?.modificationDate ?? Date(timeIntervalSince1970: 0)
            let df = DateFormatter()
            df.dateFormat = "LLL"
            let mTimeMonth = df.string(from: mDate)
            df.dateFormat = "d HH:mm"
            let mtime = mTimeMonth + " " + df.string(from: mDate).rightFit(8)
            if links.count > maxLinksLen {
                maxLinksLen = links.count
            }
            if uid.count > maxUidLen {
                maxUidLen = uid.count
            }
            if gid.count > maxGidLen {
                maxGidLen = gid.count
            }
            if size.count > maxSizeLen {
                maxSizeLen = size.count
            }
            if child.name.count > maxNameLen {
                maxNameLen = child.name.count
            }
            var colour = ""
            if hasColor {
                if child.isDirectory {
                    colour = "\u{001B}[1;34m"
                    // coloredName = "\u{001B}[1;34m\(child.name)\u{001B}[0m"
                } else if case .symlink = child {
                    colour = "\u{001B}[1;35m"
                    // coloredName = "\u{001B}[1;35m\(child.name)\u{001B}[0m"
                }
            }
            let symlinkTarget: String
            if case .symlink(_, let target, _) = child {
                symlinkTarget = " -> \(target)"
            } else {
                symlinkTarget = ""
            }
            let name = ignoreAlternateName ? child.nameInVolDescriptor : child.name
            lines.append([permissions, links, uid, gid, size, mtime, name, colour, symlinkTarget])
            if case .directory = child {
                directories.append(child)
            }
        }
        var numPerRow = 0
        if !longListing {
            var w = winsize()
            if ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0 {
                numPerRow = Int(w.ws_col) / (maxNameLen + 1)
            }
        }
        var newLinePrinted = true
        for (idx, line) in lines.enumerated() {
            let permissions = line[0]
            let links = line[1].rightFit(maxLinksLen)
            let uid = line[2].rightFit(maxUidLen)
            let gid = line[3].rightFit(maxGidLen)
            let size = line[4].rightFit(maxSizeLen)
            let mtime = line[5]
            let name = line[6]
            let colour = line[7]
            let symlinkTarget = line[8]
            let endColour = colour.isEmpty ? "" : "\u{001B}[0m"
            if longListing {
                print("\(permissions) \(links) \(uid) \(gid) \(size) \(mtime) \(colour)\(name)\(endColour)\(symlinkTarget)")
            } else {
                if numPerRow > 0 {
                    newLinePrinted = false
                    print("\(colour)\(name.padding(toLength: maxNameLen, withPad: " ", startingAt: 0))\(endColour)", terminator: " ")
                    if idx % numPerRow == numPerRow - 1 {
                        print("")
                        newLinePrinted = true
                    }
                } else {
                    print("\(colour)\(name)\(endColour)")
                }
            }
        }
        if !newLinePrinted {
            print("")
        }

        // recursively traverse the directory if required
        if recursive {
            for dir in directories {
                let fullPath = path.last == "/" ? path + dir.name : path + "/" + dir.name
                print("")
                print("\(fullPath):")
                try listDirectory(fs, dir, fullPath)
            }
        }
    }
}

extension FSEntry {
    var permissions: String {
        let type: String
        let mode = metadata?.mode ?? 0
        let ownerPermissions = (mode & 0o400 == 0 ? "-" : "r") + (mode & 0o200 == 0 ? "-" : "w") + (mode & 0o4000 != 0 ? "s" : mode & 0o100 == 0 ? "-" : "x")
        let groupPermissions = (mode & 0o40 == 0 ? "-" : "r") + (mode & 0o20 == 0 ? "-" : "w") + (mode & 0o2000 != 0 ? "s" : mode & 0o10 == 0 ? "-" : "x")
        let otherPermissions = (mode & 0o4 == 0 ? "-" : "r") + (mode & 0o2 == 0 ? "-" : "w") + (mode & 0o1 == 0 ? "-" : "x")
        switch self {
        case .currentDirectory, .parentDirectory, .directory:
            type = "d"
        case .file:
            type = "-"
        case .symlink:
            type = "l"
        }
        return "\(type)\(ownerPermissions)\(groupPermissions)\(otherPermissions)"
    }
}

private func uidToName(_ uid: Int) -> String {
    return getpwuid(uid_t(uid)).map{String(cString: $0.pointee.pw_name)} ?? String(uid)
}

private func gidToName(_ gid: Int) -> String {
    return getgrgid(gid_t(gid)).map{String(cString: $0.pointee.gr_name)} ?? String(gid)
}

private extension String {
    func rightFit(_ length: Int) -> String {
        if length < count {
            return String(self[..<self.index(self.startIndex, offsetBy: length)])
        }
        else if length < count {
            return self
        } else {
            return String(repeating: " ", count: Swift.max(0, length - count)) + self
        }
    }
}

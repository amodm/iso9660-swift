import Foundation

/// A single SUSP Entry. A set of these entries is stored in a contiguous block of data, which is referred to as a
/// **SUSP Continuation**. A set of these continuations logically constitutes a ``SUSPArea``.
///
/// This has the general format of `<signature> <len> <version> <data>`, where:
/// - `signature` is a 2-byte string identifying the type of SUSP entry
/// - `len` is a 1-byte number, representing the length of this SUSP entry, including the signature, length, and version fields
/// - `version` is a 1-byte number, representing the version of the SUSP entry
/// - `data` is a string of bytes representing the type specific data
///
/// Also see: ``SUSPArea`` and the [spec](https://studylib.net/doc/18849138/ieee-p1281-system-use-sharing-protocol-draft)
public enum SUSPEntry: Equatable {
    /// Tags that are defined directly in the SUSP standard
    public enum SUSP: Equatable {
        /// CE: Continuation Area: This SUSP entry is used to continue a SUSP entry that is too large to fit in a single System Use Entry.
        ///
        /// Format: `<CE> <len> <version> <block-4B-LSB-MSB> <offset-4B-LSB-MSB> <length-of-cont-4B-LSB-MSB>`
        case CE(block: UInt32, offset: UInt32, length: UInt32)

        /// PD: SUSP Padding Field: This SUSP entry is used to pad a System Use Entry to a 2-byte boundary.
        ///
        /// Format: `<SP> <len> <version> <padding-bytes>`
        case PD(padLength: UInt8)

        /// SP: SUSP Sharing Protocol: This SUSP entry is used to specify the location of the SUSP sharing protocol data.
        ///
        /// Format: `<SP> <len> <version> <0xbe> <0xef> <len-skip=0>`
        case SP(lengthToSkip: UInt8 = 0)

        /// ST: SUSP Terminator: Used to terminate a System Use Entry.
        ///
        /// Format: `<ST> <len=4> <version>`
        case ST
    }

    /// Tags that are defined in the Rock Ridge standard: https://archive.org/details/enf_pobox_Rrip/page/n11/mode/2up
    public enum RockRidge: Equatable {
        /// PX: Posix file attributes. Format: `<PX> <len=36/44> <version> <fileMode> <links> <uid> <gid> <serial?>`. The `fileMode`
        /// has the same bit-format as defined in POSIX IEEE 1003.1, so things like `S_IRUSR` can be used for bit-checking.
        ///
        /// Implementation note: In practice, there seems to be two kinds of this in the wild:
        /// - Length 36: this is as per [draft rev 1.10](https://archive.org/details/enf_pobox_Rrip/page/n13/mode/2up)
        /// - Length 44: this is as per [draft rev 1.12](https://web.archive.org/web/20170404043745/http://www.ymi.com/ymi/sites/default/files/pdf/Rockridge.pdf)
        ///
        /// We support both, by making `serial` optional.
        case PX(fileMode: UInt32, links: UInt32, uid: UInt32, gid: UInt32, serial: UInt32? = nil)

        /// PN: POSIX device numbers. Format: `<PN> <len=8> <version> <high> <low>`
        case PN(high: UInt32, low: UInt32)

        /// SL: Symbolic link. Format: `<SL> <len> <version> <flags> <components...>`. The `continuesInNext` flag indicates whether this
        /// entry continues in the next `SL` entry. Use ``Symlink`` to assemble the components into a single symlink.
        case SL(continuesInNext: Bool, recordsData: Data)

        /// NM: Alternate name. Multiple such NM entry may exist for the same directory record, in which case all of them need to be
        /// appended to get the final name.
        ///
        /// Format: `<NM> <len> <version> <flags> <name>`. The `name` is a `Data` because the encoding is determined by the OS, not the standard.
        case NM(flags: UInt8, name: Data)

        /// TF: Timestamps. Format: `<TF> <len> <version> <flags> <timestamps>`
        case TF(createdAt: Date? = nil, modifiedAt: Date? = nil, accessedAt: Date? = nil, attributesChangedAt: Date? = nil, backedupAt: Date? = nil, expirationAt: Date? = nil, effectiveAt: Date? = nil, longForm: Bool = false)

        /// SF: Sparse File. Format: `<SF> <len=12> <version> <virtual-file-size>`
        case SF(virtualFileSize: UInt32) // TODO: needs appropriate support in ISOFileSystem for sparse files

        /// RR: Rock Ridge. Format: `<RR> <len=5> <version>`
        case RR

        public enum NamedComponent: Equatable {
            case currentDirectory
            case parentDirectory
            case rootDirectory
            case volumeRoot
            case host
            /// A named component. We use `Data` here instead of `String` because the encoding is determined by the OS, not the standard.
            case named(Data)
        }

        /// A symbolic link. This is a convenience type that assembles the components of a symlink from all component entry inside a single
        /// `SL` entry, as well as components that are split across multiple `SL` entry.
        public class Symlink {
            public private(set) var data: Data
            public private(set) var isComplete: Bool
            private var componentContinuation: Bool

            /// The components of the symlink. This is a convenience property that assembles the components from all component entry inside
            public var components: [NamedComponent] {
                var components: [NamedComponent] = []
                var offset = data.startIndex
                var previousComponentContinuation: Data? = nil
                while offset < data.endIndex {
                    // we get the flags & length of the immediate component
                    let compFlags = data[offset]
                    let compLen = data[offset + 1]
                    offset += 2

                    if compFlags & 0x2 != 0 {
                        components.append(.currentDirectory)
                        previousComponentContinuation = nil
                    } else if compFlags & 0x4 != 0 {
                        components.append(.parentDirectory)
                        previousComponentContinuation = nil
                    } else if compFlags & 0x8 != 0 {
                        components.append(.rootDirectory)
                        previousComponentContinuation = nil
                    } else if compFlags & 0x10 != 0 {
                        components.append(.volumeRoot)
                        previousComponentContinuation = nil
                    } else if compFlags & 0x20 != 0 {
                        components.append(.host)
                        previousComponentContinuation = nil
                    } else {
                        let range = offset ..< offset + Int(compLen)
                        let thisData = data.subdata(in: range)
                        // if this entry is incomplete
                        if compFlags & 0x1 != 0 {
                            // let's store it as such and continue
                            previousComponentContinuation = previousComponentContinuation == nil ? thisData : (previousComponentContinuation! + thisData)
                        } else {
                            // else we handle it as a normal component
                            // but first we need to check if we're carrying from a previous component
                            if let pcc = previousComponentContinuation {
                                // we are, so let's add it to the current component data
                                components.append(.named(pcc + thisData))
                                previousComponentContinuation = nil
                            } else {
                                // else just add the current data as-is
                                components.append(.named(thisData))
                            }
                        }
                    }
                    offset += Int(compLen)
                }
                return components
            }

            /// Creates a new symlink from a single SL entry. If `entry` is not an SL entry, this initializer returns `nil`.
            /// More SL entries can be added if this `entry` is not complete on its own.
            init?(_ entry: SUSPEntry) {
                switch entry {
                case .rrip(.SL(let continuesInNext, let data)):
                    self.isComplete = !continuesInNext
                    self.componentContinuation = continuesInNext
                    self.data = data
                default:
                    return nil
                }
            }

            /// Adds another SL entry to the symlink for assembly.
            /// - Parameter entry: The SL entry to add.
            func add(from entry: SUSPEntry) {
                if isComplete {
                    return
                }

                switch entry {
                case .rrip(.SL(let continuesInNext, let data)):
                    self.isComplete = !continuesInNext
                    self.data += data
                default:
                    return
                }
            }

            /// Create a new SL entry from a name and target.
            static func newSL(name: String, target: String, encoding: String.Encoding = .utf8) -> SUSPEntry {
                var recordsData = Data()
                let pathComponents: [String]
                if target.starts(with: "//") {
                    pathComponents = ["//"] + target.pathComponents
                } else if target.starts(with: "/") {
                    pathComponents = ["/"] + target.pathComponents
                } else {
                    pathComponents = target.pathComponents
                }
                for component in pathComponents {
                    if component == "." {
                        recordsData.append(Data([2, 0]))
                    } else if component == ".." {
                        recordsData.append(Data([4, 0]))
                    } else if component == "/" {
                        recordsData.append(Data([8, 0]))
                    } else if component == "//" {
                        recordsData.append(Data([16, 0]))
                    } else {
                        let componentData = component.data(using: encoding)!
                        recordsData.append(Data([0, UInt8(componentData.count)]) + componentData)
                    }
                }
                return .rrip(.SL(continuesInNext: false, recordsData: recordsData))
            }
        }

        /// An Alternate Name. This is a convenience type that assembles the components of NM from potentially multiple NM entries.
        public class AlternateName {
            public private(set) var data: Data
            public private(set) var isComplete: Bool
            private var specialNameType: NamedComponent? = nil

            /// The full alternate name as byte buffer. This is a convenience property that assembles the names from multiple NM
            /// fields if provided.
            public var name: NamedComponent {
                if let specialNameType = specialNameType {
                    return specialNameType
                }
                return .named(data)
            }

            /// Creates a new AlternateName from a single NM entry. If `entry` is not a NM entry, this initializer returns `nil`.
            /// More NM entries can be added if this `entry` is not complete on its own.
            init?(_ entry: SUSPEntry) {
                switch entry {
                case .rrip(.NM(let flags, let name)):
                    self.isComplete = flags & 0x1 == 0
                    if flags & 0x2 != 0 {
                        self.specialNameType = .currentDirectory
                    } else if flags & 0x4 != 0 {
                        self.specialNameType = .parentDirectory
                    } else if flags & 0x20 != 0 {
                        self.specialNameType = .host
                    } else {
                        self.specialNameType = nil
                    }
                    if self.specialNameType != nil {
                        self.isComplete = true // we also mark things as complete if it's a special name
                    }
                    self.data = name
                default:
                    return nil
                }
            }

            /// Adds another NM entry to this for assembly.
            /// - Parameter entry: The NM entry to add.
            func add(from entry: SUSPEntry) {
                if isComplete {
                    return
                }

                switch entry {
                case .rrip(.NM(let flags, let name)):
                    self.isComplete = flags & 0x1 == 0
                    self.data += name
                default:
                    return
                }
            }
        }
    }

    /// SUSP entry
    case susp(SUSP)
    /// Rock Ridge entry
    case rrip(RockRidge)
    /// Any other SUSP entry for which we don't yet have a specific type defined
    case other(Data)

    /// Signature of this entry
    var signature: String {
        switch self {
        case .susp(let susp):
            switch susp {
            case .CE:
                return "CE"
            case .PD:
                return "PD"
            case .SP:
                return "SP"
            case .ST:
                return "ST"
            }
        case .rrip(let rrip):
            switch rrip {
            case .PX:
                return "PX"
            case .PN:
                return "PN"
            case .SL:
                return "SL"
            case .NM:
                return "NM"
            case .TF:
                return "TF"
            case .SF:
                return "SF"
            case .RR:
                return "RR"
            }
        case .other(let data):
            return String(data: data[(0..<2).inc(by: data.startIndex)], encoding: .ascii) ?? "??"
        }
    }

    /// Version of this entry
    var version: UInt8 {
        switch self {
        case .other(let data):
            return data[data.startIndex + 2]
        default:
            return 1
        }
    }

    /// Serialized bytes of this entry, including the signature, length, version and body
    /// - Returns: The serialized bytes of this entry
    func serialize() -> Data {
        let bodyBytes: Data
        switch self {
        case .susp(let susp):
            switch susp {
            case .CE(let block, let offset, let length):
                bodyBytes = block.bothEndianBytes + offset.bothEndianBytes + length.bothEndianBytes
            case .PD(let padLength):
                bodyBytes = Data(count: Int(padLength))
            case .SP(let lengthToSkip):
                bodyBytes = Data([0xbe, 0xef, UInt8(lengthToSkip)])
            case .ST:
                bodyBytes = Data()
            }
        case .rrip(let rrip):
            switch rrip {
            case .PX(let fileMode, let links, let uid, let gid, let serial):
                bodyBytes = fileMode.bothEndianBytes + links.bothEndianBytes + uid.bothEndianBytes + gid.bothEndianBytes + (serial?.bothEndianBytes ?? Data())
            case .PN(let high, let low):
                bodyBytes = high.bothEndianBytes + low.bothEndianBytes
            case .SL(let continuesInNext, let recordsData):
                bodyBytes = [continuesInNext ? 1 : 0] + recordsData
            case .NM(let flags, let name):
                bodyBytes = [flags] + name
            case .TF(let createdAt, let modifiedAt, let accessedAt, let attributesChangedAt, let backedupAt, let expirationAt, let effectiveAt, let longform):
                let numEntries = (createdAt != nil ? 1 : 0) + (modifiedAt != nil ? 1 : 0) + (accessedAt != nil ? 1 : 0) 
                    + (attributesChangedAt != nil ? 1 : 0) + (backedupAt != nil ? 1 : 0) + (expirationAt != nil ? 1 : 0) 
                    + (effectiveAt != nil ? 1 : 0)
                let entrySize = longform ? 17 : 7
                var data = Data(count: 1 + numEntries * entrySize)
                var idx = 0
                var tfIdx = 0
                let df = { (date: Date?) in
                    let start = 1 + tfIdx * entrySize
                    if let date = date {
                        data[data.startIndex] |= UInt8(1 << idx)
                        data.replaceSubrange(start..<start+entrySize, with: longform ? date.iso9660Format17B : date.iso9660Format7B)
                        tfIdx += 1
                    }
                    idx += 1
                }
                df(createdAt)
                df(modifiedAt)
                df(accessedAt)
                df(attributesChangedAt)
                df(backedupAt)
                df(expirationAt)
                df(effectiveAt)

                bodyBytes = data
            case .SF(let virtualFileSize):
                bodyBytes = virtualFileSize.bothEndianBytes
            case .RR:
                bodyBytes = Data()
            }
        case .other(let data):
            return data
        }

        return signature.data(using: .ascii)! + [UInt8(4 + bodyBytes.count), version] + bodyBytes
    }

    /// Deserializes the set of SUSP entries from `data`.
    /// - Parameter data: The data to deserialize.
    /// - Returns: The set of SUSP entries
    static func deserialize(from data: Data) -> [SUSPEntry] {
        var entries = [SUSPEntry]()
        guard data.count >= 4 else {
            return entries
        }

        var offset = data.startIndex
        while offset <= data.endIndex - 4 {
            guard let signature = String(data: data[(0..<2).inc(by: offset)], encoding: .ascii) else {
                break
            }
            let length = data[offset + 2]
            guard length >= 4 && data.endIndex >= offset + Int(length) else {
                break
            }
            defer {
                offset += Int(length)
            }
            // let version = data[offset + 3]
            let bodyOffset = offset + 4
            let body = data[(4..<Int(length)).inc(by: offset)]
            switch signature {
            case "CE":
                guard body.count >= 12 else {
                    continue
                }
                let block = UInt32(fromBothEndian: body[(0..<8).inc(by: bodyOffset)])
                let offset = UInt32(fromBothEndian: body[(8..<16).inc(by: bodyOffset)])
                let length = UInt32(fromBothEndian: body[(16..<24).inc(by: bodyOffset)])
                entries.append(.susp(.CE(block: block, offset: offset, length: length)))
            case "PD":
                entries.append(.susp(.PD(padLength: UInt8(body.count))))
            case "SP":
                guard body.count >= 3 && body[bodyOffset] == 0xbe && body[bodyOffset + 1] == 0xef else {
                    continue
                }
                let lengthToSkip = body[bodyOffset + 2]
                entries.append(.susp(.SP(lengthToSkip: lengthToSkip)))
            case "ST":
                entries.append(.susp(.ST))
                break // the rest of the data does not contain any SUSP entries
            case "PX":
                guard body.count >= 20 else {
                    continue
                }
                let fileMode = UInt32(fromBothEndian: body[(0..<8).inc(by: bodyOffset)])
                let links = UInt32(fromBothEndian: body[(8..<16).inc(by: bodyOffset)])
                let uid = UInt32(fromBothEndian: body[(16..<24).inc(by: bodyOffset)])
                let gid = UInt32(fromBothEndian: body[(24..<32).inc(by: bodyOffset)])
                let serial = length >= 44 ? UInt32(fromBothEndian: body[(32..<40).inc(by: bodyOffset)]) : nil
                entries.append(.rrip(.PX(fileMode: fileMode, links: links, uid: uid, gid: gid, serial: serial)))
            case "PN":
                guard body.count >= 8 else {
                    continue
                }
                let high = UInt32(fromBothEndian: body[(0..<8).inc(by: bodyOffset)])
                let low = UInt32(fromBothEndian: body[(8..<16).inc(by: bodyOffset)])
                entries.append(.rrip(.PN(high: high, low: low)))
            case "SL":
                guard body.count >= 1 else {
                    continue
                }
                let continuesInNext = body[bodyOffset] & 0x1 != 0
                let recordsData = Data(body[(1..<body.count).inc(by: bodyOffset)])
                entries.append(.rrip(.SL(continuesInNext: continuesInNext, recordsData: recordsData)))
            case "NM":
                guard body.count >= 2 else {
                    continue
                }
                let flags = body[bodyOffset]
                let name = Data(body[(bodyOffset+1)...])
                entries.append(.rrip(.NM(flags: flags, name: name)))
            case "TF":
                guard body.count >= 22 else {
                    continue
                }
                let flags = body[bodyOffset]
                let tl = flags & 0x80 != 0 ? 17 : 7
                let tf: ISO9660DateFormat = tl == 17 ? .format17B : .format7B
                var tsIdx = 0
                let df = { (idx: Int) -> Date? in
                    if flags & (1 << idx) == 0 {
                        return nil
                    }
                    let start = 1 + tsIdx * tl + bodyOffset
                    let end = start + tl
                    guard end <= body.endIndex else {
                        return nil
                    }
                    tsIdx += 1
                    return Date.decode(from: body[start ..< end], format: tf)
                }
                entries.append(.rrip(.TF(createdAt: df(0), modifiedAt: df(1), accessedAt: df(2), attributesChangedAt: df(3), backedupAt: df(4), expirationAt: df(5), effectiveAt: df(6), longForm: tf == .format17B)))
            case "SF":
                guard body.count >= 8 else {
                    continue
                }
                entries.append(.rrip(.SF(virtualFileSize: UInt32(fromBothEndian: body[(0..<8).inc(by: bodyOffset)]))))
            case "RR":
                entries.append(.rrip(.RR))
            default:
                entries.append(.other(data[(0..<Int(length)).inc(by: offset)]))
            }
        }

        return entries
    }

    /// If this entry is splittable at `threshold` or before, split it and return the first and the second parts, else return nil.
    /// - Parameter threshold: The max byte position at which to consider splitting.
    /// - Returns: A tuple containing the first and the second parts, if split was successful, else nil.
    func splitAt(lessThanOrEqualTo threshold: Int) -> (SUSPEntry, SUSPEntry)? {
        switch self {
        // RRIP - SL
        case .rrip(.SL(let cin, let recordsData)):
            let headerLen = 5 // 'SL' (2-bytes) + len (1-byte) + version (1-byte) + flags (1-bytes)
            let threshold = threshold - headerLen // we need to reduce threshold to account for header length

            var idx = recordsData.startIndex, prevIdx = -1
            while idx < recordsData.endIndex - 1 {
                let componentFlags = recordsData[idx] // current component flags
                let componentLen = recordsData[idx + 1] // current component length
                let nextIdx = idx + 2 + Int(componentLen) // index of next component
                let lenThatCanBeIncludedInFirst = threshold - (idx + 2)

                if lenThatCanBeIncludedInFirst >= componentLen {
                    // this component can be fully included in `first`
                    if nextIdx >= recordsData.count - 1 {
                        // this is the last component, and can be fully included, so we can just return ourselves
                        let first: SUSPEntry = .rrip(.SL(continuesInNext: cin, recordsData: recordsData))
                        let second: SUSPEntry = .rrip(.SL(continuesInNext: cin, recordsData: Data()))
                        return (first, second)
                    } else if nextIdx > threshold - 2 {
                        // this is the last component that can be fully included, so we can return the first part
                        let first: SUSPEntry = .rrip(.SL(continuesInNext: true, recordsData: recordsData[recordsData.startIndex..<nextIdx]))
                        let second: SUSPEntry = .rrip(.SL(continuesInNext: cin, recordsData: recordsData[nextIdx...]))
                        return (first, second)
                    } else {
                        // we're not the last component, so let's continue to iterate
                        prevIdx = idx
                        idx = nextIdx
                        continue
                    }
                } else if lenThatCanBeIncludedInFirst > 0 {
                    // this component can be partially included in `first`
                    var firstData = recordsData[recordsData.startIndex..<(idx + 2 + lenThatCanBeIncludedInFirst)]
                    firstData[idx] |= 1 // mark this continuation as to be continued
                    firstData[idx + 1] = UInt8(lenThatCanBeIncludedInFirst) // update the length
                    let first: SUSPEntry = .rrip(.SL(continuesInNext: true, recordsData: firstData))

                    let secondData = Data([componentFlags, componentLen - UInt8(lenThatCanBeIncludedInFirst)]) + recordsData[(idx + 2 + lenThatCanBeIncludedInFirst)...]
                    let second: SUSPEntry = .rrip(.SL(continuesInNext: cin || nextIdx < recordsData.count - 1, recordsData: secondData))
                    return (first, second)
                } else {
                    // this component cannot be included in `first`
                    if prevIdx >= 0 {
                        // but there is a previous component which can be, so we can return the first part
                        let first: SUSPEntry = .rrip(.SL(continuesInNext: true, recordsData: Data(recordsData[recordsData.startIndex..<prevIdx])))
                        let second: SUSPEntry = .rrip(.SL(continuesInNext: cin, recordsData: Data(recordsData[prevIdx...])))
                        return (first, second)
                    } else {
                        // there is no previous component which can be included, so we can't split
                        return nil
                    }
                }
            }
            return nil

        // RRIP - NM
        case .rrip(.NM(let flags, let name)):
            let lenThatCanBeIncludedInFirst = threshold - 5 // 'NM' (2-bytes) + len (1-byte) + version (1-byte) + flags (1-bytes)
            if lenThatCanBeIncludedInFirst >= name.count {
                // name can be fully included in `first`
                let first: SUSPEntry = .rrip(.NM(flags: flags & ~1, name: name)) // we set the continue flag
                let second: SUSPEntry = .rrip(.NM(flags: 0, name: Data())) // this is just a placeholder
                return (first, second)
            } else if lenThatCanBeIncludedInFirst > 0 {
                // this component can be partially included in `first`
                let first: SUSPEntry = .rrip(.NM(flags: flags | 1, name: Data(name[..<(name.startIndex+lenThatCanBeIncludedInFirst)])))
                let second: SUSPEntry = .rrip(.NM(flags: flags, name: Data(name[(name.startIndex+lenThatCanBeIncludedInFirst)...])))
                return (first, second)
            } else {
                // this component cannot be included in `first`
                return nil
            }
        default:
            return nil
        }
    }
}

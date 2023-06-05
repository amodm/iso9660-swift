import Foundation

/// A single SUSP Area, representing a complete SUSP information set for a single ``DirectoryRecord``. This may not necessarily be stored
/// contiguously, but instead is a logical concatenation of multiple _continuations_, each of which is a contiguous region of SUSP data,
/// but stored in distinct regions. Each continuation contains a set of serialized ``SUSPEntry``s. The link between these disinct
/// continuations is achieved via ``SUSPEntry.SUSP.CE`` entries.
///
/// [SUSP (System Use Sharing Protocol)](https://studylib.net/doc/18849138/ieee-p1281-system-use-sharing-protocol-draft) is a protocol for
/// specifying how the System Use Field of an ISO 9660 directory record is to be interpreted.
public struct SUSPArea {
    private var data: Data

    /// If not nil, represents where the next continuation is located.
    public private(set) var continuesAt: (block: UInt32, offset: UInt32, length: UInt32)?

    /// Returns true if this ``SUSPArea`` is complete, i.e. there are no more continuations needed to complete the SUSP information.
    public var isComplete: Bool {
        return continuesAt == nil
    }

    /// The [SUSPEntry] list for this ``SUSPArea``.
    public var entries: [SUSPEntry] {
        return SUSPEntry.deserialize(from: Self.compact(data))
    }

    /// Creates a new ``SUSPArea`` from a given SUSP continuation data. If the data does not contain valid SUSP entries, returns nil.
    /// - Parameter continuation: The data from which to create the ``SUSPArea``
    public init?(continuation: Data?) {
        guard let continuation = continuation else {
            return nil
        }

        let entries = SUSPEntry.deserialize(from: continuation)
        if entries.isEmpty {
            return nil
        }

        var continuesAt: (block: UInt32, offset: UInt32, length: UInt32)? = nil
        for entry in entries {
            if case .susp(.CE(let block, let offset, let length)) = entry {
                continuesAt = (block, offset, length)
                break
            }
        }
        let data = continuesAt == nil ? Self.compact(continuation, entries) : continuation
        if data.isEmpty {
            return nil
        }
        self.data = data
        self.continuesAt = continuesAt
    }

    /// Adds a new SUSP `continuation` to the current data. If the continuation is invalid, or does not contain any SUSP entries,
    /// returns false, else returns true.
    /// - Parameter continuation: The continuation to add
    /// - Returns: True if the continuation was added, else false (can happen if `continuation` is invalid, or if we're already complete)
    public mutating func add(continuation: Data) -> Bool {
        if isComplete {
            return false
        }

        let entries = SUSPEntry.deserialize(from: continuation)
        if entries.isEmpty {
            return false
        }
        var foundCE = false
        for entry in entries {
            if case .susp(.CE(let block, let offset, let length)) = entry {
                if continuesAt!.block == block && continuesAt!.offset + continuesAt!.length == offset {
                    return false // we got the same data as before?
                } else {
                    continuesAt = (block, offset, length)
                    foundCE = true
                }
            }
        }
        if !foundCE {
            continuesAt = nil
        }
        self.data.append(continuation)

        return true
    }

    /// Compacts the data, i.e. merges all the ``SUSPEntry``s into a single contiguous region, and returns it.
    /// - Parameter data: The data to compact
    /// - Parameter entries: The pre-processed list of ``SUSPEntry``, if available, else is generated from current data.
    /// - Returns: The compacted data
    private static func compact(_ data: Data, _ entries: [SUSPEntry]? = nil) -> Data {
        var validEntries: [SUSPEntry] = []
        var expectingMoreNM = true
        var expectingMoreSL = true
        var tfAdded = false
        let entries = entries ?? SUSPEntry.deserialize(from: data)
        for entry in entries {
            let skip: Bool
            switch entry {
            case .susp(.CE(_, _, _)), .susp(.ST), .susp(.PD):
                skip = true
            case .rrip(.SL(let continuesInNext, let recordsData)):
                if expectingMoreSL {
                    expectingMoreSL = continuesInNext
                    var prevExisting = false
                    for idx in 0..<validEntries.count {
                        if case .rrip(.SL(_, let prevData)) = validEntries[idx] {
                            validEntries[idx] = SUSPEntry.rrip(SUSPEntry.RockRidge.SL(continuesInNext: continuesInNext, recordsData: prevData + recordsData))
                            prevExisting = true
                            break
                        }
                    }
                    skip = prevExisting
                } else {
                    skip = true
                }
            case .rrip(.NM(let flags, let name)):
                if expectingMoreNM {
                    expectingMoreNM = flags & 0x1 != 0
                    var prevExisting = false
                    for idx in 0..<validEntries.count {
                        if case .rrip(.NM(let prevFlags, let prevName)) = validEntries[idx] {
                            let newFlags = expectingMoreNM ? prevFlags : (prevFlags & ~0x1)
                            validEntries[idx] = SUSPEntry.rrip(SUSPEntry.RockRidge.NM(flags: newFlags, name: prevName + name))
                            prevExisting = true
                            break
                        }
                    }
                    skip = prevExisting
                } else {
                    skip = true
                }
            case .rrip(.TF(let oldCreatedAt, let oldModifiedAt, let oldAccessedAt, let oldAttributesChangedAt, let oldBackedupAt, let oldExpirationAt, let oldEffectiveAt, let oldLongform)):
                if tfAdded {
                    for idx in 0..<validEntries.count {
                        if case .rrip(.TF(let createdAt, let modifiedAt, let accessedAt, let attributesChangedAt, let backedupAt, let expirationAt, let effectiveAt, _)) = validEntries[idx] {
                            validEntries[idx] = SUSPEntry.rrip(SUSPEntry.RockRidge.TF(
                                createdAt: createdAt ?? oldCreatedAt,
                                modifiedAt: modifiedAt ?? oldModifiedAt,
                                accessedAt: accessedAt ?? oldAccessedAt,
                                attributesChangedAt: attributesChangedAt ?? oldAttributesChangedAt,
                                backedupAt: backedupAt ?? oldBackedupAt,
                                expirationAt: expirationAt ?? oldExpirationAt,
                                effectiveAt: effectiveAt ?? oldEffectiveAt,
                                longForm: oldLongform
                            ))
                            break
                        }
                    }
                    tfAdded = true
                    skip = true
                } else {
                    skip = false
                }
            default:
                skip = false
            }
            if !skip {
                validEntries.append(entry)
            }
        }
        if validEntries.isEmpty {
            return Data()
        } else {
            return validEntries.map { $0.serialize() }.reduce(Data(), +)
        }
    }

    /// Length of a ``SUSPEntry.susp.CE`` entry, in bytes.
    internal static let CE_LEN = 28

    /// Serialize this SUSP Area into bytes. For the reason behind the convoluted signature, see Discussion section.
    /// - Parameter firstContinuationSize: The maximum size of the first continuation, in bytes.
    /// - Parameter allocator: A closure that this function uses to allocate blocks for continuations beyond the first one.
    /// - Result: A tuple containing the first continuation, and a list of continuations (and locations) beyond the first one.
    ///
    /// A SUSP Area is usually created by repurposing the ``DirectoryRecord.systemUse`` field, which is size constrained
    /// becaue the maximum size of a ``DirectoryRecord`` can be 256 bytes, at least 34 bytes of which is taken up by other
    /// fields. If the whole SUSP Area fits into `firstContinuationSize` bytes, that's great, else we have to split up
    /// the area into multiple continuations, where each except the last one has a _CE_ entry pointing to the location
    /// of the next one. We do this by making space requests to `allocator`.
    ///
    /// TODO: Current implementation is very fragile, and not easy to understand. It needs to be refactored.
    internal func serialize(
        _ firstContinuationSize: UInt32,
        _ allocator: (_ requestedSize: UInt32) -> (block: UInt32, offset: UInt32, length: UInt32)
    ) -> (first: Data, continuations: [(block: UInt32, offset: UInt32, data: Data)]) {
        if data.isEmpty {
            return (first: data, continuations: [])
        }

        // parse the data into SUSP entries
        let compactedData = Self.compact(data)

        // we short circuit if the data fits into the first continuation
        if compactedData.count <= firstContinuationSize {
            return (first: compactedData, continuations: [])
        }
        // or if there are no continuations
        var entries = SUSPEntry.deserialize(from: compactedData)
        if entries.isEmpty {
            return (first: compactedData, continuations: [])
        }

        // now we segregate the continuations
        var bytes = entries.map { $0.serialize() }
        var continuations: [(block: UInt32, offset: UInt32, data: Data)] = []
        var currentMaxLenAllowed = firstContinuationSize
        var currentBlock = UInt32(0)
        var currentOffset = UInt32(0)
        var currentStartIndex = bytes.startIndex

        // at each iteration here, we add a continuation to the list
        while currentStartIndex < bytes.endIndex {
            // we find the last entry that can be included in the current continuation
            var endIndex = currentStartIndex, needsCE = false, endIndexIsFullyContained = false
            while endIndex < bytes.count {
                let lenWithCurrentIdx = bytes[currentStartIndex...endIndex].map { $0.count }.reduce(0, +)
                if lenWithCurrentIdx + Self.CE_LEN >= currentMaxLenAllowed {
                    // from our current position of endIndex, we can no more accommodate the data + a CE entry
                    // but we might be able to accommodate the data without the CE entry, so we check for that
                    let lenToFinish = bytes[currentStartIndex...].map { $0.count }.reduce(0, +)
                    if lenToFinish <= currentMaxLenAllowed {
                        needsCE = false
                        endIndex = bytes.count - 1
                    } else {
                        needsCE = true
                        endIndexIsFullyContained = lenWithCurrentIdx + Self.CE_LEN == currentMaxLenAllowed
                    }
                    break
                } else {
                    // else we just increment and move on to next entry
                    endIndex += 1
                }
            }
            if endIndex == bytes.count {
                endIndex = bytes.count - 1
                needsCE = false
            }
            // from here on, endIndex is pointing to the item being split or the last item which can be included
            // in the current continuation

            if needsCE {
                let data: Data
                let maxLenFirstPart = endIndexIsFullyContained
                    ? 0
                    : Int(currentMaxLenAllowed) - Self.CE_LEN - bytes[currentStartIndex..<endIndex].map { $0.count }.reduce(0, +) // notice the ..<endIndex
                if maxLenFirstPart >= 7 {
                    if let (first, second) = entries[endIndex].splitAt(lessThanOrEqualTo: maxLenFirstPart) {
                        // and fit the first into the continuation
                        data = (endIndex > currentStartIndex ? bytes[currentStartIndex..<endIndex].reduce(Data(), +) : Data()) + first.serialize()

                        // if split is successful, we replace the current entry with the second part, and decrement
                        // endIndex, so that the next iteration starts from the second part.
                        bytes[endIndex] = second.serialize()
                        entries[endIndex] = second
                        endIndex -= 1 // we still have second part of the split to process
                    } else {
                        // we're not able to split the entry, so we try to handle it in the next continuation
                        if endIndex > currentStartIndex {
                            endIndex -= 1
                        }
                        // but if doing this leads us to start from the same index, then we have no choice but to ignore
                        // this entry and move on to the next one
                        if endIndex <= currentStartIndex {
                            currentStartIndex += 1
                            continue
                        } else {
                            data = bytes[currentStartIndex...endIndex].reduce(Data(), +)
                        }
                    }
                } else {
                    data = bytes[currentStartIndex...endIndex].reduce(Data(), +)
                }

                let remainingBytes = bytes[(endIndex + 1)...].reduce(0) { $0 + $1.count }
                let (nextBlock, nextOffset, nextMaxLength) = allocator(UInt32(remainingBytes))
                let ce = SUSPEntry.susp(SUSPEntry.SUSP.CE(block: nextBlock, offset: nextOffset, length: nextMaxLength))
                let dataPlusCE = data + ce.serialize()
                assert(dataPlusCE.count <= currentMaxLenAllowed, "Max length \(currentMaxLenAllowed) breached for SUSP Continuation: \(dataPlusCE.count)")
                continuations.append((block: currentBlock, offset: currentOffset, data: dataPlusCE))
                currentBlock = nextBlock
                currentOffset = nextOffset
                currentMaxLenAllowed = nextMaxLength
                currentStartIndex = endIndex + 1
                continue
            } else {
                // we don't need a CE entry, so we can just break out of the loop and rely on pending data addition
                // to add the remaining data
                break
            }
        }

        // add any pending data
        if currentStartIndex < bytes.count {
            continuations.append((block: currentBlock, offset: currentOffset, data: bytes[currentStartIndex...].reduce(Data(), +)))
        }

        // true-up the CE entries, as their lengths are now known
        for idx in 0..<continuations.count - 1 {
            let ce = SUSPEntry.susp(SUSPEntry.SUSP.CE(block: continuations[idx + 1].block, offset: continuations[idx + 1].offset, length: UInt32(continuations[idx + 1].data.count)))
            let ceStart = continuations[idx].data.count - Self.CE_LEN
            let ceEnd = continuations[idx].data.count
            continuations[idx].data.replaceSubrange(ceStart..<ceEnd, with: ce.serialize())
        }

        // return the results
        return (first: continuations[0].data, continuations: Array(continuations[1...]))
    }
}

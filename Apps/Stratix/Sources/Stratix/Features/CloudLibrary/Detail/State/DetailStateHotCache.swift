// DetailStateHotCache.swift
// Defines detail state hot cache for the CloudLibrary / Detail surface.
//

import StratixModels

struct DetailStateCacheEntry {
    var state: CloudLibraryTitleDetailViewState
    var inputSignature: String
    var accessToken: UInt64
}

struct DetailStateHotCache {
    private(set) var capacity: Int
    private var entries: [TitleID: DetailStateCacheEntry] = [:]
    private var accessCounter: UInt64 = 0

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    var keys: [TitleID] {
        Array(entries.keys)
    }

    func peek(_ titleID: TitleID) -> DetailStateCacheEntry? {
        entries[titleID]
    }

    mutating func touch(_ titleID: TitleID) {
        guard var entry = entries[titleID] else { return }
        accessCounter &+= 1
        entry.accessToken = accessCounter
        entries[titleID] = entry
    }

    mutating func insert(
        state: CloudLibraryTitleDetailViewState,
        for titleID: TitleID,
        inputSignature: String
    ) {
        accessCounter &+= 1
        entries[titleID] = DetailStateCacheEntry(
            state: state,
            inputSignature: inputSignature,
            accessToken: accessCounter
        )
        evictIfNeeded()
    }

    mutating func remove(_ titleID: TitleID) {
        entries.removeValue(forKey: titleID)
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
    }

    mutating func prune(validTitleIDs: Set<TitleID>) {
        entries = entries.filter { validTitleIDs.contains($0.key) }
    }

    mutating func invalidateChangedEntries(currentSignatures: [TitleID: String]) -> [TitleID] {
        var invalidated: [TitleID] = []
        for (titleID, entry) in entries {
            guard let current = currentSignatures[titleID], !current.isEmpty else {
                invalidated.append(titleID)
                continue
            }
            if current != entry.inputSignature {
                invalidated.append(titleID)
            }
        }
        guard !invalidated.isEmpty else { return [] }
        for titleID in invalidated {
            entries.removeValue(forKey: titleID)
        }
        return invalidated
    }

    private mutating func evictIfNeeded() {
        while entries.count > capacity {
            guard let evictionKey = entries.min(by: { $0.value.accessToken < $1.value.accessToken })?.key else {
                break
            }
            entries.removeValue(forKey: evictionKey)
        }
    }
}

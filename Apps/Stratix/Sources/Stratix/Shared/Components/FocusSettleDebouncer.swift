// FocusSettleDebouncer.swift
// Defines focus settle debouncer for the Shared / Components surface.
//

import Foundation
import StratixCore

@MainActor
final class FocusSettleDebouncer {
    private var task: Task<Void, Never>?

    func schedule(
        debounce: UInt64 = StratixConstants.Timing.focusSettleDebounceNanoseconds,
        action: @escaping @MainActor () -> Void
    ) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .nanoseconds(debounce))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

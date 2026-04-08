// TaskRegistry.swift
// Defines task registry.
//

import Foundation

actor TaskRegistry {
    private enum Scope: Hashable {
        case single(String)
        case grouped(String, String)
    }

    private struct Entry {
        let task: Any
        let cancel: @Sendable () -> Void
    }

    private var entries: [Scope: Entry] = [:]

    @discardableResult
    func register<Success>(_ task: Task<Success, Never>, id: String) async -> Task<Success, Never> {
        store(task, for: .single(id))
    }

    @discardableResult
    func register<Success>(
        _ task: Task<Success, Never>,
        group: String,
        key: String
    ) async -> Task<Success, Never> {
        store(task, for: .grouped(group, key))
    }

    func taskOrRegister<Success>(
        id: String,
        makeTask: @Sendable () -> Task<Success, Never>
    ) async -> (task: Task<Success, Never>, inserted: Bool) {
        taskOrRegister(for: .single(id), makeTask: makeTask)
    }

    func taskOrRegister<Success>(
        group: String,
        key: String,
        makeTask: @Sendable () -> Task<Success, Never>
    ) async -> (task: Task<Success, Never>, inserted: Bool) {
        taskOrRegister(for: .grouped(group, key), makeTask: makeTask)
    }

    private func taskOrRegister<Success>(
        for scope: Scope,
        makeTask: @Sendable () -> Task<Success, Never>
    ) -> (task: Task<Success, Never>, inserted: Bool) {
        if let existing = task(for: scope, as: Task<Success, Never>.self) {
            return (existing, false)
        }
        let task = makeTask()
        store(task, for: scope)
        return (task, true)
    }

    func task<Success>(
        id: String,
        as _: Task<Success, Never>.Type = Task<Success, Never>.self
    ) async -> Task<Success, Never>? {
        task(for: .single(id), as: Task<Success, Never>.self)
    }

    func task<Success>(
        group: String,
        key: String,
        as _: Task<Success, Never>.Type = Task<Success, Never>.self
    ) async -> Task<Success, Never>? {
        task(for: .grouped(group, key), as: Task<Success, Never>.self)
    }

    func remove(id: String) async {
        entries[.single(id)] = nil
    }

    func remove(group: String, key: String) async {
        entries[.grouped(group, key)] = nil
    }

    func cancel(id: String) async {
        cancel(scope: .single(id))
    }

    func cancel(group: String, key: String) async {
        cancel(scope: .grouped(group, key))
    }

    func cancelGroup(_ group: String) async {
        for scope in scopes(inGroup: group) {
            guard let entry = entries.removeValue(forKey: scope) else { continue }
            entry.cancel()
        }
    }

    func cancelAll() async {
        let entriesToCancel = entries.values
        entries.removeAll()
        for entry in entriesToCancel {
            entry.cancel()
        }
    }

    private func cancel(scope: Scope) {
        guard let entry = entries.removeValue(forKey: scope) else { return }
        entry.cancel()
    }

    @discardableResult
    private func store<Success>(_ task: Task<Success, Never>, for scope: Scope) -> Task<Success, Never> {
        cancel(scope: scope)
        entries[scope] = Entry(task: task, cancel: { task.cancel() })
        return task
    }

    private func scopes(inGroup group: String) -> [Scope] {
        entries.keys.filter {
            guard case .grouped(let currentGroup, _) = $0 else { return false }
            return currentGroup == group
        }
    }

    private func task<Success>(
        for scope: Scope,
        as _: Task<Success, Never>.Type = Task<Success, Never>.self
    ) -> Task<Success, Never>? {
        entries[scope]?.task as? Task<Success, Never>
    }
}

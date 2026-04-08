// TaskRegistryTests.swift
// Exercises task registry behavior.
//

import Testing
@testable import StratixCore

@MainActor
@Suite(.serialized)
struct TaskRegistryTests {
    actor InvocationCounter {
        private(set) var value = 0

        func increment() {
            value += 1
        }
    }

    @Test
    func cancelSingleTask_marksTaskCancelledAndRemovesIt() async {
        let registry = TaskRegistry()
        let task = await registry.register(
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            },
            id: "single"
        )

        await registry.cancel(id: "single")

        #expect(task.isCancelled)
        #expect(await registry.task(id: "single", as: Task<Void, Never>.self) == nil)
    }

    @Test
    func cancelGroup_cancelsEveryGroupedTask() async {
        let registry = TaskRegistry()
        let first = await registry.register(
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            },
            group: "artwork",
            key: "one"
        )
        let second = await registry.register(
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            },
            group: "artwork",
            key: "two"
        )

        await registry.cancelGroup("artwork")

        #expect(first.isCancelled)
        #expect(second.isCancelled)
        #expect(await registry.task(group: "artwork", key: "one", as: Task<Void, Never>.self) == nil)
        #expect(await registry.task(group: "artwork", key: "two", as: Task<Void, Never>.self) == nil)
    }

    @Test
    func taskOrRegister_concurrentCallersDeduplicateToSingleTask() async {
        let registry = TaskRegistry()
        let counter = InvocationCounter()
        var insertedCount = 0

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    let (task, inserted) = await registry.taskOrRegister(id: "dedupe-test") {
                        Task {
                            await counter.increment()
                            try? await Task.sleep(nanoseconds: 80_000_000)
                            await registry.remove(id: "dedupe-test")
                        }
                    }
                    await task.value
                    return inserted
                }
            }

            for await inserted in group {
                if inserted { insertedCount += 1 }
            }
        }

        #expect(insertedCount == 1)
        #expect(await counter.value == 1)
        #expect(await registry.task(id: "dedupe-test", as: Task<Void, Never>.self) == nil)
    }

    @Test
    func cancelAll_cancelsStandaloneAndGroupedTasks() async {
        let registry = TaskRegistry()
        let standalone = await registry.register(
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            },
            id: "standalone"
        )
        let grouped = await registry.register(
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            },
            group: "prefetch",
            key: "cover"
        )

        await registry.cancelAll()

        #expect(standalone.isCancelled)
        #expect(grouped.isCancelled)
        #expect(await registry.task(id: "standalone", as: Task<Void, Never>.self) == nil)
        #expect(await registry.task(group: "prefetch", key: "cover", as: Task<Void, Never>.self) == nil)
    }
}

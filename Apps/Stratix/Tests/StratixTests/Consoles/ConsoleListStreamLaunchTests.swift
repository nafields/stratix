// ConsoleListStreamLaunchTests.swift
// Exercises console list stream launch behavior.
//

import Testing
import StratixCore
import XCloudAPI

#if canImport(Stratix)
@testable import Stratix
#endif

struct ConsoleListStreamLaunchTests {
    @Test
    @MainActor
    func prepareHomeStreamLaunch_entersHomePriorityModeAndReturnsConsole() async throws {
        let console = try makeConsole(id: "console-a")
        var receivedContexts: [StreamRuntimeContext] = []

        let selectedConsole = await ConsoleListView.prepareHomeStreamLaunch(
            console: console,
            isShowingStream: false,
            enterPriorityMode: { receivedContexts.append($0) }
        )

        #expect(selectedConsole?.serverId == "console-a")
        #expect(receivedContexts == [.home(consoleId: "console-a")])
    }

    @Test
    @MainActor
    func restoreShellAfterStreamDismissal_preservesStopExitFocusOrder() async {
        var events: [String] = []

        await ConsoleListView.restoreShellAfterStreamDismissal(
            stopStreaming: { events.append("stop") },
            exitPriorityMode: { events.append("exit") },
            restoreFocus: { events.append("focus") }
        )

        #expect(events == ["stop", "exit", "focus"])
    }

    private func makeConsole(id: String) throws -> RemoteConsole {
        let json = """
        {
          "deviceName": "Fixture Console",
          "serverId": "\(id)",
          "powerState": "On",
          "consoleType": "Xbox Series X",
          "playPath": "/play",
          "outOfHomeWarning": false,
          "wirelessWarning": false,
          "isDevKit": false
        }
        """
        return try JSONDecoder().decode(RemoteConsole.self, from: Data(json.utf8))
    }
}

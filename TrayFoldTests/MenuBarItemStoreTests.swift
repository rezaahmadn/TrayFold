import CoreGraphics
import Testing
@testable import TrayFold

/// Drives `MenuBarItemStore` with a fake permission, fake app list and fake scan, so the
/// tests never touch real apps. The NSWorkspace and permission notifications are checked
/// in the running app (see the phase 3 report).
@MainActor
struct MenuBarItemStoreTests {
    /// Mutable stand-ins for the permission and the running apps.
    final class FakeSystem {
        var trusted = true
        var pids: [pid_t] = [1, 2]
    }

    static func owner(_ pid: pid_t) -> MenuBarItem.Owner {
        MenuBarItem.Owner(pid: pid, bundleID: "test.app\(pid)", name: "App \(pid)")
    }

    /// One item per app, placed at x = pid × 40 and titled with how many apps the same
    /// scan asked. `nonisolated` because the store runs it on a background thread.
    nonisolated static func fakeScan(_ owners: [MenuBarItem.Owner]) -> [MenuBarItem] {
        owners.map { owner in
            MenuBarItem(
                id: "\(owner.pid)/#0",
                owner: owner,
                title: "batch of \(owners.count)",
                accessibilityDescription: nil,
                identifier: nil,
                frame: CGRect(x: CGFloat(owner.pid) * 40, y: 0, width: 36, height: 24),
                // Creating a handle for a made-up pid is fine: nothing is asked until it's read.
                element: AXElement.application(pid: owner.pid)
            )
        }
    }

    func makeStore(_ system: FakeSystem) -> MenuBarItemStore {
        MenuBarItemStore(
            isTrusted: { system.trusted },
            candidateApps: { system.pids.map(Self.owner) },
            scan: Self.fakeScan
        )
    }

    @Test func refreshListsEveryAppLeftToRight() async {
        let system = FakeSystem()
        system.pids = [2, 1]
        let store = makeStore(system)
        await store.refresh()
        #expect(store.items.map(\.owner.pid) == [1, 2])
    }

    @Test func staysEmptyWithoutPermission() async {
        let system = FakeSystem()
        system.trusted = false
        let store = makeStore(system)
        var calls = 0
        store.onChange = { _ in calls += 1 }
        await store.refresh()
        #expect(store.items.isEmpty)
        #expect(calls == 0)
    }

    @Test func recoversOnceAllowedAndEmptiesWhenRevoked() async {
        let system = FakeSystem()
        system.trusted = false
        let store = makeStore(system)
        await store.refresh()
        #expect(store.items.isEmpty)
        system.trusted = true
        await store.refresh()
        #expect(store.items.count == 2)
        system.trusted = false
        await store.refresh()
        #expect(store.items.isEmpty)
    }

    @Test func onChangeFiresOnlyWhenItemsChange() async {
        let system = FakeSystem()
        let store = makeStore(system)
        var calls: [Int] = []
        store.onChange = { calls.append($0.count) }
        await store.refresh()           // [] → 2 items: call
        await store.refresh()           // same items: no call
        system.pids = [1, 2, 3]
        await store.refresh()           // 3 items: call
        #expect(calls == [2, 3])
    }

    @Test func launchRescansOnlyThatApp() async {
        let system = FakeSystem()
        let store = makeStore(system)
        await store.refresh()
        await store.rescan(Self.owner(3))
        #expect(store.items.map(\.owner.pid) == [1, 2, 3])
        #expect(store.items.map(\.title) == ["batch of 2", "batch of 2", "batch of 1"])
    }

    @Test func quitDropsThatAppsItems() async {
        let system = FakeSystem()
        let store = makeStore(system)
        await store.refresh()
        await store.forget(pid: 1)
        #expect(store.items.map(\.owner.pid) == [2])
    }

    @Test func overlappingUpdatesApplyInOrder() async {
        let system = FakeSystem()
        let store = makeStore(system)
        // A full scan is running in the background when app 1 quits. Without the queue,
        // the scan would finish last and bring app 1's item back.
        let scanning = Task { await store.refresh() }
        await Task.yield()              // let the scan start
        await store.forget(pid: 1)
        await scanning.value
        #expect(store.items.map(\.owner.pid) == [2])
    }

    @Test func summaryListsBundleIDs() {
        let items = Self.fakeScan([Self.owner(1), Self.owner(2)])
        #expect(MenuBarItemStore.summary(items) == "2 (test.app1, test.app2)")
        #expect(MenuBarItemStore.summary([]) == "0 ()")
    }
}

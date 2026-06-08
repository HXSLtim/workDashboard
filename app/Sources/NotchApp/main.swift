import AppKit
import Combine
import DynamicNotchKit
import SwiftUI

@MainActor
final class AppController {
    private let store = StateStore()
    private let reminders = RemindersStore()
    private let pager = PagerModel()
    private let notifier = Notifier()
    private var notch: DynamicNotch<ExpandedPanel, EmptyView, EmptyView>!
    private var hoverCancellable: AnyCancellable?
    private var stateCancellable: AnyCancellable?
    private var expandTask: Task<Void, Never>?
    private var scrollMonitor: Any?
    private var scrollLatched = false
    // CI-failure notifications: only alert for failures that happen AFTER launch,
    // and at most once per failure per session.
    private let startTime = Date()
    private let iso = ISO8601DateFormatter()
    private var notifiedCIKeys = Set<String>()

    func start() {
        store.start()
        reminders.start()
        notifier.start()
        let store = self.store
        let reminders = self.reminders
        let pager = self.pager

        // Collapsed state shows nothing — just the bare notch (still hoverable to
        // expand). Per request: no content unless expanded.
        notch = DynamicNotch(hoverBehavior: .all, style: .auto) {
            ExpandedPanel(store: store, reminders: reminders, pager: pager)
        } compactLeading: {
            EmptyView()
        } compactTrailing: {
            EmptyView()
        }

        Task { await notch.compact() }
        hoverCancellable = notch.$isHovering
            .removeDuplicates()
            .sink { [weak self] hovering in
                Task { @MainActor in self?.handleHover(hovering) }
            }

        installScrollMonitor()

        // Watch for new CI failures and post a banner.
        stateCancellable = store.$state.sink { [weak self] s in
            Task { @MainActor in self?.onState(s) }
        }
    }

    // Expand only after the mouse rests on the notch ~0.3s (so merely passing
    // through to the menu bar / other apps doesn't trigger it); collapse instantly
    // on exit to get out of the way.
    private func handleHover(_ hovering: Bool) {
        expandTask?.cancel()
        guard let notch else { return }
        if hovering {
            expandTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                if !Task.isCancelled, notch.isHovering { await notch.expand() }
            }
        } else {
            Task { @MainActor in await notch.compact() }
        }
    }

    private func onState(_ s: HubState) {
        // GitHub delivers workflow-run failures (main/branch CI) as notifications,
        // not as PR check status — so we watch the inbox's CI items. Only alert for
        // failures whose timestamp is after launch, once per failure per session.
        let ciFailures = s.inbox.filter {
            $0.type == "ci" && $0.title.lowercased().contains("fail")
        }
        for item in ciFailures {
            guard !notifiedCIKeys.contains(item.id) else { continue }
            notifiedCIKeys.insert(item.id) // mark so it never re-fires this session
            guard let ts = iso.date(from: item.ts), ts >= startTime else { continue }
            notifier.notify(title: "CI 失败", body: "\(item.repo) · \(item.title)", url: item.url)
        }
    }

    // Two-finger horizontal swipe over the notch panel flips pages. A local
    // monitor only sees events dispatched to our app (no accessibility prompt),
    // and we act only when the event targets our notch window.
    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard let window = notch?.windowController?.window, event.window === window else { return }
        if event.phase.contains(.began) { scrollLatched = false }
        guard event.momentumPhase == [], !scrollLatched else { return }

        let dx = event.scrollingDeltaX
        guard abs(dx) > abs(event.scrollingDeltaY), abs(dx) > 8 else { return }
        scrollLatched = true
        if dx < 0 { pager.next() } else { pager.prev() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AppController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // no Dock icon — lives in the notch
    objc_setAssociatedObject(app, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.run()
}

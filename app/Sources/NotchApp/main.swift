import AppKit
import Combine
import DynamicNotchKit
import SwiftUI

@MainActor
final class AppController {
    private let store = StateStore()
    private let reminders = RemindersStore()
    private let pager = PagerModel()
    private var notch: DynamicNotch<ExpandedPanel, EmptyView, EmptyView>!
    private var hoverCancellable: AnyCancellable?
    private var stateCancellable: AnyCancellable?
    private var scrollMonitor: Any?
    private var scrollLatched = false
    private var knownRedCI: Set<String>?

    func start() {
        store.start()
        reminders.start()
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
            .sink { [weak notch] hovering in
                guard let notch else { return }
                Task { @MainActor in
                    if hovering { await notch.expand() } else { await notch.compact() }
                }
            }

        installScrollMonitor()

        // Watch for newly-failed CI and briefly drop the notch open as an alert.
        stateCancellable = store.$state.sink { [weak self] s in
            Task { @MainActor in self?.onState(s) }
        }
    }

    private func onState(_ s: HubState) {
        let red = Set(
            (s.github.myOpenPRs + s.github.reviewRequestList)
                .filter { $0.ciStatus == "red" }
                .map(\.url)
        )
        guard let known = knownRedCI else {
            knownRedCI = red // baseline on first load — don't alert
            return
        }
        let fresh = red.subtracting(known)
        knownRedCI = red
        guard !fresh.isEmpty, let notch, !notch.isHovering else { return }
        Task { @MainActor in
            await notch.expand()
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !notch.isHovering { await notch.compact() }
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

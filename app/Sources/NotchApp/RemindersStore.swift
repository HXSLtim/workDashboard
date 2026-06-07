import AppKit
import Combine
import EventKit
import Foundation
import SwiftUI

struct ReminderItem: Identifiable {
    let id: String
    let title: String
    let due: Date?
    let priority: Int // 0 = none, 1 (high) ... 9 (low) per EventKit
    let list: String
}

// Reads incomplete reminders from macOS Reminders via EventKit. This is the one
// data source the notch app reads directly (not through the daemon), because
// Reminders is local and its access is gated by a per-app permission prompt.
@MainActor
final class RemindersStore: ObservableObject {
    @Published var reminders: [ReminderItem] = []
    @Published var authorized = false
    @Published var statusText = "请求提醒事项权限…"

    private let store = EKEventStore()
    private var refreshTimer: Timer?
    private var ekById: [String: EKReminder] = [:]

    /// Mark a reminder complete directly from the notch panel.
    func complete(_ id: String) {
        guard let r = ekById[id] else { return }
        r.isCompleted = true
        try? store.save(r, commit: true)
        reload()
    }

    /// Open the Reminders app (no per-reminder deep link in EventKit).
    func openRemindersApp() {
        if let url = URL(string: "x-apple-reminderkit://") {
            NSWorkspace.shared.open(url)
        }
    }

    func refresh() { reload() }

    func start() {
        store.requestFullAccessToReminders { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                self.authorized = granted
                if granted {
                    self.statusText = ""
                    self.reload()
                    self.observeChanges()
                    // Periodic fallback in case the change notification is missed.
                    self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                        Task { @MainActor in self.reload() }
                    }
                } else {
                    self.statusText = "未授权提醒事项"
                    if let error { self.statusText += "：\(error.localizedDescription)" }
                }
            }
        }
    }

    private func observeChanges() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    private func reload() {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        store.fetchReminders(matching: predicate) { [weak self] ekReminders in
            let ek = ekReminders ?? []
            let byId = Dictionary(ek.map { ($0.calendarItemIdentifier, $0) }) { a, _ in a }
            let items = ek.map { r in
                ReminderItem(
                    id: r.calendarItemIdentifier,
                    title: r.title ?? "(无标题)",
                    due: r.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                    priority: r.priority,
                    list: r.calendar.title
                )
            }
            // Sort: due-dated first (soonest), then higher priority, then the rest.
            let sorted = items.sorted { a, b in
                switch (a.due, b.due) {
                case let (.some(x), .some(y)): return x < y
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none):
                    return effectivePriority(a.priority) < effectivePriority(b.priority)
                }
            }
            Task { @MainActor in
                withAnimation(.smooth(duration: 0.3)) { self?.reminders = sorted }
                self?.ekById = byId
            }
        }
    }
}

// EventKit priority: 1 = high … 9 = low, 0 = none. Map "none" to the bottom.
private func effectivePriority(_ p: Int) -> Int { p == 0 ? 99 : p }

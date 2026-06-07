import Combine
import Foundation
import SwiftUI

// Loads ~/.workhub/state.json and republishes it whenever the file changes.
// Polls mtime on a timer — the file is tiny and the daemon writes atomically,
// so we never see a partial read.
@MainActor
final class StateStore: ObservableObject {
    @Published var state: HubState = .empty
    @Published var loadError: String?

    private let path: URL
    private var lastModified: Date?
    private var timer: Timer?

    init() {
        path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".workhub/state.json")
    }

    func start() {
        reloadIfChanged()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadIfChanged() }
        }
    }

    /// Source names that failed on the daemon's last poll.
    var failingSources: [String] {
        state.sources.filter { !$0.value.ok }.map(\.key).sorted()
    }

    /// Re-read state.json immediately (used by the refresh menu item).
    func forceReload() {
        lastModified = nil
        reloadIfChanged()
    }

    private func reloadIfChanged() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path.path)
        let modified = attrs?[.modificationDate] as? Date
        if let modified, modified == lastModified { return }
        lastModified = modified

        do {
            let data = try Data(contentsOf: path)
            let decoded = try JSONDecoder().decode(HubState.self, from: data)
            withAnimation(.smooth(duration: 0.35)) { state = decoded }
            loadError = nil
        } catch {
            loadError = "无法读取 state.json：\(error.localizedDescription)"
        }
    }
}

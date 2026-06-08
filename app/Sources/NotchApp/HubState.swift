import Foundation

// Codable mirror of daemon/src/types.ts. Property names match JSON keys exactly.

struct HubState: Codable {
    var updatedAt: String
    var github: GitHubState
    var usage: UsageState
    var inbox: [InboxItem]
    var servers: [ServerStatus]
    var sources: [String: SourceStatus]
}

struct ServerStatus: Codable, Identifiable {
    var id: String { name }
    var name: String
    var host: String
    var os: String
    var online: Bool
    var cpuPct: Double?
    var memPct: Double?
    var diskPct: Double?
    var uptimeSec: Double?
    var latencyMs: Double?
    var error: String?
}

struct GitHubState: Codable {
    var profile: GitHubProfile
    var contributions: Contributions
    var reviewRequests: Int
    var reviewRequestList: [PullRequestInfo]
    var myOpenPRs: [PullRequestInfo]
    var runningActions: [RunningAction]
}

struct GitHubProfile: Codable {
    var login: String
    var name: String
    var avatarUrl: String
}

struct Contributions: Codable {
    var total: Int
    var today: Int
    var weeks: [[Int]]
}

struct PullRequestInfo: Codable, Identifiable {
    var id: String { url }
    var title: String
    var url: String
    var repo: String
    var author: String
    var ciStatus: String
}

struct RunningAction: Codable, Identifiable {
    var id: String { url }
    var repo: String
    var workflow: String
    var url: String
}

struct UsageState: Codable {
    var claude: ProviderUsage
    var codex: ProviderUsage
}

struct ProviderUsage: Codable {
    var today: UsageWindow
    var month: UsageWindow
    var byModel: [String: Double]
    var sessions: Int
}

struct UsageWindow: Codable {
    var tokens: Double
    var cost: Double
}

struct InboxItem: Codable, Identifiable {
    var id: String { "\(repo)|\(type)|\(title)" }
    var type: String
    var title: String
    var url: String
    var repo: String
    var ts: String
    var count: Int
}

struct SourceStatus: Codable {
    var ok: Bool
    var error: String?
    var updatedAt: String
}

extension HubState {
    static let empty = HubState(
        updatedAt: "",
        github: GitHubState(
            profile: GitHubProfile(login: "", name: "", avatarUrl: ""),
            contributions: Contributions(total: 0, today: 0, weeks: []),
            reviewRequests: 0, reviewRequestList: [], myOpenPRs: [], runningActions: []
        ),
        usage: UsageState(claude: .empty, codex: .empty),
        inbox: [],
        servers: [],
        sources: [:]
    )
}

extension ProviderUsage {
    static let empty = ProviderUsage(
        today: UsageWindow(tokens: 0, cost: 0),
        month: UsageWindow(tokens: 0, cost: 0),
        byModel: [:], sessions: 0
    )
}

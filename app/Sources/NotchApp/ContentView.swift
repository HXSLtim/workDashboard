import AppKit
import SwiftUI

// Views handed to DynamicNotchKit. The library provides the notch window, black
// chrome, rounded corners, hover tracking and safe-area insets — these views
// only render content.

private func openURL(_ s: String) {
    guard let u = URL(string: s) else { return }
    NSWorkspace.shared.open(u)
}

// Adds hover highlight + tap affordance to any view, so clickable items feel
// alive instead of static.
private struct Clickable: ViewModifier {
    let action: () -> Void
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(hover ? 0.12 : 0))
            )
            .contentShape(Rectangle())
            .scaleEffect(hover ? 1.03 : 1)
            .onHover { hover = $0 }
            .onTapGesture(perform: action)
            .animation(.easeOut(duration: 0.13), value: hover)
    }
}

extension View {
    func clickable(_ action: @escaping () -> Void) -> some View {
        modifier(Clickable(action: action))
    }
}

private func fmtTokens(_ t: Double) -> String {
    if t >= 1_000_000 { return String(format: "%.1fM", t / 1_000_000) }
    if t >= 1_000 { return String(format: "%.0fK", t / 1_000) }
    return "\(Int(t))"
}

// MARK: - Expanded (drops from the notch, wide/horizontal)

// Shared paging state so the trackpad scroll monitor (in AppController) and the
// SwiftUI view stay in sync.
@MainActor
final class PagerModel: ObservableObject {
    @Published var page = 0
    let count = 2
    func next() { page = min(count - 1, page + 1) }
    func prev() { page = max(0, page - 1) }
}

struct ExpandedPanel: View {
    @ObservedObject var store: StateStore
    @ObservedObject var reminders: RemindersStore
    @ObservedObject var pager: PagerModel

    private static let pageWidth: CGFloat = 600
    private static let pageHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                // Page 0 — GitHub commits + to-dos
                HStack(alignment: .top, spacing: 12) {
                    ProfileColumn(github: store.state.github)
                    TodosColumn(reminders: reminders)
                }
                .frame(width: Self.pageWidth)

                // Page 1 — AI usage
                HStack(alignment: .top, spacing: 12) {
                    UsageColumn(title: "Claude", accent: .orange, usage: store.state.usage.claude)
                    UsageColumn(title: "Codex", accent: .green, usage: store.state.usage.codex)
                }
                .frame(width: Self.pageWidth)
            }
            .frame(width: Self.pageWidth, height: Self.pageHeight, alignment: .leading)
            .offset(x: CGFloat(-pager.page) * Self.pageWidth)
            .animation(.easeInOut(duration: 0.25), value: pager.page)
            .clipped()

            HStack(spacing: 8) {
                if !store.failingSources.isEmpty {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("源异常：\(store.failingSources.joined(separator: ", "))")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                PageControl(page: $pager.page, count: pager.count)
                Spacer()
            }
        }
        .padding(16)
        .frame(width: Self.pageWidth + 32)
        .foregroundStyle(.white)
        .contextMenu {
            Button("刷新") { store.forceReload(); reminders.refresh() }
            Divider()
            Button("退出 WorkHub") { NSApp.terminate(nil) }
        }
    }
}

private struct PageControl: View {
    @Binding var page: Int
    var count: Int
    var body: some View {
        HStack(spacing: 14) {
            chevron("chevron.left", enabled: page > 0) { page = max(0, page - 1) }
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.white : Color.white.opacity(0.25))
                        .frame(width: 6, height: 6)
                        .onTapGesture { page = i }
                }
            }
            chevron("chevron.right", enabled: page < count - 1) { page = min(count - 1, page + 1) }
        }
        .frame(height: 16)
    }

    private func chevron(_ name: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? .white.opacity(0.8) : .white.opacity(0.2))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: GitHub profile + contributions

private struct ProfileColumn: View {
    var github: GitHubState
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    AsyncImage(url: URL(string: github.profile.avatarUrl)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color.white.opacity(0.1)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.15)))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(github.profile.name).font(.system(size: 14, weight: .bold))
                        Text("@\(github.profile.login)")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                }
                .clickable { openURL("https://github.com/\(github.profile.login)") }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(github.contributions.total)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("contributions / yr").font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text("今日 \(github.contributions.today)")
                        .font(.system(size: 11, weight: .semibold))
                        .contentTransition(.numericText())
                        .foregroundStyle(github.contributions.today > 0 ? .green : .white.opacity(0.5))
                }

                Heatmap(weeks: github.contributions.weeks)

                HStack(spacing: 18) {
                    stat("待 review", github.reviewRequests,
                         "https://github.com/pulls?q=is%3Aopen+is%3Apr+review-requested%3A%40me")
                    stat("我的 PR", github.myOpenPRs.count, "https://github.com/pulls")
                    stat("运行中", github.runningActions.count,
                         github.runningActions.first?.url ?? "https://github.com/\(github.profile.login)")
                }
                .font(.system(size: 11))
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(_ k: String, _ v: Int, _ url: String) -> some View {
        VStack(spacing: 2) {
            Text("\(v)").font(.system(size: 14, weight: .bold))
                .contentTransition(.numericText())
            Text(k).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
        }
        .clickable { openURL(url) }
    }
}

private struct Heatmap: View {
    var weeks: [[Int]]
    var body: some View {
        HStack(alignment: .top, spacing: 3) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(day < week.count ? week[day] : 0))
                            .frame(width: 10, height: 10)
                    }
                }
            }
        }
    }

    private func color(_ count: Int) -> Color {
        switch count {
        case 0: return .white.opacity(0.08)
        case 1...2: return .green.opacity(0.4)
        case 3...5: return .green.opacity(0.65)
        case 6...9: return .green.opacity(0.85)
        default: return .green
        }
    }
}

// MARK: AI usage column (Claude / Codex)

private struct UsageColumn: View {
    var title: String
    var accent: Color
    var usage: ProviderUsage
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 8, height: 8)
                    Text(title).font(.system(size: 13, weight: .bold))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(fmtTokens(usage.today.tokens))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("今日 tokens · ~$\(String(format: "%.1f", usage.today.cost))")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }

                Divider().overlay(.white.opacity(0.1))

                row("本月", fmtTokens(usage.month.tokens))
                row("本月费用", "~$\(String(format: "%.0f", usage.month.cost))")
                row("今日会话", "\(usage.sessions)")

                if let top = usage.byModel.sorted(by: { $0.value > $1.value }).first {
                    Text(top.key).font(.system(size: 9)).lineLimit(1)
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(v).fontWeight(.semibold)
        }
        .font(.system(size: 11))
    }
}

// MARK: 待办 (macOS Reminders via EventKit)

private struct TodosColumn: View {
    @ObservedObject var reminders: RemindersStore
    @State private var completing: Set<String> = []

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "checklist").font(.system(size: 11))
                    Text("待办").font(.system(size: 13, weight: .bold))
                    Spacer()
                    if reminders.authorized {
                        Text("\(reminders.reminders.count)")
                            .font(.system(size: 12, weight: .bold))
                            .contentTransition(.numericText())
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                if !reminders.authorized {
                    Text(reminders.statusText)
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                } else if reminders.reminders.isEmpty {
                    Text("全部完成 🎉").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                } else {
                    ForEach(reminders.reminders.prefix(8)) { item in
                        row(item)
                            .transition(.asymmetric(
                                insertion: .opacity,
                                removal: .opacity.combined(with: .move(edge: .leading))
                            ))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: 230)
    }

    private func row(_ item: ReminderItem) -> some View {
        let done = completing.contains(item.id)
        return HStack(alignment: .top, spacing: 7) {
            // Tap to complete — fills with a check, then the row slides out.
            ZStack {
                Circle().strokeBorder(dotColor(item), lineWidth: 1.5)
                    .opacity(done ? 0 : 1)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
                    .scaleEffect(done ? 1 : 0.1)
                    .opacity(done ? 1 : 0)
            }
            .frame(width: 13, height: 13)
            .padding(.top, 1)
            .contentShape(Circle())
            .onTapGesture { complete(item.id) }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 11)).lineLimit(1)
                    .strikethrough(done, color: .white.opacity(0.5))
                if let due = item.due {
                    Text(dueLabel(due))
                        .font(.system(size: 9))
                        .foregroundStyle(isOverdue(due) ? .red : .white.opacity(0.4))
                }
            }
            .opacity(done ? 0.4 : 1)
            .contentShape(Rectangle())
            .onTapGesture { reminders.openRemindersApp() }
            Spacer(minLength: 0)
        }
    }

    private func complete(_ id: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            _ = completing.insert(id)
        }
        // Let the check animation play, then remove (list change animates the slide-out).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            reminders.complete(id)
            completing.remove(id)
        }
    }

    private func isOverdue(_ d: Date) -> Bool { d < Date() }

    private func dotColor(_ item: ReminderItem) -> Color {
        if let due = item.due, isOverdue(due) { return .red }
        if item.priority != 0, item.priority <= 4 { return .orange }
        return .white.opacity(0.35)
    }

    private func dueLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(d) { f.dateFormat = "今天 HH:mm" }
        else if Calendar.current.isDateInTomorrow(d) { f.dateFormat = "明天 HH:mm" }
        else { f.dateFormat = "M月d日" }
        return f.string(from: d)
    }
}

//
// TiebaLiveActivity.swift —— Live Activity（灵动岛/锁屏实时活动）在 iOS 15.5 上的落法
//
// Live Activity 是 ActivityKit 的能力，最低 iOS 16.1；本工程底线 15.5 时它没有对应实现，
// 也没有"降级观感"可言（系统侧根本不存在这个展示位）。因此这层从"ActivityKit 句柄管理"
// 退化成**同签名的空实现**：
//
//   · 保留 `TiebaLiveActivityManager` 的全部方法签名与语义（start/update/end/endAll/
//     endAllInterrupted/areActivitiesEnabled）以及三个值类型（payload / alert / dismissal policy），
//     调用方（TiebaSignService、TiebaAppBootstrap、TiebaOKSignViewController）一行都不用改；
//   · `start` 恒抛 `.disabled`（调用方本来就是 `try?`，等于什么都不做）；
//   · `areActivitiesEnabled` 恒 false ⇒ 启动时的"残留活动抢救"直接短路；
//   · 签到本身的**结果**不受影响：成功数/失败数/经验仍由页内 pill 与本地通知承担
//     （见 TiebaSignService.finishDisplay），丢掉的只有"灵动岛/锁屏进度条"这一个展示位。
//
// 与之配套的删除：`PlugIns/TiebaLiveActivity.appex`（扩展的最低系统版本是 16.1，留着会让
// 15.5 的安装器拒绝整包）与 Info.plist 里的 `NSSupportsLiveActivities*`。
//

import Foundation

/// start 的完整载荷投影：模块侧 AsyncFunction 收到的是自由字典 [String: Any]
/// （非 Sendable），管理器在主 actor——跨域前先在调用队列把字典归一成值类型。
struct TiebaLiveActivityPayload: Sendable {
    let name: String
    let extra: [String: String]?
    let state: TiebaLiveActivityKitAttributes.ContentState

    init(raw: [String: Any]) {
        self.name = raw["name"] as? String ?? "TiebaLiteSign"
        self.extra = raw["extra"] as? [String: String]
        self.state = TiebaLiveActivityKitAttributes.ContentState(raw: raw)
    }
}

/// 结束时的锁屏通知（原 AlertConfiguration 的标题 + 正文）。
struct TiebaLiveActivityAlert: Sendable {
    let title: String
    let body: String
}

/// Live Activity 结束时的撤除策略（保留原名，调用方传 `.default` / `.immediate`）。
enum TiebaLiveActivityDismissalPolicy: Sendable {
    case immediate
    case `default`
}

@MainActor
final class TiebaLiveActivityManager {
    static let shared = TiebaLiveActivityManager()

    private init() {}

    /// 15.5 上没有 Live Activity：恒 false（调用方据此整段短路）。
    nonisolated static func areActivitiesEnabled() -> Bool {
        false
    }

    /// 恒抛 `.disabled`（调用点都是 `try?`，语义 = 不展示）。
    func start(payload: TiebaLiveActivityPayload) throws -> String {
        throw TiebaLiveActivityError.disabled
    }

    func update(activityId: String, state: TiebaLiveActivityKitAttributes.ContentState) async {}

    func end(
        activityId: String,
        state: TiebaLiveActivityKitAttributes.ContentState,
        dismissalPolicy: TiebaLiveActivityDismissalPolicy,
        alert: TiebaLiveActivityAlert? = nil
    ) async {}

    /// 结束「签到」类中断残留：没有活动可结束，保留入口以免调用点分叉。
    func endAllInterrupted() async {}

    func endAll(
        state: TiebaLiveActivityKitAttributes.ContentState,
        dismissalPolicy: TiebaLiveActivityDismissalPolicy
    ) async {}
}

enum TiebaLiveActivityError: LocalizedError {
    case disabled

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "当前系统版本不支持 Live Activities（需要 iOS 16.1 或更高）。"
        }
    }
}

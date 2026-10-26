//
// LiveActivityKitAttributes.swift —— 签到活动的属性/状态值类型
//
// 原实现 `import ActivityKit` 并遵循 `ActivityAttributes`（该协议最低 iOS 16.1）。
// 底线 15.5 下 ActivityKit 不可用，但这份**数据**仍被三处使用：
//   · TiebaLiveActivityPayload(raw:) / TiebaSignService.activityState 的状态装箱；
//   · TiebaAppBootstrap.recoverLiveActivities 的中断态；
//   · 空实现的 TiebaLiveActivityManager 的方法签名。
//
// 因此这里保留字段与初始化器、去掉框架依赖与协议遵循（纯值类型，Codable/Hashable 不变），
// 语义不变而不再牵 ActivityKit。
//

import Foundation

// Sendable 显式声明（public 值类型不会隐式推断）。
public struct TiebaLiveActivityKitAttributes: Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var title: String
        public var subtitle: String?
        public var body: String?
        public var currentForum: String?
        public var status: String?
        public var progress: Double?
        public var date: Double?
        public var imageName: String?
        public var tintColorHex: String?
        public var leading: String?
        public var trailing: String?
        public var extra: [String: String]?

        public init(
            title: String,
            subtitle: String? = nil,
            body: String? = nil,
            currentForum: String? = nil,
            status: String? = nil,
            progress: Double? = nil,
            date: Double? = nil,
            imageName: String? = nil,
            tintColorHex: String? = nil,
            leading: String? = nil,
            trailing: String? = nil,
            extra: [String: String]? = nil
        ) {
            self.title = title
            self.subtitle = subtitle
            self.body = body
            self.currentForum = currentForum
            self.status = status
            self.progress = progress
            self.date = date
            self.imageName = imageName
            self.tintColorHex = tintColorHex
            self.leading = leading
            self.trailing = trailing
            self.extra = extra
        }
    }

    public var name: String
    public var extra: [String: String]?

    public init(name: String, extra: [String: String]? = nil) {
        self.name = name
        self.extra = extra
    }
}

extension TiebaLiveActivityKitAttributes.ContentState {
    /// 自由字典 → 值类型（原 TiebaLiveActivityManager.makeState 的语义，原样搬移）。
    /// 必须存在于非隔离上下文：模块侧 AsyncFunction 收到 [String: Any]（非 Sendable），
    /// 要在跨到主 actor 之前先归一，否则 Swift 6 报 "sending 'state'"。
    init(raw: [String: Any]) {
        self.init(
            title: raw["title"] as? String ?? "",
            subtitle: raw["subtitle"] as? String,
            body: raw["body"] as? String,
            currentForum: raw["currentForum"] as? String,
            status: raw["status"] as? String,
            progress: raw["progress"] as? Double,
            date: raw["date"] as? Double,
            imageName: raw["imageName"] as? String,
            tintColorHex: raw["tintColorHex"] as? String,
            leading: raw["leading"] as? String,
            trailing: raw["trailing"] as? String,
            extra: raw["extra"] as? [String: String]
        )
    }
}

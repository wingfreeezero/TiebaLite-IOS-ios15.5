//
// TiebaPlatformCompat.swift —— iOS 15.5 部署底线下的平台能力兼容层
//
// 这个工程原来的部署底线是 iOS 17（`.bazelrc --ios_minimum_os` / `BUILD.bazel minimum_os_version`），
// 因此正文里可以直接写 iOS 17 才有的 API。底线降到 15.5 后，下面两类 API 在**编译期**就不可用
// （不是运行时崩溃，而是 "is only available in iOS 17.0 or newer" 直接编不过），必须换成同语义落法：
//
//   1. `MainActor.assumeIsolated`（SwiftStdlib 5.9 / iOS 17 起）
//      → `MainActor.tiebaAssumeIsolated`：同一手法（校验 executor + unsafeBitCast 抹掉闭包上的
//        actor 标注后**同步**调用），不派发、不改变时序。
//   2. `registerForTraitChanges`（UITraitChangeObservable，iOS 17 起）
//      → `tiebaObserveTraits(_:_:_:)`：iOS 17+ 直接转给系统实现（行为逐字不变）；15.x 用
//        `traitCollectionDidChange` 驱动同一份闭包（系统在低版本上唯一的 trait 变化回调）。
//
// 判据与全仓一致：**不留第二套实现**。两个分支跑的是同一份 handler，只是"谁来触发"不同；
// 15.x 上的观感/几何决定全部来自既有代码里已经写好的低版本分支（原 `#available(iOS 26.0, *)`
// 的 else 侧），本仓不新增任何视觉配方。
//

import UIKit

// MARK: - MainActor 隔离断言（替代 iOS 17 的 MainActor.assumeIsolated）

extension MainActor {
    /// 语义与 `MainActor.assumeIsolated` 完全一致：调用方保证此刻在主线程（= 主 actor），
    /// 断言成立后**同步**执行 `operation`，不派发、不改变时序；断言失败直接停在断言处。
    ///
    /// 为什么需要自实现：系统实现的可用性是 SwiftStdlib 5.9（iOS 17），底线 15.5 下编不过。
    /// 内部实现与 stdlib 同一手法：先校验"当前是否主线程"，再用 `unsafeBitCast` 把
    /// `@MainActor () throws -> T` 抹成 `() throws -> T` 后同步调用——这一步的安全性由
    /// 上面的校验保证（主线程 = Apple 平台上的 MainActor executor）。
    @_alwaysEmitIntoClient
    public static func tiebaAssumeIsolated<T>(
        _ operation: @MainActor () throws -> T,
        file: StaticString = #fileID,
        line: UInt = #line
    ) rethrows -> T {
        typealias ActorBound = @MainActor () throws -> T
        typealias Unbound = () throws -> T
        guard Thread.isMainThread else {
            preconditionFailure("tiebaAssumeIsolated 只能在主线程调用（\(file):\(line)）")
        }
        return try withoutActuallyEscaping(operation) { (escaping fn: @escaping ActorBound) throws -> T in
            let unbound: Unbound = unsafeBitCast(fn, to: Unbound.self)
            return try unbound()
        }
    }
}

// MARK: - trait 变化观察（替代 iOS 17 的 registerForTraitChanges）

/// 需要观察的 trait 维度。
///
/// 只声明本仓真正用到的四个；iOS 17+ 分支据此映射回系统定义，15.x 分支不区分维度
/// （`traitCollectionDidChange` 一次变化把所有登记项都跑一遍，代价是同一帧内多几个
/// 幂等的重解析调用，与系统行为等价）。
enum TiebaTraitAspect {
    case userInterfaceStyle
    case preferredContentSizeCategory
    case accessibilityContrast
    case horizontalSizeClass
}

/// 登记令牌：iOS 17+ 是系统返回的 `UITraitChangeRegistration`，15.x 是内部登记项。
/// 调用方只负责**持有**它（写进 `private var xxxRegistration`），不读内容，因此统一成 AnyObject。
typealias TiebaTraitRegistration = AnyObject

/// 15.x 的登记表 + 触发点。
///
/// 触发点用 `traitCollectionDidChange(_:)` 交换实现来拿：这个方法是 iOS 8 起就有的系统回调，
/// 也是 15.x 上**唯一**能观察到"深浅色/字号档/尺寸类别"变化的位置（系统在 17 起把它标成废弃，
/// 但低版本上它就是正解）。交换只做一次，两个基类各一处；子类自己的 override 只要调了 super
/// 就能走到这里（本仓唯一的 override 就是 TiebaForumHeaderView，它调了 super）。
@MainActor
private final class TiebaTraitCenter {
    static let shared = TiebaTraitCenter()

    private var handlers: [ObjectIdentifier: [() -> Void]] = [:]
    private var installed = false

    private init() {}

    func add(_ object: AnyObject, _ handler: @escaping () -> Void) {
        handlers[ObjectIdentifier(object), default: []].append(handler)
    }

    func fire(_ object: AnyObject) {
        guard let list = handlers[ObjectIdentifier(object)] else { return }
        for handler in list { handler() }
    }

    /// 交换 `traitCollectionDidChange:`（幂等，全进程一次）。
    func installSwizzlesIfNeeded() {
        guard !installed else { return }
        installed = true
        Self.swizzle(
            in: UIView.self,
            original: #selector(UIView.traitCollectionDidChange(_:)),
            replacement: #selector(UIView.tieba_traitCollectionDidChange(_:))
        )
        Self.swizzle(
            in: UIViewController.self,
            original: #selector(UIViewController.traitCollectionDidChange(_:)),
            replacement: #selector(UIViewController.tieba_traitCollectionDidChange(_:))
        )
    }

    private static func swizzle(in cls: AnyClass, original: Selector, replacement: Selector) {
        guard
            let lhs = class_getInstanceMethod(cls, original),
            let rhs = class_getInstanceMethod(cls, replacement)
        else { return }
        method_exchangeImplementations(lhs, rhs)
    }
}

extension UIView {
    /// 交换后的选择器指向系统原实现：这里先调"自己"（= 原实现），再广播登记项。
    @objc fileprivate func tieba_traitCollectionDidChange(_ previous: UITraitCollection?) {
        self.tieba_traitCollectionDidChange(previous)
        TiebaTraitCenter.shared.fire(self)
    }
}

extension UIViewController {
    @objc fileprivate func tieba_traitCollectionDidChange(_ previous: UITraitCollection?) {
        self.tieba_traitCollectionDidChange(previous)
        TiebaTraitCenter.shared.fire(self)
    }
}

/// iOS 17+ 的维度映射（类型本身是 17 起，因此整函数带可用性标注）。
@available(iOS 17.0, *)
private func tiebaTraitDefinitions(_ aspects: [TiebaTraitAspect]) -> [any UITraitDefinition.Type] {
    aspects.map { aspect in
        switch aspect {
        case .userInterfaceStyle: return UITraitUserInterfaceStyle.self
        case .preferredContentSizeCategory: return UITraitPreferredContentSizeCategory.self
        case .accessibilityContrast: return UITraitAccessibilityContrast.self
        case .horizontalSizeClass: return UITraitHorizontalSizeClass.self
        }
    }
}

/// 观察 `object` 的 trait 变化。返回的令牌需要被调用方持有（释放即视为取消，与系统语义一致）。
///
/// 用法与系统 API 同形，只是把 trait 列表换成本仓的 `TiebaTraitAspect`：
/// ```swift
/// registration = tiebaObserveTraits(self, [.userInterfaceStyle]) { (host: Self) in
///     host.applyTheme(...)
/// }
/// ```
@MainActor
@discardableResult
func tiebaObserveTraits<T: UIView>(
    _ object: T,
    _ aspects: [TiebaTraitAspect],
    _ handler: @escaping (T) -> Void
) -> TiebaTraitRegistration {
    if #available(iOS 17.0, *) {
        return object.registerForTraitChanges(tiebaTraitDefinitions(aspects)) {
            (changed: T, _: UITraitCollection) in
            handler(changed)
        }
    }
    TiebaTraitCenter.shared.installSwizzlesIfNeeded()
    TiebaTraitCenter.shared.add(object) { [weak object] in
        guard let object else { return }
        handler(object)
    }
    return NSObject()
}

/// `UIViewController` 侧的同名入口（`registerForTraitChanges` 在两个基类上各有一份）。
@MainActor
@discardableResult
func tiebaObserveTraits<T: UIViewController>(
    _ object: T,
    _ aspects: [TiebaTraitAspect],
    _ handler: @escaping (T) -> Void
) -> TiebaTraitRegistration {
    if #available(iOS 17.0, *) {
        return object.registerForTraitChanges(tiebaTraitDefinitions(aspects)) {
            (changed: T, _: UITraitCollection) in
            handler(changed)
        }
    }
    TiebaTraitCenter.shared.installSwizzlesIfNeeded()
    TiebaTraitCenter.shared.add(object) { [weak object] in
        guard let object else { return }
        handler(object)
    }
    return NSObject()
}

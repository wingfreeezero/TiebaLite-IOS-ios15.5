//
// MainActorIsolationCompat.swift —— Hero 模块自己的 MainActor 隔离断言
//
// 上游 Hero 1.6.4 在本仓被放在 Swift 6 语言模式下编译，其中三处（CALayer 动画装配与
// 转场入口）用 `MainActor.assumeIsolated` 把"UIKit 保证在主线程调用"这条既有契约显式告诉编译器。
// 该 API 的可用性是 SwiftStdlib 5.9（iOS 17），本分支部署底线 15.5，因此在这里补一份
// **逐字同语义**的本地实现（Hero 是独立 module，不能引用 TiebaNative 里的同名 shim）。
//
// 手法与 stdlib 一致：先校验"当前是否主线程"，再用 unsafeBitCast 抹掉闭包上的 actor 标注
// 后同步调用 —— 不派发、不改变时序。
//

import Foundation

extension MainActor {
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

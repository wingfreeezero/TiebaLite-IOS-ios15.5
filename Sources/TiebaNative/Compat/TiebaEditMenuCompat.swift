//
// TiebaEditMenuCompat.swift —— 文本编辑菜单在 iOS 15.5 上的落法
//
// 原实现用 `UIEditMenuInteraction` + `UIEditMenuConfiguration`（iOS 16 起）自己弹一份
// 与系统文本框同观的浮动菜单：正文选择层的「拷贝/全选/查询」与主贴标题的「复制标题」都走它。
// 底线降到 15.5 后这套类型在编译期不可用，而 15.x 上**唯一**的行内菜单只有
// `UIMenuController`（按选择器分发，装不下 UIAction 闭包）。
//
// 落法：把同一批动作改由系统 action sheet 承载。
//   · 动作、文案、顺序、触觉、回调与原来逐条一致（调用方给的是同一份 UIAction / 菜单项）；
//   · 观感从"锚在选区上方的浮动菜单"变成"系统底部动作表"——这是 15.x 上能力边界内的
//     最接近形态，且是系统件（不是自绘），深浅色/字号/无障碍全跟随系统；
//   · iPad 上按系统要求挂 popover 锚点（不挂会 crash）。
//
// 判据不变：不留第二套实现。16+ 上如果需要回到浮动菜单，把 present 内部换成
// UIEditMenuInteraction 即可，调用点不用动。
//

import UIKit

@MainActor
enum TiebaEditMenuCompat {
    /// 一条菜单动作（title / 图标 / 回调）。
    struct Item {
        let title: String
        let image: UIImage?
        let handler: () -> Void

        init(title: String, image: UIImage? = nil, handler: @escaping () -> Void) {
            self.title = title
            self.image = image
            self.handler = handler
        }
    }

    private static var presented: UIAlertController?

    /// 弹出动作表；`anchor` 决定 iPad 上的 popover 落点。
    static func present(_ items: [Item], from anchor: UIView) {
        guard !items.isEmpty else { return }
        guard let presenter = TiebaViewHosts.viewController(for: anchor) else { return }
        // 上一次还没收掉（连点标题等）：先收，避免叠两层。
        dismiss()
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for item in items {
            sheet.addAction(UIAlertAction(title: item.title, style: .default) { _ in
                TiebaSceneHaptics.fire("press")
                item.handler()
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = anchor
            popover.sourceRect = anchor.bounds
            popover.permittedArrowDirections = .any
        }
        presented = sheet
        presenter.present(sheet, animated: true)
    }

    /// 收掉当前动作表（选择结束/行复用/取消选择时调用）。
    static func dismiss() {
        guard let sheet = presented else { return }
        presented = nil
        if sheet.presentingViewController != nil {
            sheet.dismiss(animated: false)
        }
    }
}

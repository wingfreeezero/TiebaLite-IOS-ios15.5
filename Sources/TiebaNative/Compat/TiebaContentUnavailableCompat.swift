//
// TiebaContentUnavailableCompat.swift —— 系统空/错状态（UIContentUnavailableView）在 iOS 15.5 上的落法
//
// 原实现直接吃系统的 `UIContentUnavailableView` / `UIContentUnavailableConfiguration`（iOS 17 起）。
// 底线降到 15.5 后这两个类型在编译期就不可用，因此本文件提供**同名同形**的替身：
//
//   UIContentUnavailableConfiguration  →  TiebaUnavailableConfiguration（值类型，属性名逐条对齐）
//   UIContentUnavailableView           →  TiebaUnavailableView（UIView，configuration 可重复赋值）
//
// 对齐原则（为什么不是"随便画一个"）：
//   · 属性名与嵌套结构（imageProperties / textProperties / secondaryTextProperties /
//     buttonProperties）与系统逐条一致 —— 调用点只改类型名，改法不需要理解排版；
//   · 排版跟系统空态同一套决定：图标 48pt（可被 maximumSize 压小）、标题 headline、
//     说明 subheadline + 次级色、按钮 34pt 高、整体竖排居中、左右不出 16pt；
//   · **内在高度**参与布局：系统视图自带约 87pt 内在高度（750 优先级），各页把它与列表
//     四边同框，靠这条 750 的偏好撑出"空态块"，列表被压回内容高度。本替身同样实现
//     intrinsicContentSize，且 loading（只有转圈）时返回与系统一致的 87pt，保证
//     TiebaHistoryViewController / TiebaForumMembersViewController 里那两条
//     "列表被挤成 87pt" 的约束关系不变。
//

import UIKit

/// 空/错状态的配置（对位 `UIContentUnavailableConfiguration`）。
struct TiebaUnavailableConfiguration {
    struct ImageProperties {
        var tintColor: UIColor?
        var maximumSize: CGSize?

        init() {
            self.tintColor = nil
            self.maximumSize = nil
        }
    }

    struct TextProperties {
        var font: UIFont?
        var color: UIColor?

        init() {
            self.font = nil
            self.color = nil
        }
    }

    struct ButtonProperties {
        var primaryAction: UIAction?
        var tintColor: UIColor?

        init() {
            self.primaryAction = nil
            self.tintColor = nil
        }
    }

    var image: UIImage?
    var imageProperties: ImageProperties
    var text: String?
    var textProperties: TextProperties
    var secondaryText: String?
    var secondaryTextProperties: TextProperties
    var button: UIButton.Configuration?
    var buttonProperties: ButtonProperties
    /// 顶部转圈（对位系统的 `.loading()` 形态）。
    var showsSpinner: Bool

    init() {
        self.image = nil
        self.imageProperties = ImageProperties()
        self.text = nil
        self.textProperties = TextProperties()
        self.secondaryText = nil
        self.secondaryTextProperties = TextProperties()
        self.button = nil
        self.buttonProperties = ButtonProperties()
        self.showsSpinner = false
    }

    /// 空态（图标/标题/说明全空，调用方随后逐项赋值）。
    static func empty() -> TiebaUnavailableConfiguration {
        TiebaUnavailableConfiguration()
    }

    /// 加载态：只有转圈，没有文案（与系统 `.loading()` 同形）。
    static func loading() -> TiebaUnavailableConfiguration {
        var config = TiebaUnavailableConfiguration()
        config.showsSpinner = true
        return config
    }
}

/// 空/错状态视图（对位 `UIContentUnavailableView`）。
final class TiebaUnavailableView: UIView {
    /// 与系统同款的默认图标边长。
    private static let iconSide: CGFloat = 48
    /// 系统 loading 形态的内在高度（各页布局按它算，见文件头）。
    private static let loadingHeight: CGFloat = 87

    private let stack = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private var actionButton: UIButton?
    private var iconWidth: NSLayoutConstraint?
    private var iconHeight: NSLayoutConstraint?

    var configuration: TiebaUnavailableConfiguration {
        didSet { apply() }
    }

    init(configuration: TiebaUnavailableConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        setUp()
        apply()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TiebaUnavailableView 只支持代码创建")
    }

    // MARK: - 装配

    private func setUp() {
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        spinner.hidesWhenStopped = true

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let width = iconView.widthAnchor.constraint(equalToConstant: Self.iconSide)
        let height = iconView.heightAnchor.constraint(equalToConstant: Self.iconSide)
        width.isActive = true
        height.isActive = true
        iconWidth = width
        iconHeight = height

        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true

        detailLabel.numberOfLines = 0
        detailLabel.textAlignment = .center
        detailLabel.adjustsFontForContentSizeCategory = true

        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(detailLabel)

        // 只居中；四边留白用 999 的可破约束：各页把它与列表四边同框，某些态下会被压得
        // 比内容还矮（系统视图在这种情况下也是裁掉内容而不是约束冲突）。
        let leading = stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16)
        let trailing = stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
        let topEdge = stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8)
        let bottomEdge = stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8)
        for edge in [leading, trailing, topEdge, bottomEdge] {
            edge.priority = UILayoutPriority(999)
        }
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            leading,
            trailing,
            topEdge,
            bottomEdge,
        ])
    }

    // MARK: - 应用配置

    private func apply() {
        let config = configuration

        spinner.isHidden = !config.showsSpinner
        if config.showsSpinner {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }

        if let image = config.image {
            iconView.image = image
            iconView.isHidden = false
            iconView.tintColor = config.imageProperties.tintColor ?? .secondaryLabel
            let side: CGFloat
            if let maximum = config.imageProperties.maximumSize {
                side = min(Self.iconSide, min(maximum.width, maximum.height))
            } else {
                side = Self.iconSide
            }
            iconWidth?.constant = side
            iconHeight?.constant = side
        } else {
            iconView.image = nil
            iconView.isHidden = true
        }

        titleLabel.isHidden = config.text?.isEmpty ?? true
        titleLabel.text = config.text
        titleLabel.font = config.textProperties.font
            ?? UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.textColor = config.textProperties.color ?? .label

        detailLabel.isHidden = config.secondaryText?.isEmpty ?? true
        detailLabel.text = config.secondaryText
        detailLabel.font = config.secondaryTextProperties.font
            ?? UIFont.preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = config.secondaryTextProperties.color ?? .secondaryLabel

        rebuildButton()
        invalidateIntrinsicContentSize()
    }

    private func rebuildButton() {
        actionButton?.removeFromSuperview()
        actionButton = nil
        guard let buttonConfig = configuration.button else { return }
        let button = UIButton(
            configuration: buttonConfig,
            primaryAction: configuration.buttonProperties.primaryAction
        )
        if let tint = configuration.buttonProperties.tintColor {
            button.tintColor = tint
        }
        stack.addArrangedSubview(button)
        actionButton = button
    }

    // MARK: - 内在高度（系统视图同样是"内容撑高 + 750 优先级"）

    override var intrinsicContentSize: CGSize {
        var height: CGFloat = 0
        if configuration.showsSpinner { height += 20 }
        if configuration.image != nil {
            height += iconWidth?.constant ?? Self.iconSide
        }
        if !(configuration.text?.isEmpty ?? true) {
            height += 8 + ceil(titleLabel.font.lineHeight)
        }
        if !(configuration.secondaryText?.isEmpty ?? true) {
            height += 8 + ceil(detailLabel.font.lineHeight)
        }
        if configuration.button != nil { height += 8 + 34 }
        if height.isZero {
            // 系统 loading 形态是一条固定高度的空态块，各页布局按 87pt 算（见文件头）。
            height = configuration.showsSpinner ? Self.loadingHeight : 0
        }
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }
}

# TiebaLite 降到 iOS 15.5（iPhone SE 3 可用）

基线：仓库主干 `toamdou/TiebaLite-IOS` + 你给的 `TiebaLite-v2.2.0.ipa`（2.2.0 / build 6，
原来是 `MinimumOSVersion = 17.0`，`DTSDKName = iphoneos26.5`）。

本目录就是**改完的完整工程**，部署底线 `15.5`，iOS 26 的液态玻璃等实现已删除，
`PlugIns/TiebaLiveActivity.appex` 已移除。功能与 UI 与主干保持一致，只有"15.5 上系统根本
不存在的东西"换了落法（详见下面的对照表）。

---

## 一、出 IPA（两条路，任选一条）

### A. 云端（不用 Mac，2 分钟）

1. 把这个目录整体推到自己的 GitHub 仓库（public/private 都行）；
2. 仓库 Settings → Actions → General → 允许 workflow 运行；
3. Actions → 左侧 **Build iOS 15.5 Unsigned IPA** → `Run workflow`（configuration 选 Release）；
4. 跑完在该次运行的 **Artifacts → ipa-ios15.5** 下载，文件名 `TiebaLite-<版本>-ios15.5.ipa`。

工作流里带三道自检，出包即验证：`MinimumOSVersion == 15.5`、产物内**没有** `PlugIns/`、
`.bazelrc`/`BUILD.bazel` 的底线没被人改回去。用的 runner 是 `macos-26`（Xcode 26.x），
和主干一致，只是把部署底线从 17.0 改成 15.5。

### B. 本机 macOS（有 Mac 时最快）

```bash
./build-ios15.5.sh          # = bazel build //:AppStripped --config=ci --config=release + 打包自检
```

产物：`./TiebaLite-2.2.0-ios15.5.ipa`（ad-hoc 签名 = 无签名口径）。

### 装到 SE 3（iOS 15.5）

SideStore / AltStore / ESign / TrollStore 里选这个 ipa 直接装（工具会用你自己的证书重签，
工程不需要任何 Apple 账号或描述文件）。

---

## 二、为什么不是"改 Info.plist 就能装"

`MinimumOSVersion` 只是安装器的一道闸；真正的问题是**编译期**的可用性检查。
主干用 SDK 26 编译、底线 17.0，因此下列 API 是**直接调用**的（没有 `#available`）：

| API | 起始版本 | 主干为什么能编 | 15.5 上会怎样 |
|---|---|---|---|
| `MainActor.assumeIsolated` | iOS 17（SwiftStdlib 5.9） | 底线 17，恒可用 | 编译期报 unavailable |
| `registerForTraitChanges` | iOS 17 | 同上 | 编译期报 unavailable |
| `UIContentUnavailableView` / `...Configuration` | iOS 17 | 同上 | 编译期报 unavailable |
| `UIEditMenuInteraction` / `UIEditMenuConfiguration` | iOS 16 | 底线 17 | 编译期报 unavailable |
| `UISheetPresentationController.Detent.custom(...)` | iOS 16 | 同上 | 编译期报 unavailable |
| `Task.sleep(for:)`（`Duration` 版） | iOS 16 | 同上 | 编译期报 unavailable |
| `UITextViewDelegate.textView(_:editMenuForTextIn:...)` | iOS 16 | 同上 | 编译期报 unavailable |
| `UITextViewDelegate.textView(_:primaryActionFor:...)` + `UITextItem` | iOS 17 | 同上 | 编译期报 unavailable |
| `ActivityKit`（`Activity<...>` / `ActivityAttributes`） | iOS 16.1 | 同上 | 编译期报 unavailable |
| `UIGlassEffect` / `UIGlassContainerEffect` / `.glass()` / `.prominentGlass()` | iOS 26 | 主干用 `#available(iOS 26)` 分档 | 有降级分支，但本次按要求**整段删除** |

> 只改二进制（`minos` 17.0 → 15.5 + 改 Info.plist）在 15.5 上会**一启动就崩**：
> 底线 17.0 编译时 `#available(iOS 17)` 被折叠成"恒真"，那些调用没有运行时判定，
> 15.5 上就是"unrecognized selector / Class not found"。所以必须重新编译 —— 这也是本目录
> 交付的是**源码 + 出包流水线**而不是改过的二进制的原因。

---

## 三、改动清单

### 1) 构建配置

| 文件 | 改动 |
|---|---|
| `.bazelrc` | `build --ios_minimum_os=17.0` → `15.5` |
| `BUILD.bazel` | `minimum_os_version = "17.0"` → `"15.5"`；删掉 `extensions = ["//Extensions/TiebaLiveActivity:extension"]` |
| `TiebaLite/Info.plist` | `LSMinimumSystemVersion` 17.0 → 15.5；删掉 `NSSupportsLiveActivities` / `...FrequentUpdates` |
| `Signing/BUILD.bazel` | 删掉 `profile_ext`（扩展没了） |
| `Extensions/` | **整目录删除**（Live Activity widget，最低 16.1；留在包里会让 15.5 装不上） |
| `.github/workflows/` | `build-ipa.yml`（旧，17.0 口径）→ 换成 `build-ios15.5-ipa.yml` |
| `build-ios15.5.sh` | 新增：本机 macOS 一键出包 |

### 2) 新增兼容层（`Sources/TiebaNative/Compat/`）

| 文件 | 作用 |
|---|---|
| `TiebaPlatformCompat.swift` | ① `MainActor.tiebaAssumeIsolated`（系统实现在 17+，这里同手法：断言主线程 + `unsafeBitCast` 后**同步**调用，不派发、不改时序）；② `tiebaObserveTraits(_:_:_:)`：iOS 17+ 原样转给 `registerForTraitChanges`，15.x 用 `traitCollectionDidChange` 交换实现驱动**同一份**闭包 |
| `TiebaContentUnavailableCompat.swift` | `TiebaUnavailableConfiguration` / `TiebaUnavailableView`：与系统 `UIContentUnavailable*` **同名同形**（`imageProperties/textProperties/secondaryTextProperties/buttonProperties` 逐条对齐、loading 态内在高度 87pt@750 与系统一致），调用点只改类型名 |
| `TiebaEditMenuCompat.swift` | 编辑菜单在 15.5 上的落法：同一批动作改由系统 action sheet 呈现（iPad 自动挂 popover 锚点） |

> `Vendor/Hero` 是独立 module，另加了 `Vendor/Hero/Sources/MainActorIsolationCompat.swift`
> （同一份实现，模块内自足）。

### 3) 逐点改写（56 个文件，相对主干）

- **trait 观察 13 处**：`registerForTraitChanges([UIKit trait…]) { (self: X, _: UITraitCollection) in … }`
  → `tiebaObserveTraits(self, [.userInterfaceStyle …]) { (self: X) in … }`（闭包体一行没动）
  涉及：AppBootstrap / NavigationShell / Home / Explore / Forum / Thread(PostListPage) /
  Settings(About、Theme) / FormListView / FeedRowView / SkeletonView / 首页欢迎页。
- **空态视图 10 个文件**：`UIContentUnavailableView` → `TiebaUnavailableView`（含
  `TiebaStateContentView`、各 Forum/Profile/Thread 页、表单空态单元）；
  `TiebaNotFoundViewController` 的 `contentUnavailableConfiguration`（VC 的 iOS 17 属性）→ 自建空态视图铺满页面。
- **编辑菜单**（`UIEditMenuInteraction`）：正文选词菜单 + 主贴标题长按 → `TiebaEditMenuCompat`；
  `UIEditMenuInteractionDelegate` 整个扩展删除。
- **table/TextDelegate**：`TiebaSelectableLabel` 的 `editMenuForTextIn`（16）标 `@available(iOS 16.0, *)`，
  `primaryActionFor`（17，含 `UITextItem`）标 `@available(iOS 17.0, *)`，并补上 15/16 的
  `shouldInteractWith(_:in:interaction:)` —— "伪装链接确认"这条安全逻辑在 15.5 上**照旧生效**。
- **sheet detents**（`TiebaNavigator`）：iOS 16+ 保留原 `.custom(identifier:resolver:)`；
  15.x 只有 `.medium()/.large()`，按"<0.7 半屏 / ≥0.7 大档"映射，圆角与把手不变。
- **`Task.sleep(for:)` 2 处** → `Task.sleep(nanoseconds:)`。
- **Live Activity 相关**：`Core/LiveActivity/TiebaLiveActivity.swift` 改为**同签名空实现**
  （`start` 恒抛 `.disabled`、`areActivitiesEnabled` 恒 false、update/end/endAll 空转），
  属性/状态值类型去掉 `ActivityKit` 依赖。调用方（`TiebaSignService` / `TiebaAppBootstrap` /
  `TiebaOKSignViewController`）**一行未改**。

### 4) 按要求删除的 iOS 26 内容

| 位置 | 删除的东西 | 15.5 上用的 |
|---|---|---|
| `TiebaGlassContainerView` | `UIGlassContainerEffect()`、`UIGlassEffect(style:tintColor:)` + 白色高光边 | `UIVisualEffectView(effect: nil)`（容器本来就无材质）+ `UIBlurEffect(.systemUltraThinMaterial / .systemThinMaterial)` + tint 落 `contentView` 底色（原代码 17/18 分档配方） |
| 9 处按钮配置 | `.glass()` / `.prominentGlass()` | `.gray()` / `.filled()`（原代码已写好的 else 侧，逐值不变） |
| `TiebaNavBarChrome` | `UIScrollEdgeEffect.bottomEdgeEffect` 关闭逻辑 | 直接返回 false（这层在 15.5 上不存在） |
| `TiebaNavigationShell` | `tabBarMinimizeBehavior`（滚动收纳） | 底栏常驻；设置项与偏好保留 |
| `TiebaNavigator` | iOS 26.1 的 `UITab.selectedImage` KVC 落值 | 经典 `UITabBarItem(selectedImage:)` |
| `TiebaTransitionDeviceMetrics` | iOS 26 的导航条高度 20pt / 键盘 -1pt 修正 | 经典 21/34pt 与经典键盘高度 |
| `TiebaCAAnimationUtils` | `tiebaMake26SpringAnimation`（iOS 26 系统弹簧）及其两处分支 | 经典 `CASpringAnimation` 参数 / 贝塞尔回退 |

---

## 四、功能对照（相对 2.2.0 / iOS 17+）

| 能力 | iOS 15.5 上 |
|---|---|
| 首页/进吧/消息/我的、搜索、楼中楼、图片查看器、发帖回帖、签到、自动签到后台任务、主题与字号、触觉、深链、分享、保存图片 | **完全一致** |
| 液态玻璃材质 | 换成经典超薄材质模糊（深浅自适应不变） |
| 玻璃按钮 / 圆钮 | `gray` / `filled`（原代码的低版本档） |
| 深浅模式跟随、字号档切换的实时重排 | **同一份 handler**，改由 `traitCollectionDidChange` 触发（15.x 唯一可用回调） |
| 空态 / 错误态 / 加载态排版 | 自建替身，图标 48pt、标题 headline、说明 subheadline + 次级色、按钮 34pt、loading 87pt |
| 正文选词 / 复制 / 全选 / 查询 / 分享；标题长按复制 | **动作全在**，面板从"选区浮动菜单"变成系统 action sheet（15.x 无 `UIEditMenuInteraction`） |
| 伪装链接确认（U+202E 同形字） | **照旧生效**（走 15/16 的 `shouldInteractWith` 钩子） |
| 表单弹出高度 | 15.x 只有半屏/大档两档（比例值按 0.7 分界映射） |
| Live Activity（灵动岛/锁屏签到进度） | **不可用**（ActivityKit 最低 16.1，系统侧无此展示位）；签到结果仍由页内 pill + 本地通知给到 |
| 底栏滚动收纳（iOS 26） | 不可用，底栏常驻 |

---

## 五、自检结果（本目录已在 Windows 侧做过静态校验）

- 全仓扫描 `Sources/ + Vendor/ + TiebaLite/`：`UIGlassEffect` / `UIGlassContainerEffect` /
  `.glass()` / `.prominentGlass()` / `UIEditMenuInteraction` / `registerForTraitChanges`（业务代码）/
  `UIContentUnavailable*` / `contentUnavailableConfiguration` / `tabBarMinimizeBehavior` /
  `bottomEdgeEffect` / `Task.sleep(for:)` / `import ActivityKit` / `#available(iOS 26` —— **业务代码 0 命中**
  （只剩 Compat 里对系统 API 的转发，以及注释里的说明）。
- 762 个 Swift 文件做过注释/字符串剥离后的括号配对检查：除 `TiebaForumAPI.swift` 里
  原始代码的 raw string（`#"..."#`，主干同样报）外**无结构破坏**。
- `MainActor.assumeIsolated` 33 处（含 Hero 3 处）全部换成自实现；13 处 trait 登记的闭包签名已统一成单参。

> 唯一无法在 Windows 上做的是"真正编译一次"：Swift + UIKit 必须 Xcode。
> 上面两条路径（Actions / 本机 `build-ios15.5.sh`）就是编译关口；工作流里的三道校验会在出包时
> 直接判定底线与扩展是否符合 15.5。若首次编译报某处 `is only available in iOS 16.0 or newer`，
> 报错行就是遗漏点，按 Compat 里同一套办法（加 `#available` + 走低版本分支）补一处即可。

---

## 六、目录速查

```
.bazelrc                       iOS 15.5 底线
BUILD.bazel                    minimum_os_version = 15.5，无 extensions
Sources/TiebaNative/Compat/    三个兼容层（trait / 空态 / 编辑菜单）
Sources/TiebaNative/Core/LiveActivity/   Live Activity 空实现 + 去 ActivityKit 的值类型
Vendor/Hero/Sources/MainActorIsolationCompat.swift   Hero 模块的隔离断言
.github/workflows/build-ios15.5-ipa.yml              云端出包（含产物校验）
build-ios15.5.sh                                     本机 macOS 一键出包
docs/ios15.5-port.md                                 本文
```

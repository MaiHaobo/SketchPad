# 墨迹 SketchPad — 从零到 iPhone 安装 · 保姆级教程

> 适用场景：**没有 Mac、只有免费 Apple ID**，借到一台 Mac 后把 App 装进自己的 iPhone。
> 全程 **0 元**，不需要付费开发者账号。App 能用 **7 天**，到期重装一次即可。

---

## 零、开始之前：检查清单

### 你要准备的东西

| 物品 | 说明 |
|---|---|
| 一台 Mac | macOS 13 Ventura 或更新。MacBook / iMac / Mac mini 都行 |
| 一根数据线 | iPhone 原装线或 MFi 认证线。**必须是数据线，纯充电线不行** |
| 你的 iPhone | iOS 16 或更新 |
| 免费 Apple ID | 就是平时登录 App Store 的那个账号，不用额外注册 |
| 项目文件 | 就是本教程旁边的 `SketchPad` 整个文件夹 |

### 检查这台 Mac 够不够新

点屏幕左上角  → **关于本机**，看 **macOS 版本**：

- 13 (Ventura) / 14 (Sonoma) / 15 (Sequoia) / 26 → ✅ 可以
- 12 (Monterey) 或更低 → ⚠️ 需要先升级系统，或改用 [Xcode 14.3.1](https://developer.apple.com/download/all/)（用下面的"调整部署目标"方法）

### 检查 iPhone 系统版本

iPhone → **设置 → 通用 → 关于本机 → iOS 版本**：
- 16.0 或更高 → ✅ 直接可用
- 低于 16.0 → 需要做本文档 **附录 A** 的"降低部署目标"

---

## 一、把项目文件拷到 Mac

### 方法 1：U 盘（最稳妥）

1. 把 `SketchPad` 整个文件夹拷进 U 盘
2. U 盘插到 Mac，把 `SketchPad` 拖到 **桌面**（Desktop）

> ⚠️ **关键**：一定要放在**桌面或文稿**这类你的个人目录下。
> **不要**放在 `/Applications`、`/Library` 或任何系统目录，否则 Xcode 会因为权限问题报一堆奇怪的错。

### 方法 2：AirDrop（有 Mac 和 iPhone 时最快）

从 iPhone 隔空投送到 Mac，文件会落到 **下载** 文件夹。

### 方法 3：GitHub 中转

如果项目已经推到 GitHub（见另一份说明），在 Mac 上：

```bash
cd ~/Desktop
git clone https://github.com/<你的用户名>/SketchPad.git
```

### 拷完检查一下结构

在访达里打开 `SketchPad` 文件夹，应该看到：

```
SketchPad/
├── README.md
├── SketchPad.xcodeproj          ← 这个是工程文件
└── SketchPad/
    ├── SketchPadApp.swift
    ├── Info.plist
    ├── Models/
    ├── Views/
    └── Assets.xcassets/
```

> ❗ **常见错误**：如果你的文件夹是 `SketchPad/SketchPad/SketchPad.xcodeproj`（多套了一层），
> 或者只剩一个 `SketchPad` 文件夹里面直接就是 `.swift` 文件——说明拷贝时层级压平或多套了。
> 请确认 `SketchPad.xcodeproj` 和 `SketchPad`（源码文件夹）是**并列同级**的。

---

## 二、安装 Xcode

### 安装

1. 打开 **App Store**（在启动台或应用程序里找）
2. 搜索 **Xcode**
3. 点 **获取** → **安装**

> ⏱ **注意**：Xcode 有 10 GB 左右，下载可能要 30 分钟到 2 小时，取决于网速。
> 这是整个流程最耗时的部分，可以先去泡杯茶。

### 首次启动（必做，跳过会报错）

1. 安装完后，在 **启动台** 里找到 Xcode，点开
2. 会弹出协议窗口，点 **Agree**
3. 输入 Mac 的登录密码，点 **安装附加组件**（Install Additional Components）
4. 等它跑完（大约 5-10 分钟），然后 **退出 Xcode**（⌘Q）

> ❗ **这一步不能跳**。跳过的话后面编译会报 `xcrun: error: invalid active developer path`。

---

## 三、用 Xcode 打开项目

1. 到桌面找到 **SketchPad** 文件夹
2. 双击里面的 **SketchPad.xcodeproj**

> 图标是个蓝色的 Xcode 图标（里面一个锤子形状的尺规）。
> 如果双击后弹出"无法打开，因为它来自身份不明的开发者"，右键点它 → **打开** → 再点 **打开** 即可。

3. Xcode 打开后，你会看到左侧是一堆文件列表，中间是代码

### 确认能看见项目和模拟器

- 左上角有一排小图标，找到设备选择器（默认可能显示 **SketchPad > Any iOS Device** 之类的文字）
- 点开它，应该能看到一列 **iPhone 16 Pro**、**iPhone 16**、**iPhone SE** 这样的模拟器选项

**如果看不到任何模拟器**（下拉菜单是空的）：

1. 上方菜单 **Xcode → Settings**（或按 ⌘,）
2. 选 **Platforms** 标签
3. 找到 **iOS**，点它右边的 **下载** 按钮（约 7 GB）
4. 下载完再回来看设备列表

---

## 四、配置签名（最关键的一步，90% 的报错都在这里）

### 4.1 找到签名设置

1. 点 Xcode 左侧文件列表**最顶上**那个蓝色的 **SketchPad** 图标（不是文件夹，是项目本身）
2. 中间区域会出现一排标签：**General / Signing & Capabilities / Resource Tags / Info / Build Settings / Build Phases / Build Rules**
3. 点 **Signing & Capabilities**

### 4.2 打开自动签名

你会看到一个 **Team** 下拉框，现在是空的。往下看有个勾选框：

- ☑️ **Automatically manage signing** ← **确认这个勾是打上的**

### 4.3 登录你的 Apple ID

1. 点 **Team** 下拉框 → 选 **Add an Account...**
2. 弹出窗口，选左侧 **Apple ID**（如果已经在里面了就直接跳过）
3. 点 **+** 号 → 选 **Apple ID** → **Continue**
4. 输入你的 Apple ID 邮箱和密码 → **Next**
   - 如果开了双重认证，手机会收到 6 位验证码，输进去
5. 登录成功后，**关闭这个小窗口**

### 4.4 选择你的账号

回到 **Signing & Capabilities** 页面：

1. 再点 **Team** 下拉框
2. 现在能看到你的名字 + **(Personal Team)** —— **选它**
3. 等几秒，Xcode 会自动生成证书

### 4.5 如果报了红色错误

| 错误提示 | 原因 | 解决办法 |
|---|---|---|
| `Failed to create provisioning profile` | Bundle ID 被人占了 | 看下面的 **4.6 改 Bundle ID** |
| `No signing certificate "iOS Development" found` | 证书没生成出来 | 点 `Manage Certificates...` → 左下角 **+** → **Apple Development** → 完成 |
| `The app ID "com.sketchpad.ink" cannot be registered` | 同上 | 改 Bundle ID |
| `Communication with Apple failed` | 网络问题 | 换个网络，或挂梯子重试 |

### 4.6 改 Bundle ID（如果上面提示被占用）

Bundle ID 是 App 的唯一身份证，必须全球不重复。做法：

在 **Signing & Capabilities** 页面找到 **Bundle Identifier** 输入框，把：

```
com.sketchpad.ink
```

改成（把 `你的名字拼音` 换成你自己的，别用中文）：

```
com.你的名字拼音.sketchpad
```

例如：`com.zhangsan.sketchpad`

改完后 Xcode 会自动重新申请签名，等几秒红色错误就消失了。

> ✅ **成功标志**：页面上面显示 `Signing Certificate: Apple Development: 你的邮箱 (XXXXXXXX)`，
> 而且**没有任何红色报错**。看到这一步你就成功了 90%。

---

## 五、让 iPhone 信任这台 Mac

### 5.1 连接手机

1. 用数据线把 iPhone 插到 Mac
2. iPhone 屏幕上会弹出 **"要信任此电脑吗？"** → 点 **信任** → 输入 iPhone 锁屏密码
3. **保持手机解锁状态**（锁屏会导致下面步骤失败）

### 5.2 在 Xcode 里选中你的手机

1. 回到 Xcode，点左上角那个设备下拉框
2. 现在除了模拟器，还会多出一个 **你的 iPhone 名字**（名字下面写着 "iOS 16.x" 之类）
3. **选中它**

> 如果没出现你的设备：
> - 拔了线重新插
> - 手机上重新点一次"信任"
> - Xcode 菜单 **Window → Devices and Simulators** 里看设备有没有识别到

### 5.3 开启开发者模式（iOS 16 及以上必做）

1. iPhone → **设置 → 隐私与安全性**
2. 划到最底下，找到 **开发者模式**（Developer Mode）
3. 打开它 → 会提示要重启 → 点 **重新启动**
4. 重启后会出现确认弹窗 → 输入锁屏密码 → 点 **打开**

> ❗ **如果找不到"开发者模式"这一项**：说明还没被激活过。回到 Xcode 尝试运行一次（第六步），
> 报错后再回来看，这个菜单项就出现了。

---

## 六、编译并安装

1. 确认顶部设备选的是 **你的 iPhone**
2. 按 **⌘R**（或点左上角的 ▶️ 播放按钮）

### 接下来会发生什么

1. Xcode 顶部会出现进度条，写着 **Building...** —— 第一次编译要 1-3 分钟
2. 然后写着 **Installing to iPhone...**
3. iPhone 主屏幕上出现一个叫 **墨迹** 的图标，图标是一支白色铅笔
4. App 自动启动 ✅

### 如果 App 启动后立刻闪退

这是**没信任证书**导致的，做第七步。

---

## 七、在 iPhone 上信任这个 App（必须做）

1. App 装上去后，第一次点开**会提示"不受信任的开发者"**
2. iPhone → **设置 → 通用 → VPN与设备管理**
3. 在 **开发者 App** 一栏下，找到你的 Apple ID 邮箱
4. 点它 → 点 **信任 "你的邮箱"** → 再点一次 **信任**
5. 回到主屏幕，点开 **墨迹**，正常使用 ✅

---

## 八、7 天后过期怎么办

免费 Apple ID 签发的证书只有 **7 天**有效期。到期后 App 打不开，提示"无法验证 App"。

**续期方法**（每次不到 1 分钟）：

1. 插上数据线，打开 Xcode
2. 打开 `SketchPad.xcodeproj`，确认设备选的是你的 iPhone
3. 按 **⌘R**

完了。App 上的画作数据**不会丢**（存在 App 沙盒的 Documents 目录里，重装会保留）。

> 💡 **想省事**：买个 $99/年的付费开发者账号，证书有效期变成 1 年，还能用 TestFlight 分发。

---

## 附录 A：降低部署目标（老系统用）

如果你的 Mac 系统版本低（装不了 Xcode 15），或者 iPhone 低于 iOS 16：

1. Xcode 左侧点最上面蓝色 **SketchPad** 图标
2. 选 **Build Settings** 标签
3. 右上角搜索框输入 `deployment`
4. 找到 **iOS Deployment Target**，把值改成你的 iPhone 系统版本（比如 `15.0`）
5. 同时改 **两处**：`Project` 一个、`Targets → SketchPad` 一个（搜索框下方有两个区块）
6. 按 ⌘R 重试

> ⚠️ 本项目用了 iOS 16 的 API（`.presentationDetents`、`NavigationStack`、`GridItem` 等），
> 降到 15.0 后如果报错，把错误消息发我，我来改代码适配。

---

## 附录 B：开启 iCloud 同步（可选）

画作默认存在手机本地。想让 iPhone 和 iPad 之间自动同步画作，需要开启 iCloud：

### B.1 添加 iCloud Capability

1. Xcode 里点左侧最上面的蓝色 **SketchPad** 项目图标
2. 选 **Signing & Capabilities** 标签
3. 左上角点 **+ Capability**（在 Team 那一行的左边）
4. 弹出搜索框，输入 `icloud`，双击 **iCloud**
5. 页面下方会出现 **iCloud** 区块，勾选：
   - ☑️ **Cloud Documents**
   - Container 列表里应该能看到 `iCloud.com.sketchpad.ink`
     （如果只有 `Use default container` 或空的，点下面 **+** 号新建，名称必须是 `iCloud.com.sketchpad.ink`）

> ⚠️ **名称必须一字不差**。代码里写死了这个标识符，改了名会导致同步不工作。
> 如果你想用别的名字，需要同步修改 `SketchPad/Models/ArtworkStorage.swift` 里的
> `containerIdentifier` 常量。

### B.2 重新运行

按 **⌘R** 重新安装。

### B.3 验证是否生效

打开 App → 点左上角的画廊图标 → 看**顶部状态条**：

| 显示 | 含义 |
|---|---|
| 🔵 `iCloud 同步 · 已同步` | ✅ 成功了 |
| ⚪️ `iCloud 未开启 · 画作仅保存在本机` | ❌ 没生效，检查下面 |

**没生效的排查顺序：**

1. 手机上 **设置 → 你的名字 → iCloud** 是否已登录？（没登录就登一下）
2. 手机的 **设置 → 你的名字 → iCloud → iCloud Drive** 是否开着？
3. Xcode 里 iCloud 区块的 Container 名字对不对？
4. 点一下状态条可以手动刷新

### B.4 注意事项

- **首次同步要等一会**：已有画作需要上传，有几秒到几十秒延迟
- **模拟器测试要先登录 iCloud**：模拟器 → 设置 → 登录 iPhone → 输入 Apple ID，
  否则会走本地降级模式
- **免费 Apple ID 也支持 iCloud**：只要在 Xcode 里选了 Personal Team，iCloud 功能可以用
- **数据不会丢**：iCloud 同步失败时 App 自动降级为本地保存，画作依然安全

---

## 附录 C：项目文件怎么打包发给别人

在访达里：

1. 右键 `SketchPad` 文件夹 → **压缩 "SketchPad"**
2. 得到 `SketchPad.zip`，可以微信/邮件发出去
3. 对方拿到后解压，从第二步开始做即可

> ❗ 注意：只压缩**最外层**的 `SketchPad` 文件夹（里面同时有 `.xcodeproj` 和源码文件夹）。
> 不要只压 `.xcodeproj`，那样会缺源码文件。

---

## 常见问题速查表

| 现象 | 原因 | 解决 |
|---|---|---|
| 双击 `.xcodeproj` 没反应 | 没装 Xcode | 回到第二步 |
| 打开后左侧文件全是红的 | 拷贝时层级错了 | 重新拷贝，保证 `.xcodeproj` 和源码文件夹同级 |
| `Building...` 卡住不动 | 首次编译慢 | 等 3-5 分钟；超过 10 分钟就 ⌘Q 退出重来 |
| 每行代码都报红色错误 | 部署目标或 SDK 问题 | 做附录 A |
| 装了但打不开 | 没信任证书 | 做第七步 |
| 找不到"开发者模式" | 未激活 | 先按 ⌘R 跑一次，失败后再看设置 |
| 手机连上没反应 | 线是充电线 / 没点信任 | 换线，重新点"信任" |
| 提示磁盘空间不足 | Xcode 太占地方 | 需要至少 40 GB 空闲空间 |
| 画廊顶部显示"仅保存在本机" | iCloud 没开启 | 做附录 B |
| 报错 `No such a provisioning profile` 且提到了 iCloud | Container 名字不对 | 检查附录 B.1 第 5 步 |

---

## 一句话总结流程

```
拷文件夹到桌面 → 装 Xcode 并启动一次 → 打开 .xcodeproj
→ Signing 里登录 Apple ID 选 Personal Team（报错就改 Bundle ID）
→ 手机连线信任 → 开开发者模式 → ⌘R → 手机上信任证书 → 完成
→（可选）加 iCloud Capability 开启多设备同步
```

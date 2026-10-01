# 用 GitHub 免费编译 IPA 并装到 iPhone · 保姆级教程

> **适用场景**：没有 Mac，只有 iPhone + 一台 Windows/Linux 电脑。
> **成本**：0 元（GitHub 公开仓库的 macOS 机器免费不限量）。
> **原理**：把代码推到 GitHub，让 GitHub 的云服务器帮你编译、签名，产出 `.ipa` 下载。

---

## 目录

- [零、先搞清楚几件事](#零先搞清楚几件事)
- [一、准备签名材料](#一准备签名材料)
- [二、把材料转成 base64](#二把材料转成-base64)
- [三、在 GitHub 配置 Secrets](#三在-github-配置-secrets)
- [四、运行编译](#四运行编译)
- [五、下载 IPA](#五下载-ipa)
- [六、把 IPA 装进 iPhone](#六把-ipa-装进-iphone)
- [七、常见报错排查](#七常见报错排查)
- [附录 A：没有证书怎么办](#附录-a没有证书怎么办)
- [附录 B：证书能装几台设备](#附录-b证书能装几台设备)
- [附录 C：怎么查看描述文件里的 UDID](#附录-c怎么查看描述文件里的-udid)

---

## 零、先搞清楚几件事

### 0.1 编译和签名是两件事

| 环节 | 做什么 | 谁来做 |
|---|---|---|
| **编译** | 把 `.swift` 源码变成 iOS 能运行的机器码 | GitHub Actions 的 Mac |
| **签名** | 给编译产物盖个章，iOS 才允许安装 | 你的证书（`.p12` + `.mobileprovision`） |

**两个环节都得有。** 光有证书没编译，是个空壳；光编译没签名，iPhone 拒绝安装。

### 0.2 你需要两个文件，缺一不可

| 文件 | 是什么 | 通俗理解 |
|---|---|---|
| `xxx.p12` | 证书 + 私钥的打包文件 | **你的身份证**，证明"这个 App 是我签的" |
| `xxx.mobileprovision` | 描述文件 | **通行证**，写明"这个证书能签哪个 App、能装哪几台设备" |

> ⚠️ **重点**：很多人从卖家那里只拿到 `.p12`，**没有 `.mobileprovision`**，那签不了名。
> 这两个文件是配对使用的，务必找卖家要齐。

### 0.3 关于云小朵的证书

如果你买的是"个人证书"，务必确认拿到：
- ✅ `.p12` 文件
- ✅ `.p12` 的**密码**
- ✅ 配套的 `.mobileprovision` 文件

**任何一样缺失，先找卖家补齐再往下走。**

---

## 一、准备签名材料

把卖家给你的文件放到电脑上，确认这三个东西都在：

```
📁 证书文件/
   ├── certificate.p12          ← 证书
   ├── certificate.mobileprovision   ← 描述文件
   └── 密码.txt                  ← p12 密码（通常卖家会给）
```

### 1.1 先验证文件能不能用

`.mobileprovision` 其实是个 plist 文件，可以直接查看内容。

**Windows（用记事本或在线工具）**：
- 如果文件打开是乱码，说明是正常的二进制格式
- 可以用 [这个在线工具](https://www.icloud.com/shortcuts) 或 `Plist Editor` 查看

**Mac**（如果你能借到）：
```bash
security cms -D -i certificate.mobileprovision
```

**验证要点**（能看到这些就说明文件正常）：
- `UUID` ← 描述文件唯一号，后面要用
- `TeamIdentifier` ← 团队 ID
- `ExpirationDate` ← **过期时间，过期了就签不了**
- `ProvisionedDevices` ← 允许安装的设备 UDID 列表

---

## 二、把材料转成 base64

GitHub Secrets 只能存文本，所以要把**二进制文件**转成 **base64 文本**。

### 2.1 Windows（PowerShell）

打开 PowerShell，进到文件所在目录：

```powershell
# 切换到文件所在目录（改成你自己的路径）
cd C:\Users\你的用户名\Desktop\证书文件

# 转 p12（生成 certificate-p12.txt）
[Convert]::ToBase64String([IO.File]::ReadAllBytes("certificate.p12")) | Set-Content -NoNewline certificate-p12.txt

# 转描述文件（生成 certificate-pp.txt）
[Convert]::ToBase64String([IO.File]::ReadAllBytes("certificate.mobileprovision")) | Set-Content -NoNewline certificate-pp.txt

# 看看结果（应该是一长串字母数字）
Get-Content certificate-p12.txt | Select-Object -First 1 | ForEach-Object { $_.Substring(0, 80) }
```

### 2.2 Mac / Linux

```bash
cd ~/Desktop/证书文件

# 转 p12
base64 -i certificate.p12 -o certificate-p12.txt        # Mac
base64 -w 0 certificate.p12 > certificate-p12.txt       # Linux

# 转描述文件
base64 -i certificate.mobileprovision -o certificate-pp.txt    # Mac
base64 -w 0 certificate.mobileprovision > certificate-pp.txt   # Linux

# 检查（应该是一行超长字符串，没有换行）
wc -c certificate-p12.txt certificate-pp.txt
```

### 2.3 用哪个 txt 文件？

| 生成的 txt | 对应 GitHub Secret 名字 |
|---|---|
| `certificate-p12.txt` | `BUILD_CERTIFICATE_BASE64` |
| `certificate-pp.txt` | `BUILD_PROVISION_PROFILE_BASE64` |
| 卖家给的 p12 密码（明文） | `P12_PASSWORD` |
| 自己随便设一个（如 `sketchpad123`） | `KEYCHAIN_PASSWORD` |

> 💡 **技巧**：base64 文本很长（几 KB），用记事本打开后 `Ctrl+A` → `Ctrl+C` 全选复制。

---

## 三、在 GitHub 配置 Secrets

### 3.1 进入设置页面

1. 打开你的仓库：`https://github.com/MaiHaobo/SketchPad`
2. 点顶部的 **Settings**（设置）
3. 左侧菜单往下找 → **Secrets and variables** → **Actions**

（直达链接：`https://github.com/MaiHaobo/SketchPad/settings/secrets/actions`）

### 3.2 添加四个 Secret

点右上角绿色按钮 **New repository secret**，逐个添加：

| Name（必须一模一样） | Secret（粘贴内容） |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | `certificate-p12.txt` 的全部内容 |
| `P12_PASSWORD` | 你的 p12 密码 |
| `BUILD_PROVISION_PROFILE_BASE64` | `certificate-pp.txt` 的全部内容 |
| `KEYCHAIN_PASSWORD` | 自己设一个，如 `sketchpad123` |

**添加步骤**（重复四次）：
1. 点 **New repository secret**
2. **Name** 框填入表格里的名字（注意大小写，全部大写）
3. **Secret** 框粘贴内容
4. 点 **Add secret**

### 3.3 确认添加成功

四个都加好后，页面应该显示：

```
✅ BUILD_CERTIFICATE_BASE64        Updated now
✅ P12_PASSWORD                    Updated now
✅ BUILD_PROVISION_PROFILE_BASE64  Updated now
✅ KEYCHAIN_PASSWORD               Updated now
```

> ⚠️ **安全提示**：Secret 添加后就看不见内容了（只能覆盖），这是正常的。
> 千万别把证书内容直接写进代码文件——公开仓库会被人看到。

---

## 四、运行编译

### 4.1 触发编译

1. 打开仓库页面，点顶部 **Actions** 标签
2. 左侧列表点 **Build IPA**
3. 右侧有个 **Run workflow** 下拉按钮 → 点它
4. **导出方式**选 `ad-hoc`（默认）
5. 点绿色的 **Run workflow**

### 4.2 看进度

刷新页面，会出现一条运行记录，点进去能看到实时日志：

| 步骤 | 说明 |
|---|---|
| 📥 检出代码 | 拉取仓库文件 |
| 🛠 选择 Xcode | 选 macOS 编译工具链 |
| 🔐 导入签名证书 | 安装你的证书 ↓ **这步最容易出错** |
| 📝 生成 ExportOptions.plist | 自动读取描述文件里的 Team ID |
| 🔨 编译 (xcodebuild archive) | **主要耗时步骤**，约 3-8 分钟 |
| 📦 导出 IPA | 打包成 ipa |
| ⬆️ 上传 IPA | 传到 Actions 供下载 |

**总耗时约 5-10 分钟。**

### 4.3 看结果

- **绿勾 ✅** = 成功，去下一步下载
- **红叉 ❌** = 失败，点开失败的那一步看报错，对照[第七章](#七常见报错排查)

---

## 五、下载 IPA

### 5.1 从 Actions 下载

1. 点进成功的那次运行记录
2. 页面**最下方**找到 **Artifacts** 区域
3. 点 **SketchPad-IPA** 下载（是个 zip）
4. 解压得到 `SketchPad.ipa`

> ⏰ **有效期 30 天**，过期就重新跑一次 Actions（配置还在，点一下就行）。

### 5.2 从 Release 下载（如果你打了 tag）

如果推送了 `v1.0` 这样的 tag，会自动创建 Release：

1. 仓库首页右侧 **Releases**
2. 点进对应版本
3. 在 **Assets** 里直接下载 `.ipa`

---

## 六、把 IPA 装进 iPhone

iPhone 不能像安卓那样直接装 APK，需要借助工具。以下三种任选。

### 方案 A：AltStore（推荐，可自动续签）

适合长期使用，能自动重签避免 7 天过期。

1. **电脑端**：下载 [AltServer](https://altstore.io/)（Windows/Mac 都有）
2. **iPhone 端**：App Store 搜索安装 **AltStore**
3. 用数据线连电脑，AltServer 菜单栏选 `Install AltStore → 你的设备`
4. iPhone 提示信任后，打开 AltStore
5. **My Apps** → 左上角 `+` → 选下载的 `SketchPad.ipa`
6. 输入 Apple ID 密码，等待安装完成

> 需要 iPhone 开启 **设置 → 隐私与安全性 → 开发者模式**（iOS 16+）。

### 方案 B：Sideloadly（最简单，一次性）

1. 电脑下载 [Sideloadly](https://sideloadly.io/)
2. iPhone 用数据线连电脑
3. 打开 Sideloadly，把 `SketchPad.ipa` 拖进去
4. **Apple ID** 填你的账号（或用证书签名方式）
5. 点 **Start**，等进度条走完
6. iPhone 上 **设置 → 通用 → VPN与设备管理 → 信任**

### 方案 C：爱思助手（国内用户熟悉）

1. 电脑装 [爱思助手](https://www.i4.cn/)
2. iPhone 连接后，进入 **应用游戏 → 导入安装**
3. 选择 `SketchPad.ipa`
4. 用爱思的**签名功能**处理后再安装

### 装好后打不开？

iOS 会拦截未受信任的开发者：

**设置 → 通用 → VPN与设备管理 → 找到你的开发者账号 → 点「信任」**

然后就能打开了。

---

## 七、常见报错排查

### 错误 1：`No signing certificate "iOS Development" found`

**原因**：`.p12` 没导入成功，或密码错了。

**排查**：
- 确认 `P12_PASSWORD` 填的是**证书密码**，不是 GitHub 密码
- 密码区分大小写，别多空格
- 重新生成 base64（转换时用了带换行的版本会出问题）

### 错误 2：`No profile for team ... matching ... found`

**原因**：描述文件的 Bundle ID 和工程里的对不上。

**排查**：
- 打开 `.mobileprovision` 看 `application-identifier`，格式类似 `XXXXXXXXXX.com.sketchpad.ink`
- 后半段就是登记的 Bundle ID
- 我们的 workflow 会**自动对齐**，如果还报错，检查描述文件是否真实有效

### 错误 3：`Provisioning profile doesn't include the application-identifier entitlement`

**原因**：App 用到的权限（如 iCloud）描述文件里没开。

**排查**：
- workflow 已内置**自动降级**：首次失败会移除 `entitlements` 重试
- 如果降级后成功，说明你的证书不支持 iCloud
- **想用 iCloud 同步功能**：需要付费开发者账号，或确认证书已包含 iCloud 能力

### 错误 4：`The certificate used to sign has expired` / 描述文件过期

**原因**：证书或描述文件超过有效期。

**排查**：
- 个人证书通常 **1 年**有效期，免费账号 **7 天**
- 找卖家换新证书，或走[附录 A](#附录-a没有证书怎么办)重新生成

### 错误 5：`Unable to install - This app cannot be installed because its integrity could not be verified`

**原因**：设备 UDID 不在描述文件的 `ProvisionedDevices` 列表里。

**排查**：
- 个人证书通常绑定**特定几台设备**
- 查[附录 C](#附录-c怎么查看描述文件里的-udid)确认你的 iPhone 是否在列表里
- 不在的话，把 UDID 发给卖家重新生成描述文件

### 错误 6：`xcodebuild: error: SDK "iphoneos" cannot be located`

**原因**：macOS runner 的 Xcode 版本问题（少见）。

**排查**：
- 检查 workflow 第 2 步「选择 Xcode」的日志
- 如持续失败，可以改成 `runs-on: macos-13`

### 错误 7：编译超时

**原因**：`timeout-minutes: 40` 耗尽（极少见）。

**排查**：
- 正常 5-10 分钟就完成
- 超时多半是卡在证书导入或网络，看日志定位

---

## 附录 A：没有证书怎么办

如果没有 `.p12`，可以自己生成（**免费 Apple ID 也能做**）：

1. 借一台 Mac，打开 **钥匙串访问**
2. 菜单 **钥匙串访问 → 证书助理 → 创建证书**
3. 名称填 `SketchPad Dev`，身份选**自签名根证书**
4. 右键导出的证书 → **导出** → 存为 `.p12`，设个密码
5. **描述文件**：
   - 登录 [developer.apple.com](https://developer.apple.com/account)
   - 免费账号也能创建 **Development** 描述文件
   - 需要先登记设备 UDID

**免费账号限制**：签名有效期 **7 天**，到期重新签。装 3 台设备上限。

---

## 附录 B：证书能装几台设备

| 证书类型 | 有效期限 | 设备数 | 成本 |
|---|---|---|---|
| 免费 Apple ID | 7 天 | 3 台 | 0 元 |
| 个人开发者 | 1 年 | 100 台 | $99/年 |
| 企业证书 | 1 年 | 不限 | $299/年（灰色渠道有风险） |

**个人证书**（你买的这种）通常绑定卖家登记的几台设备 UDID，买之前问清楚能不能加自己的设备。

---

## 附录 C：怎么查看描述文件里的 UDID

### 电脑上查

```bash
# Mac
security cms -D -i certificate.mobileprovision | grep -A 20 ProvisionedDevices

# Linux（需先装 docker 或 python 工具）
python3 -c "
from pathlib import Path
import plistlib
data = Path('certificate.mobileprovision').read_bytes()
# 跳过 CMS 封装头，从 plist 开始读
start = data.find(b'<?xml')
print(plistlib.loads(data[start:].split(b'</plist>')[0] + b'</plist>'))
"
```

### iPhone 上查自己的 UDID

1. 电脑装 **iTunes**（或爱思助手）
2. 连接 iPhone
3. 点设备图标 → 摘要页 → 点击**序列号**会切换成 **UDID**
4. 右键复制

**或者**用 Safari 打开 [udid.tech](https://udid.tech/) 这类在线工具，按提示安装描述文件获取。

---

## 总结检查清单

推到 GitHub → 配置 Secrets → 跑 Actions → 下载 IPA → 装进 iPhone

- [ ] 手里有 `.p12` + `.mobileprovision` + 密码
- [ ] 三个文件转成 base64（p12 和 pp 各一个 txt）
- [ ] GitHub Secrets 配好 4 个（注意名字全大写）
- [ ] Actions 跑通，拿到 `SketchPad.ipa`
- [ ] iPhone 装好并**信任开发者**
- [ ] 打开 App，能正常画画

---

## 还有问题？

1. 先看[第七章](#七常见报错排查)对号入座
2. 点开 Actions 失败的日志，复制关键报错
3. 联系：**3602246802@qq.com**

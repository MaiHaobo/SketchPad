#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  SketchPad · 云端编译打包脚本（在 GitHub Actions 的 macOS 机器上运行）
#
#  由 .github/workflows/build-ipa.yml 调用，需要的 Secrets：
#    BUILD_CERTIFICATE_BASE64        .p12 证书的 base64
#    P12_PASSWORD                    .p12 的导出密码
#    BUILD_PROVISION_PROFILE_BASE64  .mobileprovision 的 base64
#    KEYCHAIN_PASSWORD               临时钥匙串密码（随便设）
#    EXPORT_METHOD                   可选：auto / development / ad-hoc / app-store
#
#  设计原则：每一步都给出「人能看懂」的报错，并且把关键数据（体积/长度/身份）
#  打出来，方便一眼定位问题出在哪个 Secret 上。
# ─────────────────────────────────────────────────────────────

# 不用 set -u：脚本已通过 : "${VAR:?}" 显式校验必需输入，
# set -u 在 macOS runner 上对「延迟赋值」变量会误报 unbound variable，反而挡住正常流程。
set -o pipefail

step() { printf '\n──── %s ────\n' "$1"; }
ok()   { printf '[OK] %s\n' "$1"; }
warn() { printf '[警告] %s\n' "$1"; }
die()  { printf '\n[失败] %s\n' "$1" >&2; exit 1; }

REPO_DIR="$PWD"
TMP="${RUNNER_TEMP:-/tmp}"
BUILD_DIR="$REPO_DIR/build"
mkdir -p "$BUILD_DIR/export"

CERT_PATH="$TMP/build_certificate.p12"
PP_PATH="$TMP/build_pp.mobileprovision"
PP_PLIST="$TMP/pp.plist"
KEYCHAIN_PATH="$TMP/app-signing.keychain-db"
XCODE_ARCHIVE="$TMP/SketchPad.xcarchive"

PROJECT_BUNDLE_ID="com.sketchpad.ink"
BUNDLE_ID=""          # 第 4 步根据描述文件再确定；先初始化避免任何未绑定引用
SCHEME="SketchPad"

# ══════════════════════════════════════════════════════════════
# 0. 环境
# ══════════════════════════════════════════════════════════════
step "0/8 选择 Xcode"

# glob 不匹配时返回空字符串而非报错，避免 runner 上目录名有差异时脚本直接挂掉
shopt -s nullglob

# 目标：优先选可用的最高版本 Xcode（需要 ≥26 才能编译液态玻璃 API）。
#   - xcode-27 镜像里是 /Applications/Xcode_27_beta_3.app（带 beta），所以不能一味排除 beta
#   - macos-26 镜像里是 /Applications/Xcode_26.5.app
# 策略：先挑「正式版」里版本最高的；若一个正式版都没有，才放宽允许 beta/RC。
pick_xcode() {
  local stable=() any=()
  for app in /Applications/Xcode_2[6-9]*.app /Applications/Xcode_2[6-9].app; do
    [ -d "$app" ] || continue
    any+=("$app")
    case "$(basename "$app")" in
      *beta*|*Beta*|*RC*|*rc*) ;;          # 测试版：只进 any
      *) stable+=("$app") ;;               # 正式版：优先
    esac
  done
  if [ ${#stable[@]} -gt 0 ]; then
    printf '%s\n' "${stable[@]}" | sort -rV | head -1
  elif [ ${#any[@]} -gt 0 ]; then
    printf '%s\n' "${any[@]}" | sort -rV | head -1
  fi
}

XCODE_APP="$(pick_xcode)"
if [ -z "$XCODE_APP" ] || [ ! -d "$XCODE_APP" ]; then
  warn "没找到 Xcode 26+，回退到 /Applications/Xcode.app"
  XCODE_APP="/Applications/Xcode.app"
fi
echo "  选中 Xcode：$XCODE_APP"
sudo xcode-select -s "$XCODE_APP/Contents/Developer" || die "xcode-select 到 $XCODE_APP 失败（路径不存在或权限不足）"
xcodebuild -version || die "找不到 xcodebuild"

# 硬性门槛：SDK 必须 ≥26，否则液态玻璃代码编不过
SDK_VER=$(xcodebuild -version -sdk iphoneos ProductVersion 2>/dev/null | head -1 || true)
echo "  iPhoneOS SDK 版本：${SDK_VER:-未知}"
case "$SDK_VER" in
  2[6-9].*|3[0-9].*) ok "SDK 满足 iOS 26+ 编译要求" ;;
  "")                warn "读不到 SDK 版本，继续尝试" ;;
  *)                 die "当前 Xcode 的 iPhoneOS SDK 是 $SDK_VER（<26），无法编译液态玻璃 API。请把 workflow 的 runs-on 改为 macos-26 或 xcode-27" ;;
esac

# ══════════════════════════════════════════════════════════════
# 1. 解码 Secrets
# ══════════════════════════════════════════════════════════════
step "1/8 解码证书与描述文件"

: "${BUILD_CERTIFICATE_BASE64:?Secret BUILD_CERTIFICATE_BASE64 没有配置或在 Actions 里取不到}"
: "${P12_PASSWORD:?Secret P12_PASSWORD 没有配置}"
: "${BUILD_PROVISION_PROFILE_BASE64:?Secret BUILD_PROVISION_PROFILE_BASE64 没有配置}"
: "${KEYCHAIN_PASSWORD:?Secret KEYCHAIN_PASSWORD 没有配置}"

# 关键：先删掉所有空白字符（换行 / 空格 / Tab）再解码。
# iPhone 复制粘贴、Mac 的 base64 换行输出，都会被这一步统一处理掉。
decode_b64() {
  printf '%s' "$1" | tr -d '[:space:]' | base64 --decode > "$2" 2>"$TMP/decode.err"
}

decode_b64 "$BUILD_CERTIFICATE_BASE64" "$CERT_PATH" \
  || { cat "$TMP/decode.err"; die "证书 base64 解码失败，Secret BUILD_CERTIFICATE_BASE64 内容不是合法的 base64"; }

decode_b64 "$BUILD_PROVISION_PROFILE_BASE64" "$PP_PATH" \
  || { cat "$TMP/decode.err"; die "描述文件 base64 解码失败，Secret BUILD_PROVISION_PROFILE_BASE64 内容不是合法的 base64"; }

CERT_SIZE=$(wc -c < "$CERT_PATH" | tr -d ' ')
PP_SIZE=$(wc -c < "$PP_PATH" | tr -d ' ')

echo "  BUILD_CERTIFICATE_BASE64       字符数 : ${#BUILD_CERTIFICATE_BASE64}"
echo "  BUILD_PROVISION_PROFILE_BASE64 字符数 : ${#BUILD_PROVISION_PROFILE_BASE64}"
echo "  P12_PASSWORD                   字符数 : ${#P12_PASSWORD}"
echo "  KEYCHAIN_PASSWORD              字符数 : ${#KEYCHAIN_PASSWORD}"
echo "  → 解码后  .p12            体积 : ${CERT_SIZE} 字节"
echo "  → 解码后  .mobileprovision 体积 : ${PP_SIZE} 字节"

[ "$CERT_SIZE" -gt 500 ] \
  || die "证书解码后只有 ${CERT_SIZE} 字节，明显不对。请重新生成 .p12 的 base64 并覆盖 Secret BUILD_CERTIFICATE_BASE64"
[ "$PP_SIZE" -gt 500 ] \
  || die "描述文件解码后只有 ${PP_SIZE} 字节，明显不对。请重新生成 .mobileprovision 的 base64 并覆盖 Secret BUILD_PROVISION_PROFILE_BASE64"

# ══════════════════════════════════════════════════════════════
# 2. 导入证书
# ══════════════════════════════════════════════════════════════
step "2/8 把证书导入临时钥匙串"

security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" \
  || die "无法创建临时钥匙串"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" \
  || die "无法解锁临时钥匙串，请检查 Secret KEYCHAIN_PASSWORD"

if ! security import "$CERT_PATH" -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"; then
  die "证书导入失败。最常见原因：Secret P12_PASSWORD 填错了（它必须是你导出 .p12 时设置的密码）"
fi

if ! security set-key-partition-list -S apple-tool:,apple:,codesign: \
       -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" > /dev/null; then
  warn "set-key-partition-list 返回非零，继续尝试"
fi
security list-keychain -d user -s "$KEYCHAIN_PATH" > /dev/null

echo "--- 钥匙串中的签名身份 ---"
security find-identity -v -p codesigning "$KEYCHAIN_PATH" || true

IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
  | sed -n 's/.*"\(.*\)".*/\1/p' | head -1)

[ -n "$IDENTITY" ] || die "钥匙串里没有任何可用签名身份：这个 .p12 里只有证书、没有配套私钥。请重新导出（导出时必须包含私钥）"
ok "签名身份：$IDENTITY"

# xcodebuild 用「证书类型名」最稳妥
case "$IDENTITY" in
  *"Apple Development"*)        SIGN_IDENTITY="Apple Development" ;;
  *"Apple Distribution"*)       SIGN_IDENTITY="Apple Distribution" ;;
  *"iPhone Distribution"*)      SIGN_IDENTITY="iPhone Distribution" ;;
  *"iPhone Developer"*)         SIGN_IDENTITY="iPhone Developer" ;;
  *"Developer ID Application"*) SIGN_IDENTITY="Developer ID Application" ;;
  *)                            SIGN_IDENTITY="$IDENTITY" ;;
esac
echo "  → 编译时使用 CODE_SIGN_IDENTITY = $SIGN_IDENTITY"

# ══════════════════════════════════════════════════════════════
# 3. 安装并解析描述文件
# ══════════════════════════════════════════════════════════════
step "3/8 安装描述文件"

if ! security cms -D -i "$PP_PATH" > "$PP_PLIST" 2>"$TMP/cms.err"; then
  echo "--- security cms 的报错 ---"
  cat "$TMP/cms.err" 2>/dev/null || true
  echo "--- 文件开头 64 字节（用来确认你到底编码了什么）---"
  head -c 64 "$PP_PATH" | od -c | head -4
  echo "--- 内容类型判断 ---"
  if openssl pkcs12 -info -in "$PP_PATH" -nokeys -passin pass:"$P12_PASSWORD" > /dev/null 2>&1 \
     || openssl pkcs12 -info -in "$PP_PATH" -nokeys -passin pass: > /dev/null 2>&1; then
    echo ">>> 这个文件其实是一个 .p12 证书！说明 BUILD_PROVISION_PROFILE_BASE64 里填成了证书。"
    echo ">>> 正确做法：这里要填 .mobileprovision（描述文件）的 base64。"
  elif head -c 300 "$PP_PATH" | tr -d '\0' | grep -qi 'html\|<!doctype\|http'; then
    echo ">>> 这个文件是网页/文本内容，不是描述文件。"
  else
    echo ">>> 无法识别的格式，请确认你编码的是从 Apple 后台 / 商家那里拿到的 .mobileprovision 文件本体。"
  fi
  die "描述文件无法解析：Secret BUILD_PROVISION_PROFILE_BASE64 里放的不是有效的 .mobileprovision 文件内容"
fi

PP_UUID=$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$PP_PLIST" 2>/dev/null || echo "")
PP_NAME=$(/usr/libexec/PlistBuddy -c 'Print :Name' "$PP_PLIST" 2>/dev/null || echo "")
TEAM_ID=$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$PP_PLIST" 2>/dev/null || echo "")
APP_ID=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$PP_PLIST" 2>/dev/null || echo "")
EXPIRY=$(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "$PP_PLIST" 2>/dev/null || echo "")
GET_TASK_ALLOW=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' "$PP_PLIST" 2>/dev/null || echo "false")
ALL_DEVICES=$(/usr/libexec/PlistBuddy -c 'Print :ProvisionsAllDevices' "$PP_PLIST" 2>/dev/null || echo "false")
HAS_DEVICES=$(/usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$PP_PLIST" 2>/dev/null || echo "")

[ -n "$PP_UUID" ] || die "描述文件里读不到 UUID，文件可能损坏"
[ -n "$TEAM_ID" ] || die "描述文件里读不到 Team ID，文件可能损坏"

echo "  名称          : $PP_NAME"
echo "  UUID          : $PP_UUID"
echo "  Team ID       : $TEAM_ID"
echo "  App ID        : $APP_ID"
echo "  get-task-allow: $GET_TASK_ALLOW"
echo "  过期时间      : $EXPIRY"

# 过期检查（描述文件过期是最常见的「莫名其妙失败」原因）
EXP_S=$(date -j -f "%Y-%m-%d %H:%M:%S %z" "$EXPIRY" +%s 2>/dev/null || echo "")
NOW_S=$(date +%s)
if [ -n "$EXP_S" ] && [ "$EXP_S" -lt "$NOW_S" ]; then
  die "描述文件已于 $EXPIRY 过期，请在开发者后台重新签发后再上传"
fi

mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$PP_PATH" "$HOME/Library/MobileDevice/Provisioning Profiles/$PP_UUID.mobileprovision" \
  || die "无法把描述文件复制到系统目录"
ok "描述文件已安装到本机"

# ══════════════════════════════════════════════════════════════
# 4. 对齐 Bundle ID
# ══════════════════════════════════════════════════════════════
step "4/8 对齐 Bundle ID"

if printf '%s' "$APP_ID" | grep -q '\*'; then
  BUNDLE_ID="$PROJECT_BUNDLE_ID"
  warn "描述文件是通配符（$APP_ID），保留工程里的 Bundle ID：$BUNDLE_ID"
else
  BUNDLE_ID="${APP_ID#*.}"
  if [ -z "$BUNDLE_ID" ] || [ "$BUNDLE_ID" = "$APP_ID" ]; then
    BUNDLE_ID="$PROJECT_BUNDLE_ID"
  fi
  if [ "$BUNDLE_ID" != "$PROJECT_BUNDLE_ID" ]; then
    echo "  工程 Bundle ID：$PROJECT_BUNDLE_ID  →  $BUNDLE_ID（跟随描述文件）"
    sed -i '' "s/$PROJECT_BUNDLE_ID/$BUNDLE_ID/g" SketchPad.xcodeproj/project.pbxproj
  else
    echo "  Bundle ID 一致：$BUNDLE_ID"
  fi
fi
echo "  → 最终使用 Bundle ID：$BUNDLE_ID"

# ══════════════════════════════════════════════════════════════
# ══════════════════════════════════════════════════════════════
# 5. 处理 entitlements（与描述文件严格一致，避免签名不匹配）
# ══════════════════════════════════════════════════════════════
step "5/8 处理 entitlements（从描述文件提取真实 iCloud 权限）"

# 关键修复：
# 1) 过去「猜」 iCloud 容器名 -> 与描述文件不匹配；现在改为从描述文件取真实值。
# 2) 证书商给的描述文件往往塞了一堆用不到的权限（ClassKit / Sign in with Apple /
#    各种 media 权限），其中有的取值类型还不对（如 ClassKit-environment 是数组
#    而非 NSString），直接整段拷进 app 的 entitlements 会让 xcodebuild 报
#    "Malformed value type"。
# 正确做法：app 只声明它真正用到的能力 —— 即 iCloud 家族
# （com.apple.developer.icloud-* / com.apple.developer.ubiquity-*），
# 其余权限由描述文件在签名阶段自动提供，无需也不能写进 app entitlements。
python3 - "$PP_PLIST" "SketchPad/SketchPad.entitlements" << 'PYEOF_PY'
import sys, plistlib

src, dst = sys.argv[1], sys.argv[2]

with open(src, 'rb') as f:
    pp = plistlib.load(f)
ent = pp.get('Entitlements', {}) or {}

# 只保留 iCloud 家族（app 实际用到的能力）
keep_prefixes = ('com.apple.developer.icloud', 'com.apple.developer.ubiquity')
kept = {k: v for k, v in ent.items() if k.startswith(keep_prefixes)}

if not kept:
    kept = {}

with open(dst, 'wb') as f:
    plistlib.dump(kept, f)

print("  描述文件全部能力键 :", sorted(ent.keys()) or "(无)")
print("  写入 app 的 iCloud 键 :", sorted(kept.keys()) or "(无 —— 将剥离 iCloud)")
PYEOF_PY

if [ $? -ne 0 ]; then
  warn "无法解析描述文件权限，退而求其次写空 entitlements"
  cat > SketchPad/SketchPad.entitlements << 'ENT_EMPTY'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
ENT_EMPTY
fi

cat SketchPad/SketchPad.entitlements

# ══════════════════════════════════════════════════════════════
# 6. 决定导出方式 + 生成 ExportOptions.plist
# ══════════════════════════════════════════════════════════════
step "6/8 生成 ExportOptions.plist"

EXPORT_METHOD="${EXPORT_METHOD:-auto}"
if [ "$EXPORT_METHOD" = "auto" ] || [ -z "$EXPORT_METHOD" ]; then
  if [ "$GET_TASK_ALLOW" = "true" ]; then
    EXPORT_METHOD="development"
  elif [ -n "$HAS_DEVICES" ]; then
    EXPORT_METHOD="ad-hoc"
  elif [ "$ALL_DEVICES" = "true" ]; then
    EXPORT_METHOD="enterprise"
  else
    EXPORT_METHOD="app-store"
  fi
  echo "  根据描述文件自动判断导出方式：$EXPORT_METHOD"
else
  echo "  使用手动指定的导出方式：$EXPORT_METHOD"
fi

cat > "$TMP/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>$EXPORT_METHOD</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>compileBitcode</key>
	<false/>
	<key>provisioningProfiles</key>
	<dict>
		<key>$BUNDLE_ID</key>
		<string>$PP_UUID</string>
	</dict>
</dict>
</plist>
EOF
cat "$TMP/ExportOptions.plist"

# ══════════════════════════════════════════════════════════════
# 7. 编译 Archive
# ══════════════════════════════════════════════════════════════
step "7/8 编译（xcodebuild archive）"

rm -rf "$XCODE_ARCHIVE"

xcodebuild archive \
  -project SketchPad.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$XCODE_ARCHIVE" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  PROVISIONING_PROFILE_SPECIFIER="$PP_UUID" \
  OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH" \
  > "$TMP/archive.log" 2>&1
ARCHIVE_EXIT=$?

if [ "$ARCHIVE_EXIT" -ne 0 ]; then
  echo "--- 编译失败，日志最后 60 行 ---"
  tail -60 "$TMP/archive.log"
  echo "--- 日志结束 ---"
  die "Archive 编译失败（完整日志见 build-logs 产物）"
fi
ok "Archive 成功"

# ══════════════════════════════════════════════════════════════
# 8. 导出 IPA
# ══════════════════════════════════════════════════════════════
step "8/8 导出 IPA"

rm -rf "$BUILD_DIR/export"
mkdir -p "$BUILD_DIR/export"

xcodebuild -exportArchive \
  -archivePath "$XCODE_ARCHIVE" \
  -exportOptionsPlist "$TMP/ExportOptions.plist" \
  -exportPath "$BUILD_DIR/export" \
  -allowProvisioningUpdates \
  > "$TMP/export.log" 2>&1
EXPORT_EXIT=$?

if [ "$EXPORT_EXIT" -ne 0 ]; then
  echo "--- 导出失败，日志最后 60 行 ---"
  tail -60 "$TMP/export.log"
  echo "--- 日志结束 ---"
  die "导出 IPA 失败（完整日志见 build-logs 产物）"
fi

IPA=$(find "$BUILD_DIR/export" -name '*.ipa' | head -1)
[ -n "$IPA" ] || die "导出命令成功，但没有找到 .ipa 文件"

ls -lh "$IPA"
ok "打包完成：$IPA"

# ══════════════════════════════════════════════════════════════
# 9. 发布到 GitHub Release（仅 v* 标签触发时执行）
#    需要 workflow 传入 GITHUB_TOKEN 并授予 contents: write
# ══════════════════════════════════════════════════════════════
if printf '%s' "${GITHUB_REF_NAME:-}" | grep -qE '^v[0-9]'; then
  TAG="$GITHUB_REF_NAME"
  step "9/9 发布到 Release $TAG"

  [ -n "${GITHUB_TOKEN:-}" ] || die "GITHUB_TOKEN 为空：请在 workflow 的 env 里加 GITHUB_TOKEN: \${{ secrets.GITHUB_TOKEN }}"

  REPO_API="https://api.github.com/repos/${GITHUB_REPOSITORY}"
  GH_AUTH="Authorization: Bearer ${GITHUB_TOKEN}"

  # Release 已存在则复用，否则创建
  RELEASE_ID=$(curl -s -H "$GH_AUTH" "$REPO_API/releases/tags/$TAG" | jq -r '.id // empty' 2>/dev/null || true)

  if [ -z "$RELEASE_ID" ]; then
    BODY=$(cat <<JSON
{"tag_name":"$TAG","name":"SketchPad $TAG","body":"## SketchPad $TAG\n\n- 液态玻璃界面（iOS 26+ 呈现原生 Liquid Glass，iOS 16~25 自动回退毛玻璃）\n- 最低支持 **iOS 16.0**\n- 画布 · 画廊 · iCloud 同步\n\n### 安装\n从下方 Assets 下载 \`SketchPad.ipa\`，安装方式见仓库《IPA安装指南》。","draft":false,"prerelease":false}
JSON
)
    RELEASE_JSON=$(curl -s -X POST -H "$GH_AUTH" -H "Content-Type: application/json" -d "$BODY" "$REPO_API/releases")
    RELEASE_ID=$(printf '%s' "$RELEASE_JSON" | jq -r '.id // empty' 2>/dev/null || true)
    [ -n "$RELEASE_ID" ] || { printf '%s\n' "$RELEASE_JSON"; die "创建 Release 失败"; }
    ok "Release 已创建（id=$RELEASE_ID）"
  else
    ok "Release 已存在（id=$RELEASE_ID），直接更新资产"
  fi

  # 同名资产已存在则先删除（重复发布时替换）
  ASSET_NAME=$(basename "$IPA")
  ASSET_ID=$(curl -s -H "$GH_AUTH" "$REPO_API/releases/$RELEASE_ID/assets?per_page=100" \
    | jq -r --arg n "$ASSET_NAME" '.[] | select(.name == $n) | .id' 2>/dev/null || true)
  if [ -n "$ASSET_ID" ]; then
    curl -s -X DELETE -H "$GH_AUTH" "$REPO_API/releases/assets/$ASSET_ID" >/dev/null
    ok "已删除旧资产 $ASSET_NAME"
  fi

  # 上传 IPA
  UPLOAD_JSON=$(curl -s -X POST -H "$GH_AUTH" -H "Content-Type: application/octet-stream" \
    --data-binary @"$IPA" \
    "https://uploads.github.com/repos/${GITHUB_REPOSITORY}/releases/$RELEASE_ID/assets?name=$ASSET_NAME")
  ASSET_URL=$(printf '%s' "$UPLOAD_JSON" | jq -r '.browser_download_url // empty' 2>/dev/null || true)
  [ -n "$ASSET_URL" ] || { printf '%s\n' "$UPLOAD_JSON"; die "上传 IPA 到 Release 失败"; }

  ok "IPA 已发布：$ASSET_URL"
else
  echo "非 v* 标签触发，跳过 Release 发布"
fi

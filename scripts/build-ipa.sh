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

set -uo pipefail

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
SCHEME="SketchPad"

# ══════════════════════════════════════════════════════════════
# 0. 环境
# ══════════════════════════════════════════════════════════════
step "0/8 选择 Xcode"
sudo xcode-select -s /Applications/Xcode_15.4.app/Contents/Developer 2>/dev/null \
  || sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version || die "找不到 xcodebuild"

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
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

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
cp "$PP_PATH" "$HOME/Library/MobileDevice/Provisioning Profiles/$PP_UUID.mobileprovision"
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
# 5. 处理 entitlements（iCloud 权限）
# ══════════════════════════════════════════════════════════════
step "5/8 处理 entitlements"

PROFILE_HAS_ICLOUD=0
if /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.icloud-container-identifiers' \
     "$PP_PLIST" > /dev/null 2>&1; then
  PROFILE_HAS_ICLOUD=1
fi

if [ "$PROFILE_HAS_ICLOUD" = "1" ]; then
  ok "描述文件支持 iCloud，保留 iCloud 权限"
  cat > SketchPad/SketchPad.entitlements << ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>iCloud.${BUNDLE_ID}</string>
	</array>
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudDocuments</string>
	</array>
	<key>com.apple.developer.ubiquity-container-identifiers</key>
	<array>
		<string>iCloud.${BUNDLE_ID}</string>
	</array>
	<key>com.apple.developer.ubiquity-kvstore-identifier</key>
	<string>\$(TeamIdentifierPrefix)\$(CFBundleIdentifier)</string>
</dict>
</plist>
ENT
else
  warn "描述文件不含 iCloud 权限（个人证书通常如此），本次打包将剥离 iCloud 能力"
  cat > SketchPad/SketchPad.entitlements << 'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
ENT
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

# CNKH POS Mobile — iOS self-sign (你自签 IPA)

Linux 无法生成真机可用的 IPA。请用 **Mac + Xcode** 打开附带的 iOS 工程自行签名。

## 最快路径（推荐）

1. 解压 `CNKH_POS_Mobile_iOS_project.zip` 到 Mac（或直接 clone 含 `mobile/` 的仓库）。
2. 安装 Flutter（stable），在解压后的 `mobile/` 目录：
   ```bash
   flutter pub get
   cd ios && pod install && cd ..
   open ios/Runner.xcworkspace
   ```
3. 在 Xcode：
   - **Signing & Capabilities** → 勾选 *Automatically manage signing*
   - Team：选择你的 Apple ID / Developer Team
   - Bundle ID：可改为你自己的（如 `com.yourname.cnkhposmobile`）若默认被占用
4. 菜单 **Product → Archive**
5. Organizer → **Distribute App** → **Development** 或 **Ad Hoc**（真机）→ Export
6. 得到 `.ipa`，用 Finder / Apple Configurator / `ideviceinstaller` 装到手机

## 命令行（有证书时）

```bash
cd mobile
flutter build ipa --release
# 输出通常在: build/ios/ipa/*.ipa
```

仅编译检查（无签名）：

```bash
flutter build ios --release --no-codesign
```

## 说明

- 未签名的 IPA **不能** 直接装到 iPhone。
- 个人免费 Apple ID：可 Development 装自己的设备（有时效限制）。
- 企业/Ad Hoc 需对应证书与设备 UDID。
- GitHub Actions 草图：`mobile/.github/workflows/mobile-ios.yml`

## 本包内容

完整 Flutter `mobile/` 源码（含 `ios/` Xcode 工程），在 Mac 上按上面步骤即可出 IPA。

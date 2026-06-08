## FxAbsKit

### 提交的文件记录
```text
url: "https://statics.fxbusiness.cn/client/ios/abs.xcframework_v1.0.0.zip"
checksum: "173d3c9737a2266bfa3584ffa20147b01e8d0cf83a0c35f5ebecfb45668cdf86"
```
```text
url: "https://github.com/MannixGu/FxAbsKit/releases/download/1.0.0/abs.xcframework_1.0.0.zip",
checksum: "173d3c9737a2266bfa3584ffa20147b01e8d0cf83a0c35f5ebecfb45668cdf86"
```

### 如何构建SPM依赖

#### 首次创建 Swift Package 项目
```shell
mkdir MyXCFrameworkPackage
cd MyXCFrameworkPackage
swift package init --type library
```

这会生成标准 SPM 目录结构：

```text
MyXCFrameworkPackage/
├── Sources/
├── Tests/
├── Package.swift
└── README.md
```

因为我们要用 .xcframework，不需要源码。

```bash
rm -rf Sources/*
```


#### 构建xcframework
```shell
xcodebuild -create-xcframework \
  -framework MyFramework-iOS.framework \
  -framework MyFramework-macOS.framework \
  -output MyFramework.xcframework
```

#### 创建 GitHub Release 并上传 ZIP
+ 压缩 xcframework
```shell
zip -r MyFramework.zip MyFramework.xcframework
```

+ 计算校验sum

```shell
swift package compute-checksum MyFramework.zip
```

+ 创建release
+ 
1. 在 GitHub 仓库页面点击 Releases → Draft a new release
2. 填写信息:
> Tag version: 1.0.0（必须是语义化版本，如 v1.0.0 或 1.0.0）

> Release title: MyFramework 1.0.0

> Description: 可选说明
3. 上传 ZIP 文件：

4. 点击 Publish release

发布后，ZIP 的下载 URL 会是：

https://github.com/yourname/MyFrameworkSPM/releases/download/1.0.0/MyFramework.zip

#### 根据需要编辑Package.swift
```swift
.binaryTarget(
    name: "MyLibrary",
    url: "https://github.com/yourname/MyXCFrameworkPackage/releases/download/1.0.0/MyLibrary.zip",
    checksum: "..." // 用 `swift package compute-checksum MyLibrary.zip` 生成
)
```

#### 创建版本
+ 更新提交后，提交tag
```shell
git tag 1.0.0
git push origin 1.0.0
```

### 一键发布脚本

上面的步骤已经封装成 `scripts/release.sh`，传入打包好的 zip 与版本号即可完成 计算 checksum → 改 Package.swift → commit → 打 tag → push → 创建 GitHub Release（并上传 zip） 全流程。

依赖：`gh`（`brew install gh` 并 `gh auth login`）、`swift`、`python3`。

```shell
# 干跑（不会改任何 git 状态，验证 checksum 与 Package.swift 替换效果）
scripts/release.sh ~/Downloads/abs.xcframework.zip 1.0.1 --dry-run

# 正式发布（自动用 main 分支 commit 并打 tag）
scripts/release.sh ~/Downloads/abs.xcframework.zip 1.0.1

# 自定义 release notes（默认使用 gh --generate-notes）
scripts/release.sh ~/Downloads/abs.xcframework.zip 1.0.1 --notes "修复 xxx"
```

脚本会：
- 从 `git remote get-url origin` 推导 owner/repo，无需手填
- 将 zip 重命名为 `abs.xcframework_<version>.zip` 后上传
- 拒绝重复版本（本地 tag、远端 tag、远端 release 任一存在都会中止）
- 失败或取消时自动回滚 Package.swift 的本地修改
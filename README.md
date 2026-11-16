# dxc-autobuild

DXC 自动构建与发布（GitHub Actions）。

## Workflows

- Windows x64: `.github/workflows/build_win_x64.yaml`
- macOS arm64: `.github/workflows/build_macos_arm64.yaml`

## 使用方式（手动触发）

在 GitHub 仓库页面进入 **Actions**，选择对应 workflow，点击 **Run workflow**，填写：

- `dxc_ref`：`ksgfk/DirectXShaderCompiler` fork 的提交、分支或 tag（默认 `5f3d596c12efb750e9c73341f1125b4cd8a5fbaf`）
- `package_version`：写入包文件名的版本号（默认 `1.9.2609.radray.3`）。只允许字母、数字、`.`、`_`、`+` 和 `-`。

## 产物与发布行为

- 构建脚本会生成带版本的平台 zip 包，例如 `dxc-windows-x64-1.9.2609.radray.3.zip` 和 `dxc-macos-arm64-1.9.2609.radray.3.zip`。
- 两个 workflow 都将资产上传到唯一的滚动 Release：`latest`（标题为 `DXC Autobuild (Latest)`）。发布前该 Release 必须存在；工作流不修改源码提交。
- 同一版本、同一平台的 zip 和 manifest 不允许覆盖；构建前检查已有资产及源码版本，版本必须与 SDK 内部版本一致。不同版本保留在同一 Release 中。每个 zip 旁还会有同版本 manifest，记录版本、输入 ref、实际解析到的 DXC commit、构建时间与 SHA256。
- 失败时会额外上传 Actions artifact 作为一天期的排障备份。

## 本地 Windows 构建

使用 Visual Studio 的 ClangCL toolset 构建：

```powershell
pwsh -File .\build_win_x64.ps1 -ProjectDir F:\path\to\DirectXShaderCompiler -UseClangCl
```

RadRay SDK 包由 fork 自带的 `utils/package_radray_sdk.py` 生成。两个包装脚本只构建 dxcompiler/dxc/dxildll，并调用统一打包器；
从源码读取版本，拒绝错误文件名和覆盖已有包，不清空产物目录。Windows 的 `-ExistingBuild`、macOS 的
`--existing-build` 可复用已配置目录；仍执行增量构建。并行度默认 4，可用 `-Parallel` / `--parallel` 调整。
生成包不代表平台验收已执行，manifest 应只记录实际执行的验证。

## 下载

- 对外分发请从 GitHub **Releases** 页面下载 `latest` 中所需版本的资产；文件名中包含版本，因此可直接作为稳定下载路径的一部分，例如：
  - `https://github.com/ksgfk/dxc-autobuild/releases/download/latest/dxc-windows-x64-1.9.2609.radray.3.zip`
  - `https://github.com/ksgfk/dxc-autobuild/releases/download/latest/dxc-macos-arm64-1.9.2609.radray.3.zip`
- Actions 中的 artifact 主要用于失败排障备份。

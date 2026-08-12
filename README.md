# dxc-autobuild

DXC 自动构建与发布（GitHub Actions）。

## Workflows

- Windows x64: `.github/workflows/build_win_x64.yaml`
- macOS arm64: `.github/workflows/build_macos_arm64.yaml`

## 使用方式（手动触发）

在 GitHub 仓库页面进入 **Actions**，选择对应 workflow，点击 **Run workflow**，填写：

- `dxc_ref`：`ksgfk/DirectXShaderCompiler` fork 的分支或 tag（默认 `codex/radray-dxc-1.9.2607`）
- `package_version`：写入包文件名的版本号（默认 `1.9.2607.radray.1`）。只允许字母、数字、`.`、`_`、`+` 和 `-`。

## 产物与发布行为

- 构建脚本会生成带版本的平台 zip 包，例如 `dxc-windows-x64-1.9.2607.radray.1.zip` 和 `dxc-macos-arm64-1.9.2607.radray.1.zip`。
- 两个 workflow 都将资产上传到唯一的滚动 Release：`latest`（标题为 `DXC Autobuild (Latest)`）。首次成功构建会自动创建该 Release；之后不再创建 tag 或 commit。
- 同一版本、同一平台的 zip 会按同名覆盖更新；不同版本会保留在同一 Release 中。每个 zip 旁还会有同版本 manifest，记录版本、输入 ref、实际解析到的 DXC commit 与构建时间。
- 失败时会额外上传 Actions artifact 作为一天期的排障备份。

## 本地 Windows 构建

使用 Visual Studio 的 ClangCL toolset 构建：

```powershell
pwsh -File .\build_win_x64.ps1 -ProjectDir F:\path\to\DirectXShaderCompiler -UseClangCl
```

RadRay SDK 包由 fork 自带的 `utils/package_radray_sdk.py` 生成，使用构建目录执行 `--no-build` 可复用已完成的构建。

## 下载

- 对外分发请从 GitHub **Releases** 页面下载 `latest` 中所需版本的资产；文件名中包含版本，因此可直接作为稳定下载路径的一部分，例如：
  - `https://github.com/ksgfk/dxc-autobuild/releases/download/latest/dxc-windows-x64-1.9.2607.radray.1.zip`
  - `https://github.com/ksgfk/dxc-autobuild/releases/download/latest/dxc-macos-arm64-1.9.2607.radray.1.zip`
- Actions 中的 artifact 主要用于失败排障备份。

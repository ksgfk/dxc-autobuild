# dxc-autobuild

DXC 自动构建与发布（GitHub Actions）。

## Workflows

- Windows x64: `.github/workflows/build_win_x64.yaml`
- macOS arm64: `.github/workflows/build_macos_arm64.yaml`

## 使用方式（手动触发）

在 GitHub 仓库页面进入 **Actions**，选择对应 workflow，点击 **Run workflow**，填写：

- `dxc_ref`：`ksgfk/DirectXShaderCompiler` fork 的分支或 tag（默认 `codex/radray-dxc-1.9.2607`）

## 产物与发布行为

- 构建脚本会生成平台 zip 包（例如 `dxc-windows-x64.zip` / `dxc-macos-arm64.zip`）。
- 两个 workflow 都将资产上传到唯一的滚动 Release：`latest`（标题为 `DXC Autobuild (Latest)`）。首次成功构建会自动创建该 Release；之后不再创建 tag 或 commit。
- 同一平台的 zip 会按同名覆盖更新；各平台可独立更新。每个 zip 旁还会有对应的 manifest（`dxc-windows-x64.manifest.json` / `dxc-macos-arm64.manifest.json`），记录输入 ref、实际解析到的 DXC commit 与构建时间。
- 失败时会额外上传 Actions artifact 作为一天期的排障备份。

## 本地 Windows 构建

使用 Visual Studio 的 ClangCL toolset 构建：

```powershell
pwsh -File .\build_win_x64.ps1 -ProjectDir F:\path\to\DirectXShaderCompiler -UseClangCl
```

RadRay SDK 包由 fork 自带的 `utils/package_radray_sdk.py` 生成，使用构建目录执行 `--no-build` 可复用已完成的构建。

## 下载

- 对外分发请从 GitHub **Releases** 页面下载 `latest` 中的资产。固定下载地址为：
  - `https://github.com/ksgfk/dxc-autobuild/releases/download/latest/dxc-windows-x64.zip`
  - `https://github.com/ksgfk/dxc-autobuild/releases/download/latest/dxc-macos-arm64.zip`
- Actions 中的 artifact 主要用于失败排障备份。

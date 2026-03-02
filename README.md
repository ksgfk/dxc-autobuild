# dxc-autobuild

DXC 自动构建与发布（GitHub Actions）。

## Workflows

- Windows x64: `.github/workflows/build_win_x64.yaml`
- macOS arm64: `.github/workflows/build_macos_arm64.yaml`

## 使用方式（手动触发）

在 GitHub 仓库页面进入 **Actions**，选择对应 workflow，点击 **Run workflow**，填写：

- `dxc_ref`：上游 DXC 的分支或 tag（默认 `main`）
- `release_tag`：要发布到 GitHub Release 的 tag（例如 `v1.0.0`）

## 产物与发布行为

- 构建脚本会生成平台 zip 包（例如 `dxc-windows-x64.zip` / `dxc-macos-arm64.zip`）。
- workflow 会将该 zip 直接上传到对应 `release_tag` 的 GitHub Release Asset。
- 如果同名 tag 已存在，资产会按同名覆盖更新（`overwrite_files: true`）。
- 失败时会额外上传 Actions artifact 作为备份（仅失败时上传）。

## 下载

- 对外分发请从 GitHub **Releases** 页面下载资产。
- Actions 中的 artifact 主要用于失败排障备份。

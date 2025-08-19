#Requires -Version 5.1
[CmdletBinding()]
param(
    # CMake 工程目录
    [string]$ProjectDir,

	# 构建目录（默认：GitHub Actions 临时目录或仓库下 build）
	[string]$BuildDir,

	# 构建配置（默认：Release）
	[ValidateSet('Debug','Release','RelWithDebInfo','MinSizeRel')]
	[string]$Config = 'Release',

	# 产物目录（默认：脚本目录下 artifacts）
	[string]$ArtifactsDir = (Join-Path $PSScriptRoot 'artifacts'),

	# 打包 tar.gz 文件名
	[string]$ArchiveName = 'dxc-linux-x64.tar.gz'
)

<#
用法示例（在仓库根目录执行）：
  pwsh -File ./build_linux_x64.ps1
或自定义参数：
  pwsh -File ./build_linux_x64.ps1 -Config Release -ArtifactsDir ./out -ArchiveName dxc.tar.gz

脚本步骤：
1) 使用 CMake 配置 Release for Linux x64：
   cmake . -B <临时构建目录> \
     -C cmake/caches/PredefinedParams.cmake \
     -DCMAKE_BUILD_TYPE=Release -DENABLE_SPIRV_CODEGEN=ON -DHLSL_INCLUDE_TESTS=OFF \
     -DSPIRV_BUILD_TESTS=OFF -DCLANG_BUILD_EXAMPLES=OFF
2) 构建： cmake --build <构建目录> --config Release --parallel <jobs>
3) 查找并打包：
	- lib: libdxcompiler.so、libdxil.so
	- include: 从 $ProjectDir/include/dxc/ 复制 dxcapi.h、dxcerrors.h、dxcisense.h、WinAdapter.h
	（不创建 bin 目录）
#>

$ErrorActionPreference = 'Stop'
$PSStyle.OutputRendering = 'PlainText'  # 减少日志转义在 Actions 输出中的干扰（PowerShell 7 可用）

function New-DirectoryIfNeeded([string]$Path) {
	if (![string]::IsNullOrWhiteSpace($Path)) {
		if (-not (Test-Path -LiteralPath $Path)) {
			New-Item -ItemType Directory -Path $Path | Out-Null
		}
	}
}

function Get-ProcessorCount {
	# 在 Linux 上获取 CPU 核心数
	try {
		$coreCount = & nproc --all 2>$null
		if ($coreCount -and $coreCount -match '^(\d+)$') {
			return [int]$coreCount
		}
	}
	catch { }
	try {
		$cnt = (Get-Content -LiteralPath '/proc/cpuinfo' -ErrorAction Stop | Select-String -Pattern '^processor\s*:' -AllMatches).Matches.Count
		if ($cnt -gt 0) { return [int]$cnt }
	}
	catch { }
	return 4  # 默认使用 4 个核心
}

try {
	# 1) 解析构建与产物目录
	if (-not $BuildDir -or [string]::IsNullOrWhiteSpace($BuildDir)) {
		if ($env:RUNNER_TEMP) {
			$timestamp = [DateTime]::UtcNow.ToString('yyyyMMddHHmmss')
			$BuildDir = Join-Path $env:RUNNER_TEMP "dxc-build-$timestamp"
		} else {
			$BuildDir = Join-Path $PSScriptRoot 'build'
		}
	}

	# 如果构建目录已存在，先清空
	if (Test-Path -LiteralPath $ArtifactsDir) {
		Write-Host "Clean existing artifacts directory: $ArtifactsDir"
		Remove-Item -LiteralPath $ArtifactsDir -Recurse -Force -ErrorAction SilentlyContinue
	}
	New-DirectoryIfNeeded -Path $BuildDir
	New-DirectoryIfNeeded -Path $ArtifactsDir

	Write-Host "Configure build directory: $BuildDir"
	Write-Host "Artifacts directory: $ArtifactsDir"

	# 2) CMake 配置（Linux x64 + Release + 题述参数）
	$cmakeArgs = @(
		$ProjectDir,
		'-B', $BuildDir,
		'-C', "$ProjectDir/cmake/caches/PredefinedParams.cmake",
		"-DCMAKE_BUILD_TYPE=$Config",
		'-DENABLE_SPIRV_CODEGEN=ON',
        '-DSPIRV_BUILD_TESTS=OFF',
        '-DHLSL_INCLUDE_TESTS=OFF',
        '-DCLANG_BUILD_EXAMPLES=OFF'
	)

	Write-Host '::group::CMake Configure'
	Write-Host ("cmake " + ($cmakeArgs -join ' '))
	& cmake @cmakeArgs
	if ($LASTEXITCODE -ne 0) {
		throw "CMake 配置失败，退出码: $LASTEXITCODE"
	}
	Write-Host '::endgroup::'

	# 3) 构建（并行编译）
	$jobCount = Get-ProcessorCount
	Write-Host '::group::CMake Build'
	& cmake --build $BuildDir --config $Config --parallel $jobCount
	if ($LASTEXITCODE -ne 0) {
		throw "CMake 构建失败，退出码: $LASTEXITCODE"
	}
	Write-Host '::endgroup::'

	# 4) 查找目标 so 并按手动 install 布局打包
	$soNames = @('libdxcompiler.so','libdxil.so')
	$found = @{}

	Write-Host '::group::Locate shared objects'
	foreach ($name in $soNames) {
		$candidates = Get-ChildItem -LiteralPath $BuildDir -Filter $name -File -Recurse -ErrorAction SilentlyContinue |
			Sort-Object -Property FullName

		if (-not $candidates -or $candidates.Count -eq 0) {
			throw "未找到 $name（在 $BuildDir 下）"
		}

		# 优先选择路径中包含配置名(如 Release)的候选；否则取最近写入的一个
		$preferred = $candidates | Where-Object { $_.FullName -match [Regex]::Escape($Config) } | Select-Object -First 1
		if (-not $preferred) {
			$preferred = $candidates | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
		}

		$found[$name] = $preferred.FullName
		Write-Host ("Found {0}: {1}" -f $name, $preferred.FullName)
	}
	Write-Host '::endgroup::'

	# 创建打包目录结构（无 bin，仅 lib 与 include）
	$packageDir = Join-Path $ArtifactsDir "dxc-$Config"
	$libDir = Join-Path $packageDir 'lib'
	$incDir = Join-Path $packageDir 'include'
	New-DirectoryIfNeeded -Path $packageDir
	New-DirectoryIfNeeded -Path $libDir
	New-DirectoryIfNeeded -Path $incDir

	# 复制 .so 到 lib
	foreach ($name in $soNames) {
		$src = $found[$name]
		if (-not $src) { throw "未定位到 $name" }
		Copy-Item -LiteralPath $src -Destination (Join-Path $libDir $name) -Force
	}

	# 复制头文件到 include
	$headerSrcDir = Join-Path $ProjectDir 'include/dxc'
	$headers = @('dxcapi.h','dxcerrors.h','dxcisense.h','WinAdapter.h')
	foreach ($h in $headers) {
		$hSrc = Join-Path $headerSrcDir $h
		if (-not (Test-Path -LiteralPath $hSrc)) {
			throw "未找到头文件: $hSrc"
		}
		Copy-Item -LiteralPath $hSrc -Destination (Join-Path $incDir $h) -Force
	}

	# 使用 tar 创建 .tar.gz 压缩包（Linux 原生格式）
	$archivePath = Join-Path $ArtifactsDir $ArchiveName
	if (Test-Path -LiteralPath $archivePath) { 
		Remove-Item -LiteralPath $archivePath -Force 
	}

	Push-Location $packageDir
	try {
		& tar -czf $archivePath *
		if ($LASTEXITCODE -ne 0) {
			throw "tar 打包失败，退出码: $LASTEXITCODE"
		}
	}
	finally {
		Pop-Location
	}

	Write-Host "打包完成: $archivePath"

	# 在 GitHub Actions 中输出 artifact 路径，便于后续 steps 上传
	if ($env:GITHUB_OUTPUT) {
		"artifact=$archivePath" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
	}
}
catch {
	Write-Error $_
	exit 1
}

#Requires -Version 5.1
[CmdletBinding()]
param(
    # CMake 工程目录
    [string]$ProjectDir,

	# 构建目录（默认：GitHub Actions 临时目录或仓库下 build）
	[string]$BuildDir = (Join-Path $PSScriptRoot 'build'),

	# 构建配置（默认：Release）
	[ValidateSet('Debug','Release','RelWithDebInfo','MinSizeRel')]
	[string]$Config = 'Release',

	# 产物目录（默认：脚本目录下 artifacts）
	[string]$ArtifactsDir = (Join-Path $PSScriptRoot 'artifacts'),

	# 打包 zip 文件名
	[string]$ZipName = 'dxc-windows-x64.zip'
)

<#
用法示例（在仓库根目录执行）：
  pwsh -File .\build_win_x64.ps1
或自定义参数：
  pwsh -File .\build_win_x64.ps1 -Config Release -ArtifactsDir .\out -ZipName dxc.zip

脚本步骤：
1) 使用 CMake 以 ClangCL 配置 Release：
   cmake . -B <临时构建目录> \
	 -C cmake\caches\PredefinedParams.cmake \
	 -DCMAKE_BUILD_TYPE=Release -DENABLE_SPIRV_CODEGEN=ON -DHLSL_INCLUDE_TESTS=OFF \
	 -DSPIRV_BUILD_TESTS=ON -DCLANG_CL=ON -DCLANG_BUILD_EXAMPLES=OFF -T ClangCL
2) 构建： cmake --build <构建目录> --config Release
3) 查找并打包：
	- bin: dxcompiler.dll、dxil.dll
	- lib: dxcompiler.lib、dxil.lib
	- include: 从 $ProjectDir/include/dxc/ 复制 dxcapi.h、dxcerrors.h、dxcisense.h
#>

$ErrorActionPreference = 'Stop'
$PSStyle.OutputRendering = 'PlainText'  # 减少日志转义在 Actions 输出中的干扰

function New-DirectoryIfNeeded([string]$Path) {
	if (![string]::IsNullOrWhiteSpace($Path)) {
		if (-not (Test-Path -LiteralPath $Path)) {
			New-Item -ItemType Directory -Path $Path | Out-Null
		}
	}
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

	New-DirectoryIfNeeded -Path $BuildDir
	New-DirectoryIfNeeded -Path $ArtifactsDir

	# 完全删除 artifacts 目录并重新创建
	Write-Host '::group::Reset artifacts directory'
	if (Test-Path -LiteralPath $ArtifactsDir) {
		Remove-Item -LiteralPath $ArtifactsDir -Recurse -Force -ErrorAction SilentlyContinue
	}
	New-DirectoryIfNeeded -Path $ArtifactsDir
	Write-Host "Artifacts reset: $ArtifactsDir"
	Write-Host '::endgroup::'

	Write-Host "Configure build directory: $BuildDir"
	Write-Host "Artifacts directory: $ArtifactsDir"

	# 2) CMake 配置（ClangCL, Release + 题述参数）
	$cmakeArgs = @(
		$ProjectDir,
		'-B', $BuildDir,
		'-C', "$ProjectDir\cmake\caches\PredefinedParams.cmake",
	    '-A', 'x64',
		"-DCMAKE_BUILD_TYPE=$Config",
		'-DENABLE_SPIRV_CODEGEN=ON',
		'-DHLSL_INCLUDE_TESTS=OFF',
		'-DSPIRV_BUILD_TESTS=OFF',
		'-DCLANG_CL=ON',
		'-DCLANG_BUILD_EXAMPLES=OFF',
		'-T', 'ClangCL'
	)

	Write-Host '::group::CMake Configure'
	Write-Host ("cmake " + ($cmakeArgs -join ' '))
	& cmake @cmakeArgs
	Write-Host '::endgroup::'

	# 3) 构建（使用 VS 生成器时并行开关为 /m）
	Write-Host '::group::CMake Build'
	& cmake --build $BuildDir --config $Config -- /m
	Write-Host '::endgroup::'

	# 4) 查找目标文件并打包
	$targets = @('dxcompiler.dll','dxil.dll','dxcompiler.lib','dxil.lib')
	$found = @{}

	Write-Host '::group::Locate build outputs'
	foreach ($name in $targets) {
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

	# 创建目标打包目录结构
	$packageDir = Join-Path $ArtifactsDir "dxc-$Config"
	$binDir = Join-Path $packageDir 'bin'
	$libDir = Join-Path $packageDir 'lib'
	$incDir = Join-Path $packageDir 'include'

	New-DirectoryIfNeeded -Path $packageDir
	New-DirectoryIfNeeded -Path $binDir
	New-DirectoryIfNeeded -Path $libDir
	New-DirectoryIfNeeded -Path $incDir

	# 复制 DLL 到 bin
	foreach ($dll in @('dxcompiler.dll','dxil.dll')) {
		$src = $found[$dll]
		if (-not $src) { throw "未定位到 $dll" }
		Copy-Item -LiteralPath $src -Destination (Join-Path $binDir $dll) -Force
	}

	# 复制 LIB 到 lib
	foreach ($lib in @('dxcompiler.lib','dxil.lib')) {
		$src = $found[$lib]
		if (-not $src) { throw "未定位到 $lib" }
		Copy-Item -LiteralPath $src -Destination (Join-Path $libDir $lib) -Force
	}

	# 复制头文件到 include
	$headerSrcDir = Join-Path $ProjectDir 'include\dxc'
	$headers = @('dxcapi.h','dxcerrors.h','dxcisense.h')
	foreach ($h in $headers) {
		$hSrc = Join-Path $headerSrcDir $h
		if (-not (Test-Path -LiteralPath $hSrc)) {
			throw "未找到头文件: $hSrc"
		}
		Copy-Item -LiteralPath $hSrc -Destination (Join-Path $incDir $h) -Force
	}

	# 压缩打包
	$zipPath = Join-Path $ArtifactsDir $ZipName
	if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
	Compress-Archive -Path (Join-Path $packageDir '*') -DestinationPath $zipPath -Force

	Write-Host "打包完成: $zipPath"

	# 在 GitHub Actions 中输出 artifact 路径，便于后续 steps 上传
	if ($env:GITHUB_OUTPUT) {
		"artifact=$zipPath" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
	}
}
catch {
	Write-Error $_
	exit 1
}

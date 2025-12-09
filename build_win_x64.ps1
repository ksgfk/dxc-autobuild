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
1) CMake 配置：
   cmake . -B <BuildDir> -C ... -DCMAKE_INSTALL_PREFIX=<InstallDir> ...
2) 构建：
   cmake --build <BuildDir> --config Release
3) 安装：
   cmake --build <BuildDir> --config Release --target install-distribution
4) 手动复制补充文件：
   - dxil.dll -> bin
   - dxcompiler.lib, dxil.lib -> lib
5) 打包
#>

$ErrorActionPreference = 'Stop'
$PSStyle.OutputRendering = 'PlainText'

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

	# 重置 artifacts 目录
	Write-Host '::group::Reset artifacts directory'
	if (Test-Path -LiteralPath $ArtifactsDir) {
		Remove-Item -LiteralPath $ArtifactsDir -Recurse -Force -ErrorAction SilentlyContinue
	}
	New-DirectoryIfNeeded -Path $ArtifactsDir
	Write-Host "Artifacts reset: $ArtifactsDir"
	Write-Host '::endgroup::'

    # 定义安装目录 (作为 CMAKE_INSTALL_PREFIX)
    $InstallDir = Join-Path $ArtifactsDir "dxc-$Config"
    New-DirectoryIfNeeded -Path $InstallDir

	Write-Host "Configure build directory: $BuildDir"
	Write-Host "Install directory: $InstallDir"

	# 2) CMake 配置
    # 用户提供的样例：
    # cmake . -B "..." -C cmake\caches\PredefinedParams.cmake 
    # -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="..." 
    # -DENABLE_SPIRV_CODEGEN=ON -DLIBCLANG_BUILD_STATIC=OFF 
    # -DHLSL_INCLUDE_TESTS=OFF -DSPIRV_BUILD_TESTS=OFF -DLLVM_INCLUDE_TESTS=OFF 
    # -DCLANG_CL=ON -T ClangCL

	$cmakeArgs = @(
		$ProjectDir,
		'-B', $BuildDir,
		'-C', "$ProjectDir\cmake\caches\PredefinedParams.cmake",
	    '-A', 'x64', # 保持 x64 架构指定
		"-DCMAKE_BUILD_TYPE=$Config",
        "-DCMAKE_INSTALL_PREFIX=$InstallDir",
		'-DENABLE_SPIRV_CODEGEN=ON',
        '-DLIBCLANG_BUILD_STATIC=OFF',
		'-DHLSL_INCLUDE_TESTS=OFF',
		'-DSPIRV_BUILD_TESTS=OFF',
        '-DLLVM_INCLUDE_TESTS=OFF',
		'-DCLANG_CL=ON',
		'-T', 'ClangCL'
	)

	Write-Host '::group::CMake Configure'
	Write-Host ("cmake " + ($cmakeArgs -join ' '))
	& cmake @cmakeArgs
	Write-Host '::endgroup::'

	# 3) 构建
	Write-Host '::group::CMake Build'
    # cmake --build "..." --config Release
    $buildArgs = @(
        '--build', $BuildDir,
        '--config', $Config,
        '--', '/m'
    )
    Write-Host ("cmake " + ($buildArgs -join ' '))
	& cmake @buildArgs
	Write-Host '::endgroup::'

    # 4) 安装 (install-distribution)
    Write-Host '::group::CMake Install'
    # cmake --build "..." --config Release --target install-distribution
    $installArgs = @(
        '--build', $BuildDir,
        '--config', $Config,
        '--target', 'install-distribution'
    )
    Write-Host ("cmake " + ($installArgs -join ' '))
    & cmake @installArgs
    Write-Host '::endgroup::'

	# 5) 手动复制补充文件
    # 需求：
    # 复制 dxil.dll 到 bin 文件夹
    # 复制 dxcompiler.lib、dxil.lib 到 lib 文件夹
    
	Write-Host '::group::Post-Install Copy'
    
    # 辅助函数：在 BuildDir 中查找文件
    function Find-BuildArtifact([string]$Name) {
        $candidates = Get-ChildItem -LiteralPath $BuildDir -Filter $Name -File -Recurse -ErrorAction SilentlyContinue |
			Sort-Object -Property FullName
        
        if (-not $candidates -or $candidates.Count -eq 0) {
			throw "未找到 $Name（在 $BuildDir 下）"
		}

        # 优先选择路径中包含配置名(如 Release)的候选；否则取最近写入的一个
		$preferred = $candidates | Where-Object { $_.FullName -match [Regex]::Escape($Config) } | Select-Object -First 1
		if (-not $preferred) {
			$preferred = $candidates | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
		}
        return $preferred.FullName
    }

    $binDir = Join-Path $InstallDir 'bin'
    $libDir = Join-Path $InstallDir 'lib'
    New-DirectoryIfNeeded -Path $binDir
    New-DirectoryIfNeeded -Path $libDir

    # 复制 dxil.dll -> bin
    $dxilDll = Find-BuildArtifact 'dxil.dll'
    Write-Host "Copying $dxilDll to $binDir"
    Copy-Item -LiteralPath $dxilDll -Destination (Join-Path $binDir 'dxil.dll') -Force

    # 复制 libs -> lib
    foreach ($libName in @('dxcompiler.lib', 'dxil.lib')) {
        $libPath = Find-BuildArtifact $libName
        Write-Host "Copying $libPath to $libDir"
        Copy-Item -LiteralPath $libPath -Destination (Join-Path $libDir $libName) -Force
    }

	Write-Host '::endgroup::'

	# 6) 压缩打包
	$zipPath = Join-Path $ArtifactsDir $ZipName
	if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    
    Write-Host "Archiving $InstallDir to $zipPath"
	Compress-Archive -Path (Join-Path $InstallDir '*') -DestinationPath $zipPath -Force

	Write-Host "打包完成: $zipPath"

	# 在 GitHub Actions 中输出 artifact 路径
	if ($env:GITHUB_OUTPUT) {
		"artifact=$zipPath" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
	}
}
catch {
	Write-Error $_
	exit 1
}

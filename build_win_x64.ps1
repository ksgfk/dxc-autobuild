#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectDir,
    [string]$BuildDir = (Join-Path $PSScriptRoot 'build'),
    [ValidateSet('Debug','Release','RelWithDebInfo','MinSizeRel')][string]$Config = 'Release',
    [string]$ArtifactsDir = (Join-Path $PSScriptRoot 'artifacts'),
    [string]$ZipName,
    [switch]$UseClangCl,
    [switch]$ExistingBuild,
    [ValidateRange(1,64)][int]$Parallel = 4
)
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $ProjectDir).Path
$versionMatch = [regex]::Match((Get-Content -LiteralPath (Join-Path $source 'CMakeLists.txt') -Raw), 'set\(RADRAY_DXC_PACKAGE_VERSION\s+"([^"]+)"\)')
if (-not $versionMatch.Success) { Write-Error 'Missing source package version'; exit 1 }
$version = $versionMatch.Groups[1].Value
$expectedName = "dxc-windows-x64-$version.zip"
if ($ZipName -and $ZipName -ne $expectedName) { Write-Error "ZipName must be $expectedName"; exit 1 }
$output = [IO.Path]::GetFullPath($ArtifactsDir)
$build = [IO.Path]::GetFullPath($BuildDir)
$archive = Join-Path $output $expectedName
if (Test-Path -LiteralPath $archive) { Write-Error "Refusing to replace existing package: $archive"; exit 1 }
if ($ExistingBuild) {
    if (-not (Test-Path -LiteralPath (Join-Path $build 'CMakeCache.txt'))) { Write-Error 'ExistingBuild requires a configured build'; exit 1 }
} else {
    $configure = @('-S', $source, '-B', $build, '-A', 'x64', '-C', (Join-Path $source 'cmake/caches/PredefinedParams.cmake'),
        "-DCMAKE_BUILD_TYPE=$Config", '-DENABLE_SPIRV_CODEGEN=ON', '-DLIBCLANG_BUILD_STATIC=OFF',
        '-DHLSL_INCLUDE_TESTS=OFF', '-DSPIRV_BUILD_TESTS=OFF', '-DLLVM_INCLUDE_TESTS=OFF')
    if ($UseClangCl) { $configure += @('-T', 'ClangCL', '-DHLSL_ENABLE_FIXED_VER=ON', '-DSPIRV_WERROR=OFF', '-DCMAKE_COMPILE_WARNING_AS_ERROR=OFF') }
    & cmake @configure
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
& cmake --build $build --config $Config --target dxcompiler dxc dxildll --parallel $Parallel
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& python -X utf8 (Join-Path $source 'utils/package_radray_sdk.py') --build $build --config $Config --no-build --out $output --version $version
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($env:GITHUB_OUTPUT) { "artifact=$archive" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append }
Write-Host "Packaged $archive"

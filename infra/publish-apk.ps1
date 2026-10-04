<#
.SYNOPSIS
    Builds the release APK and puts it on GitHub.

.DESCRIPTION
    Two ways to get a downloadable APK, in order of preference:

      1. A GitHub release asset, when the gh CLI is installed and authenticated.
         The APK lives outside the repository, so rebuilding it does not add
         another copy to git history on every run.
      2. The APK committed into the repository, as a fallback. This needs the
         file force-added because apps/mobile/build/ is gitignored, and it is
         worth knowing that a ~20 MB binary is permanent in history: every future
         clone and every rebuild that changes it costs everyone that size again.

    The APK is signed with the debug key, so it installs but is not a store
    build. See android/app/build.gradle.kts.

.PARAMETER BaseUrl
    Overrides the baked-in API_BASE_URL. The default is this machine's LAN
    address, which only works for devices on this network.

.EXAMPLE
    .\infra\publish-apk.ps1
    .\infra\publish-apk.ps1 -BaseUrl https://api.example.com
#>
[CmdletBinding()]
param(
    [string]$BaseUrl,
    [string]$Tag,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mobile = Join-Path $root 'apps\mobile'

function Get-LanAddress {
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceAlias -notmatch 'Loopback|vEthernet|WSL|VMware|VirtualBox|Tailscale' } |
        Sort-Object RouteMetric |
        Select-Object -First 1
    if ($null -eq $route) { return $null }

    $address = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254.*' } |
        Select-Object -First 1
    if ($null -eq $address) { return $null }
    return $address.IPAddress
}

if (-not $BaseUrl) {
    $lan = Get-LanAddress
    if (-not $lan) {
        throw 'No LAN address found. Connect to a network, or pass -BaseUrl explicitly.'
    }
    $BaseUrl = "http://${lan}:8000"
}

Write-Host ''
Write-Host "  API_BASE_URL : $BaseUrl" -ForegroundColor Cyan
if ($BaseUrl -like 'http://*') {
    Write-Host '  This is a LAN address: the APK will only work on this network.' -ForegroundColor Yellow
}
Write-Host ''

$apkDir = Join-Path $mobile 'build\app\outputs\flutter-apk'
$apk = Join-Path $apkDir 'app-release.apk'

if (-not $SkipBuild) {
    Push-Location $mobile
    try {
        Write-Host '==> Building the release APK' -ForegroundColor Cyan
        Write-Host '   The first build downloads Gradle and can take several minutes.' -ForegroundColor DarkGray
        Write-Host ''
        flutter build apk --release --dart-define="API_BASE_URL=$BaseUrl"
        if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed with exit code $LASTEXITCODE" }
    }
    finally {
        Pop-Location
    }
}

if (-not (Test-Path -LiteralPath $apk)) {
    throw "No APK at $apk. Run without -SkipBuild."
}

$sizeMb = [math]::Round((Get-Item -LiteralPath $apk).Length / 1MB, 1)
Write-Host "  APK: $apk ($sizeMb MB)" -ForegroundColor Green

# Hard limit is 100 MB; 50 MB is where GitHub starts warning. A universal APK with
# every ABI can cross that, in which case a split-per-abi build is the fix.
if ($sizeMb -gt 100) {
    throw "APK is $sizeMb MB, over GitHub's 100 MB limit. Build split APKs instead: flutter build apk --release --split-per-abi"
}

Push-Location $root
try {
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    $ghReady = $false
    if ($gh) {
        & gh auth status *> $null
        $ghReady = ($LASTEXITCODE -eq 0)
    }

    if ($ghReady) {
        if (-not $Tag) { $Tag = "apk-$(Get-Date -Format 'yyyyMMdd-HHmm')" }

        Write-Host ''
        Write-Host "==> Publishing release $Tag" -ForegroundColor Cyan
        & gh release create $Tag $apk --title "Demo APK $Tag" `
            --notes "Debug-signed build. API_BASE_URL: $BaseUrl"
        if ($LASTEXITCODE -ne 0) { throw "gh release create failed with exit code $LASTEXITCODE" }

        & gh release view $Tag --json url --jq .url
        Write-Host '   Uploaded as a release asset, so the repository stays clean.' -ForegroundColor Green
    }
    else {
        if ($gh) {
            Write-Host '  gh is installed but not authenticated; skipping the release route.' -ForegroundColor DarkGray
        }
        else {
            Write-Host '  gh CLI not found; falling back to committing the APK.' -ForegroundColor DarkGray
        }

        Write-Host ''
        Write-Host '==> Committing the APK into the repository' -ForegroundColor Cyan

        # apps/mobile/build/ is gitignored, so the APK has to be force-added. This
        # is the tradeoff: the binary is now permanent in history.
        $relative = 'apps/mobile/build/app/outputs/flutter-apk/app-release.apk'
        & git add -f $relative
        if ($LASTEXITCODE -ne 0) { throw "git add failed with exit code $LASTEXITCODE" }

        & git commit -m "Add release APK ($sizeMb MB), signed with the debug key"
        if ($LASTEXITCODE -ne 0) { throw "git commit failed with exit code $LASTEXITCODE" }

        & git push
        if ($LASTEXITCODE -ne 0) { throw "git push failed with exit code $LASTEXITCODE" }

        Write-Host '   Pushed. The APK is downloadable from the repository.' -ForegroundColor Green
    }
}
finally {
    Pop-Location
}
<#
.SYNOPSIS
    Runs the demo so anyone on the same Wi-Fi can use the APK.

.DESCRIPTION
    There is no public host yet, so the backend runs on this machine and the APK
    is built pointing at this machine's LAN address. That is what makes the
    project demonstrable without any deployment: one command, and anyone on the
    same network installs the APK and signs in.

    Two things have to agree or the app looks broken while it is fine:
      - the backend must listen on 0.0.0.0, not 127.0.0.1, or the handset's
        packets never reach it;
      - the APK must carry that same LAN address, baked in at build time via
        --dart-define, because there is no settings screen to type it into.

.EXAMPLE
    .\infra\demo.ps1                 # start the backend, then build the APK
    .\infra\demo.ps1 -SkipApk        # just the backend
    .\infra\demo.ps1 -Port 9000
    .\infra\demo.ps1 -DebugBuild     # build a debug APK
#>
[CmdletBinding()]
param(
    [int]$Port = 8000,
    [switch]$SkipApk,
    # Release by default.
    [switch]$DebugBuild,
    [switch]$Release
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Get-LanAddress {
    # The address of the interface that actually has a route off this machine.
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceAlias -notmatch 'Loopback|vEthernet|WSL|VMware|VirtualBox|Tailscale' } |
        Sort-Object RouteMetric |
        Select-Object -First 1

    if ($null -eq $route) { return $null }

    $address = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254.*' } |
        Sort-Object PrefixOrigin |
        Select-Object -First 1

    if ($null -eq $address) { return $null }

    return $address.IPAddress
}

$lan = Get-LanAddress

if (-not $lan) {
    throw 'No LAN address found. Connect to Wi-Fi or Ethernet and try again.'
}

Write-Host ''
Write-Host "  Backend host : $lan" -ForegroundColor Cyan
Write-Host "  Base URL     : http://${lan}:$Port" -ForegroundColor Cyan
Write-Host ''

Write-Host '  Emulator equivalent: http://10.0.2.2:' -NoNewline -ForegroundColor DarkGray
Write-Host $Port -ForegroundColor DarkGray
Write-Host ''

$python = Join-Path $root 'backend\.venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $python)) {
    throw "Backend virtualenv not found at $python. Create it first: python -m venv backend\.venv"
}

$api = "http://${lan}:$Port"

if (-not $SkipApk) {
    $apkArgs = @('build', 'apk')

    if ($DebugBuild) {
        $apkArgs += '--debug'
    }
    else {
        $apkArgs += '--release'
    }

    $apkArgs += "--dart-define=API_BASE_URL=$api"

    Push-Location (Join-Path $root 'apps\mobile')

    try {
        Write-Host "  flutter $($apkArgs -join ' ')" -ForegroundColor DarkGray

        if (-not $DebugBuild) {
            Write-Host '  The first build downloads Gradle and can take several minutes.' -ForegroundColor DarkGray
            Write-Host '  Let it finish; interrupting it leaves a half-written build.' -ForegroundColor DarkGray
        }

        Write-Host ''
        flutter @apkArgs

        if ($LASTEXITCODE -ne 0) {
            throw "flutter build apk failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }

    $apk = Join-Path $root 'apps\mobile\build\app\outputs\flutter-apk'

    Write-Host ''
    Write-Host "  APK: $apk" -ForegroundColor Green
    Write-Host '  Install over USB: adb install -r app-release.apk' -ForegroundColor DarkGray
    Write-Host '  Or copy the APK to a handset and open it there (allow unknown sources).' -ForegroundColor DarkGray
    Write-Host '  Keep the handset on this same Wi-Fi, or it cannot reach the API.' -ForegroundColor DarkGray
    Write-Host ''
}

Write-Host '  Starting the API. Leave this window open while the demo runs.' -ForegroundColor Yellow
Write-Host ''
Write-Host '  Signing in: any email address works, and a new account is created on the' -ForegroundColor DarkGray
Write-Host '  first use. The one-time code is printed below as otp_issued, so read it' -ForegroundColor DarkGray
Write-Host '  out of this window and type it into the app.' -ForegroundColor DarkGray
Write-Host ''

# Enable debug logging for this process only so the OTP is printed.
$env:DEBUG = 'true'

Push-Location (Join-Path $root 'backend')

try {
    & $python -m uvicorn app.main:create_app --factory --host 0.0.0.0 --port $Port
}
finally {
    Pop-Location
}
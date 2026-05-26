# detect.ps1 - Comprehensive environment detection
# Run with: powershell -ExecutionPolicy Bypass -File detect.ps1

$outputDir  = Join-Path $env:USERPROFILE ".preflight"
$outputPath = Join-Path $outputDir "env-config.json"
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Force $outputDir | Out-Null }

Write-Host "Scanning environment..." -ForegroundColor Cyan

# ─── HELPERS ──────────────────────────────────────────────────────────────────

function nf  { param($v) if ($v -and "$v".Trim() -ne "") { "$v".Trim() } else { "not found" } }
function ns  { param($v) if ($v -and "$v".Trim() -ne "") { "$v".Trim() } else { "not set"   } }
function nfd { param($v) if ($v -and "$v".Trim() -ne "") { "$v".Trim() } else { "not configured" } }

function safe {
    param([scriptblock]$b)
    try { $r = & $b; if ($r) { "$r".Trim() } else { $null } } catch { $null }
}

function Get-ExeVersion {
    param([string]$p)
    if (-not (Test-Path $p -ErrorAction SilentlyContinue)) { return $null }
    try { return (Get-Item $p -ErrorAction Stop).VersionInfo.FileVersion } catch { return $null }
}

# ─── PROGRAM SCANNER ──────────────────────────────────────────────────────────

function Scan-InstalledPrograms {
    $results = [ordered]@{}

    function try-ver {
        param([string]$exe, [string[]]$a)
        try { $o = & $exe @a 2>&1 | Select-Object -First 1; if ($o) { "$o".Trim() } else { $null } } catch { $null }
    }
    function find-exe {
        param([string]$name)
        try { (Get-Command $name -ErrorAction Stop).Source } catch { $null }
    }
    function probe {
        param([string[]]$paths)
        foreach ($p in $paths) { if ($p -and (Test-Path $p -ErrorAction SilentlyContinue)) { return $p } }
        return $null
    }

    # ── DATABASES ────────────────────────────────────────────────────────────
    Write-Host "    databases..." -NoNewline

    # Redis
    $exe = find-exe "redis-server"
    if (-not $exe) { $exe = probe @("C:\Program Files\Redis\redis-server.exe","C:\Redis\redis-server.exe") }
    $ver = if ($exe) { $v = try-ver $exe @("--version"); if ($v -match "v=([\d.]+)") { $Matches[1] } else { $v } } else { $null }
    $cfg = probe @("C:\Program Files\Redis\redis.windows.conf","C:\Redis\redis.windows.conf")
    $results["redis"] = [ordered]@{
        installed = ($null -ne $exe); version = if ($ver) { $ver } else { "not installed" }
        path = if ($exe) { $exe } else { "not found" }; port = 6379
        config_file = if ($cfg) { $cfg } else { "not found" }
    }

    # PostgreSQL
    $exe = find-exe "psql"
    if (-not $exe) {
        $pgDir = Get-ChildItem "C:\Program Files\PostgreSQL" -Directory -ErrorAction SilentlyContinue |
                 Sort-Object Name -Descending | Select-Object -First 1
        if ($pgDir) { $exe = probe @((Join-Path $pgDir.FullName "bin\psql.exe")) }
    }
    $ver = if ($exe) { $v = try-ver $exe @("--version"); if ($v -match "([\d.]+)$") { $Matches[1] } else { $v } } else { $null }
    $results["postgresql"] = [ordered]@{
        installed = ($null -ne $exe); version = if ($ver) { $ver } else { "not installed" }
        path = if ($exe) { $exe } else { "not found" }; port = 5432
        data_dir = if ($env:PGDATA) { $env:PGDATA } else { "not configured" }
    }

    # MongoDB
    $exe = find-exe "mongod"
    if (-not $exe) {
        $mgDir = Get-ChildItem "C:\Program Files\MongoDB\Server" -Directory -ErrorAction SilentlyContinue |
                 Sort-Object Name -Descending | Select-Object -First 1
        if ($mgDir) { $exe = probe @((Join-Path $mgDir.FullName "bin\mongod.exe")) }
    }
    $ver = if ($exe) { $v = try-ver $exe @("--version"); if ($v -match "([\d.]+)") { $Matches[1] } else { $v } } else { $null }
    $dataDir = probe @("C:\data\db","C:\MongoDB\data")
    $results["mongodb"] = [ordered]@{
        installed = ($null -ne $exe); version = if ($ver) { $ver } else { "not installed" }
        path = if ($exe) { $exe } else { "not found" }; port = 27017
        data_dir = if ($dataDir) { $dataDir } else { "not found" }
    }

    # MySQL
    $exe = find-exe "mysql"
    if (-not $exe) { $exe = probe @("C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe","C:\Program Files\MySQL\MySQL Server 5.7\bin\mysql.exe") }
    $ver = if ($exe) { $v = try-ver $exe @("--version"); if ($v -match "([\d.]+)") { $Matches[1] } else { $v } } else { $null }
    $cfg = probe @("C:\ProgramData\MySQL\MySQL Server 8.0\my.ini","C:\ProgramData\MySQL\MySQL Server 5.7\my.ini","C:\Windows\my.ini")
    $results["mysql"] = [ordered]@{
        installed = ($null -ne $exe); version = if ($ver) { $ver } else { "not installed" }
        path = if ($exe) { $exe } else { "not found" }; port = 3306
        config_file = if ($cfg) { $cfg } else { "not found" }
    }

    # SQLite
    $exe = find-exe "sqlite3"
    $ver = if ($exe) { $v = try-ver $exe @("--version"); if ($v) { ($v -split '\s+')[0] } else { $null } } else { $null }
    $results["sqlite"] = [ordered]@{
        installed = ($null -ne $exe); version = if ($ver) { $ver } else { "not installed" }
        path = if ($exe) { $exe } else { "not found" }
    }

    Write-Host " done" -ForegroundColor Green

    # ── WEB SERVERS ──────────────────────────────────────────────────────────
    Write-Host "    web servers..." -NoNewline

    # Nginx
    $exe = find-exe "nginx"
    if (-not $exe) { $exe = probe @("C:\nginx\nginx.exe","C:\Program Files\nginx\nginx.exe") }
    $ver = if ($exe) { $v = try-ver $exe @("-v"); if ($v -match "nginx/([\d.]+)") { $Matches[1] } else { $v } } else { $null }
    $cfgPath = if ($exe) { Join-Path (Split-Path $exe) "conf\nginx.conf" } else { $null }
    $results["nginx"] = [ordered]@{
        installed = ($null -ne $exe); version = if ($ver) { $ver } else { "not installed" }
        path = if ($exe) { $exe } else { "not found" }; port = 80
        config_file = if ($cfgPath -and (Test-Path $cfgPath -ErrorAction SilentlyContinue)) { $cfgPath } else { "not found" }
    }

    # Apache
    $exe = find-exe "httpd"
    if (-not $exe) { $exe = probe @("C:\Apache24\bin\httpd.exe","C:\Program Files\Apache Group\Apache2\bin\httpd.exe") }
    $ver = if ($exe) { $v = try-ver $exe @("-v"); if ($v -match "([\d.]+)") { $Matches[1] } else { $v } } else { $null }
    $cfgPath = if ($exe) { Join-Path (Split-Path (Split-Path $exe)) "conf\httpd.conf" } else { $null }
    $results["apache"] = [ordered]@{
        installed = ($null -ne $exe); version = if ($ver) { $ver } else { "not installed" }
        path = if ($exe) { $exe } else { "not found" }; port = 80
        config_file = if ($cfgPath -and (Test-Path $cfgPath -ErrorAction SilentlyContinue)) { $cfgPath } else { "not found" }
    }

    Write-Host " done" -ForegroundColor Green

    # ── LANGUAGES ────────────────────────────────────────────────────────────
    Write-Host "    languages..." -NoNewline

    # Rust
    $exe = find-exe "rustc"
    $ver = if ($exe) { $v = try-ver $exe @("--version"); if ($v -match "rustc\s+([\d.]+)") { $Matches[1] } else { $v } } else { $null }
    $cargo = find-exe "cargo"
    $results["rust"] = [ordered]@{
        installed = ($null -ne $exe); version = if ($ver) { $ver } else { "not installed" }
        rustc_path = if ($exe) { $exe } else { "not found" }
        cargo_path = if ($cargo) { $cargo } else { "not found" }
    }

    # Go
    $exe = find-exe "go"
    $ver = if ($exe) { $v = try-ver $exe @("version"); if ($v -match "go([\d.]+)") { $Matches[1] } else { $v } } else { $null }
    $gopath = if ($env:GOPATH) { $env:GOPATH } elseif ($exe) { Join-Path $env:USERPROFILE "go" } else { $null }
    $results["go"] = [ordered]@{
        installed = ($null -ne $exe); version = if ($ver) { $ver } else { "not installed" }
        path = if ($exe) { $exe } else { "not found" }
        GOPATH = if ($gopath) { $gopath } else { "not configured" }
    }

    # Ruby
    $exe = find-exe "ruby"
    $ver = if ($exe) { $v = try-ver $exe @("--version"); if ($v -match "ruby\s+([\d.p]+)") { $Matches[1] } else { $v } } else { $null }
    $results["ruby"] = [ordered]@{
        installed = ($null -ne $exe); version = if ($ver) { $ver } else { "not installed" }
        path = if ($exe) { $exe } else { "not found" }
    }

    Write-Host " done" -ForegroundColor Green

    # ── AI & ML ──────────────────────────────────────────────────────────────
    Write-Host "    ai_ml..." -NoNewline

    # Ollama
    $exe = find-exe "ollama"
    if (-not $exe) { $exe = probe @((Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe")) }
    $ver = if ($exe) { try-ver $exe @("--version") } else { $null }
    $models = @()
    if ($exe) {
        try {
            $job = Start-Job { & $using:exe list 2>&1 | Select-Object -Skip 1 }
            $ml  = $job | Wait-Job -Timeout 5 | Receive-Job
            Remove-Job $job -Force -ErrorAction SilentlyContinue
            $models = @($ml | Where-Object { $_ -match '\S' } | ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ })
        } catch {}
    }
    $results["ollama"] = [ordered]@{
        installed = ($null -ne $exe); version = if ($ver) { $ver } else { "not installed" }
        path = if ($exe) { $exe } else { "not found" }; port = 11434; models = $models
    }

    # CUDA
    $exe = find-exe "nvcc"
    $ver = if ($exe) { $v = try-ver $exe @("--version"); if ($v -match "release\s+([\d.]+)") { $Matches[1] } else { $v } } else { $null }
    $gpu = safe { (Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name -match "NVIDIA" } | Select-Object -First 1).Name }
    $results["cuda"] = [ordered]@{
        installed = ($null -ne $exe); version = if ($ver) { $ver } else { "not installed" }
        nvcc_path = if ($exe) { $exe } else { "not found" }
        gpu = if ($gpu) { $gpu } else { "no NVIDIA GPU detected" }
    }

    Write-Host " done" -ForegroundColor Green

    # ── DEV TOOLS ────────────────────────────────────────────────────────────
    Write-Host "    dev_tools..." -NoNewline

    # Android Studio
    $studioPath = probe @("D:\Android Studio\bin\studio64.exe","C:\Program Files\Android\Android Studio\bin\studio64.exe")
    $studioVer  = if ($studioPath) { Get-ExeVersion $studioPath } else { $null }
    $sdkRoot    = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { "D:\Sdk" }
    $sdkMgr     = probe @((Join-Path $sdkRoot "cmdline-tools\latest\bin\sdkmanager.bat"),(Join-Path $sdkRoot "tools\bin\sdkmanager.bat"))
    $results["android_studio"] = [ordered]@{
        installed = ($null -ne $studioPath)
        version = if ($studioVer) { $studioVer } else { "not installed" }
        path = if ($studioPath) { $studioPath } else { "not found" }
        sdkmanager_path = if ($sdkMgr) { $sdkMgr } else { "not found" }
    }

    # PyCharm
    $pcPath = $null
    $pcDir = Get-ChildItem "C:\Program Files\JetBrains" -Directory -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -like "PyCharm*" } | Sort-Object Name -Descending | Select-Object -First 1
    if ($pcDir) { $pcPath = probe @((Join-Path $pcDir.FullName "bin\pycharm64.exe")) }
    if (-not $pcPath) {
        $pcReg = Get-ChildItem "HKLM:\SOFTWARE\JetBrains" -ErrorAction SilentlyContinue |
                 Where-Object { $_.PSChildName -like "PyCharm*" } | Select-Object -First 1
        if ($pcReg) {
            $loc = (Get-ItemProperty $pcReg.PSPath -ErrorAction SilentlyContinue).InstallLocation
            if ($loc) { $pcPath = probe @((Join-Path $loc "bin\pycharm64.exe")) }
        }
    }
    $pcVer    = if ($pcPath) { Get-ExeVersion $pcPath } else { $null }
    $pcInterp = safe { & python -c "import sys; print(sys.executable)" 2>$null }
    $results["pycharm"] = [ordered]@{
        installed = ($null -ne $pcVer)
        version = if ($pcVer) { $pcVer } else { "not installed" }
        path = if ($pcPath) { $pcPath } else { "not found" }
        default_interpreter = if ($pcInterp) { $pcInterp } else { "not detected" }
    }

    # Postman
    $exe = probe @(
        (Join-Path $env:LOCALAPPDATA "Postman\Postman.exe"),
        (Join-Path $env:APPDATA     "Postman\Postman.exe"),
        "C:\Program Files\Postman\Postman.exe"
    )
    $ver = if ($exe) { Get-ExeVersion $exe } else { $null }
    $results["postman"] = [ordered]@{
        installed = ($null -ne $exe); version = if ($ver) { $ver } else { "not installed" }
        path = if ($exe) { $exe } else { "not found" }
    }

    # TablePlus
    $exe = probe @(
        (Join-Path $env:LOCALAPPDATA "TablePlus\TablePlus.exe"),
        "C:\Program Files\TablePlus\TablePlus.exe"
    )
    $ver = if ($exe) { Get-ExeVersion $exe } else { $null }
    $results["tableplus"] = [ordered]@{
        installed = ($null -ne $exe); version = if ($ver) { $ver } else { "not installed" }
        path = if ($exe) { $exe } else { "not found" }
    }

    Write-Host " done" -ForegroundColor Green

    # ── CLOUD TOOLS ──────────────────────────────────────────────────────────
    Write-Host "    cloud..." -NoNewline

    # AWS CLI
    $exe = find-exe "aws"
    $ver = if ($exe) { $v = try-ver $exe @("--version"); if ($v -match "aws-cli/([\d.]+)") { $Matches[1] } else { $v } } else { $null }
    $region = if ($exe) { safe { & $exe configure get region 2>&1 } } else { $null }
    $results["aws_cli"] = [ordered]@{
        installed = ($null -ne $exe); version = if ($ver) { $ver } else { "not installed" }
        path = if ($exe) { $exe } else { "not found" }
        configured_region = if ($region) { $region } else { "not configured" }
    }

    # Google Cloud CLI
    $exe = find-exe "gcloud"
    $ver = if ($exe) { $v = try-ver $exe @("version"); if ($v -match "Google Cloud SDK ([\d.]+)") { $Matches[1] } else { $v } } else { $null }
    $results["gcloud"] = [ordered]@{
        installed = ($null -ne $exe); version = if ($ver) { $ver } else { "not installed" }
        path = if ($exe) { $exe } else { "not found" }
    }

    # Azure CLI
    $exe = find-exe "az"
    $ver = if ($exe) { $v = try-ver $exe @("--version"); if ($v -match "azure-cli\s+([\d.]+)") { $Matches[1] } else { ($v -split '\s+')[0] } } else { $null }
    $results["azure_cli"] = [ordered]@{
        installed = ($null -ne $exe); version = if ($ver) { $ver } else { "not installed" }
        path = if ($exe) { $exe } else { "not found" }
    }

    Write-Host " done" -ForegroundColor Green

    return $results
}

function Scan-PreflightJson {
    $discovered = @()
    $seen       = @{}

    $searchDirs = @($env:PATH -split ";" | Where-Object { $_.Trim() -ne "" } | Select-Object -Unique)
    $roots = @(
        "C:\Program Files", "C:\Program Files (x86)",
        (Join-Path $env:LOCALAPPDATA "Programs"),
        $env:APPDATA, "D:\"
    )
    foreach ($root in $roots) {
        if (Test-Path $root -ErrorAction SilentlyContinue) {
            $searchDirs += @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
                            Select-Object -ExpandProperty FullName)
        }
    }

    foreach ($dir in ($searchDirs | Select-Object -Unique)) {
        $pf = Join-Path $dir "preflight.json"
        if ((Test-Path $pf -ErrorAction SilentlyContinue) -and -not $seen[$pf]) {
            $seen[$pf] = $true
            try {
                $data = Get-Content $pf -Raw -ErrorAction Stop | ConvertFrom-Json
                if ($data.name) {
                    $discovered += [ordered]@{
                        name        = "$($data.name)"
                        version     = if ($data.version)     { "$($data.version)" }     else { "unknown" }
                        added_at    = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK")
                        description = if ($data.description) { "$($data.description)" } else { "registered via preflight.json at $pf" }
                        source      = $pf
                    }
                }
            } catch {}
        }
    }
    return $discovered
}

# ─── SYSTEM ───────────────────────────────────────────────────────────────────

Write-Host "  system..." -NoNewline
$osVersion = "unknown"
try {
    $osInfo    = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $osVersion = "$($osInfo.Caption) (Build $($osInfo.BuildNumber))"
} catch {
    Write-Warning "system detection failed: $($_.Exception.Message)"
}
Write-Host " done" -ForegroundColor Green

# ─── HARDWARE ─────────────────────────────────────────────────────────────────

Write-Host "  hardware..." -NoNewline

$cpu   = "unknown"
$ramGB = 0
$diskInfo = "not found"
try {
    $cpuRaw = safe { (Get-CimInstance Win32_Processor | Select-Object -First 1).Name }
    $cpu    = nf $cpuRaw

    $ramRaw = safe { [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2) }
    $ramGB  = if ($ramRaw) { [double]$ramRaw } else { 0 }

    $diskD    = Get-PSDrive D -ErrorAction SilentlyContinue
    $diskInfo = if ($diskD) {
        [ordered]@{
            total_GB = [math]::Round(($diskD.Used + $diskD.Free) / 1GB, 2)
            used_GB  = [math]::Round($diskD.Used  / 1GB, 2)
            free_GB  = [math]::Round($diskD.Free  / 1GB, 2)
        }
    } else { "not found" }
} catch {
    Write-Warning "hardware detection failed: $($_.Exception.Message)"
}
Write-Host " done" -ForegroundColor Green

# ─── SHELL ────────────────────────────────────────────────────────────────────

Write-Host "  shell..." -NoNewline

$psVersion  = $PSVersionTable.PSVersion.ToString()
$execPolicy = (Get-ExecutionPolicy -Scope CurrentUser).ToString()

$defaultShell = if ($env:SHELL)    { $env:SHELL }
                elseif ($env:COMSPEC) { $env:COMSPEC }
                else               { "unknown" }

# Read env vars — prefer process env, fall back to user-level registry
# (covers vars set this session via [Environment]::SetEnvironmentVariable)
function Get-EnvVar {
    param([string]$Name)
    $v = [System.Environment]::GetEnvironmentVariable($Name)
    if (-not $v) { $v = [System.Environment]::GetEnvironmentVariable($Name, "User") }
    if (-not $v) { $v = [System.Environment]::GetEnvironmentVariable($Name, "Machine") }
    return $v
}

$envVars = [ordered]@{
    JAVA_HOME    = ns (Get-EnvVar "JAVA_HOME")
    PYTHON_PATH  = ns (Get-EnvVar "PYTHON_PATH")
    ANDROID_HOME = ns (Get-EnvVar "ANDROID_HOME")
    FLUTTER_HOME = ns (Get-EnvVar "FLUTTER_HOME")
}

$pathEntries = @($env:PATH -split ";" | Where-Object { $_.Trim() -ne "" } | Select-Object -Unique)

$sshDir  = Join-Path $env:USERPROFILE ".ssh"
$sshKeys = @()

# Collect keys from ~/.ssh directly
if (Test-Path $sshDir) {
    $sshKeys += @(
        Get-ChildItem $sshDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^id_|\.pub$|\.pem$" } |
        Select-Object -ExpandProperty FullName
    )
}

# Also parse IdentityFile entries from ~/.ssh/config
$sshConfig = Join-Path $sshDir "config"
if (Test-Path $sshConfig) {
    Get-Content $sshConfig -ErrorAction SilentlyContinue |
    Where-Object { $_ -match "^\s*IdentityFile\s+(.+)" } |
    ForEach-Object {
        $raw = $Matches[1].Trim()
        # Normalise D:path → D:\path if backslash is missing
        $raw = $raw -replace '^([A-Za-z]):([^\\])', '$1:\$2'
        $expanded = [System.Environment]::ExpandEnvironmentVariables($raw)
        if ((Test-Path $expanded -ErrorAction SilentlyContinue) -and ($sshKeys -notcontains $expanded)) {
            $sshKeys += $expanded
        }
    }
}

$sshKeys = @($sshKeys | Select-Object -Unique)

# WSL — parse wsl --list --verbose
# wsl.exe stdout is UTF-32-in-UTF-16 context: every char has trailing null bytes.
# Fix: strip [char]0 first, then split columns on 2+ spaces.
# The default distro line starts with "* Name ..." — detect * on the full line.
$wslInfo = [ordered]@{ status = "not available" }
$wslExe  = [IO.Path]::Combine($env:SystemRoot, "System32", "wsl.exe")
try {
    if (Test-Path $wslExe) {
        $wslLines = & $wslExe --list --verbose 2>&1
        $distros  = @()
        foreach ($line in $wslLines) {
            $raw = ("$line" -replace [char]0, '').Trim()
            if ($raw -eq '' -or $raw -match '^NAME') { continue }

            $isDefault = $raw.StartsWith('*')
            if ($isDefault) { $raw = $raw.Substring(1).Trim() }

            $tokens = ($raw -split '\s{2,}') |
                      ForEach-Object { $_.Trim() } |
                      Where-Object   { $_ -ne '' }

            # tokens: [Name, State, Version]
            if ($tokens.Count -ge 1 -and $tokens[0] -ne '') {
                $distros += [ordered]@{
                    name       = $tokens[0]
                    state      = if ($tokens.Count -gt 1) { $tokens[1] } else { "unknown" }
                    version    = if ($tokens.Count -gt 2) { "WSL$($tokens[2])" } else { "unknown" }
                    is_default = $isDefault
                }
            }
        }
        $wslInfo = if ($distros.Count -gt 0) {
            [ordered]@{ installed = $true; distros = $distros }
        } else {
            [ordered]@{ status = "not installed" }
        }
    } else {
        $wslInfo = [ordered]@{ status = "wsl.exe not found" }
    }
} catch {
    $wslInfo = [ordered]@{ status = "error: $($_.Exception.Message)" }
}

Write-Host " done" -ForegroundColor Green

# ─── RUNTIMES ─────────────────────────────────────────────────────────────────

Write-Host "  runtimes..." -NoNewline
try {

# Node
$nodeRaw = safe { & node --version 2>$null }
$nodeVersion = if ($nodeRaw) { $nodeRaw -replace "^v","" } else { "not found" }

# npm
$npmRaw = safe { & npm --version 2>$null | Select-Object -First 1 }
$npmVersion = if ($npmRaw -match '^\d') { $npmRaw } else { "not found" }

# yarn
$yarnRaw = safe { & yarn --version 2>$null | Select-Object -First 1 }
$yarnVersion = if ($yarnRaw -match '^\d') { $yarnRaw } else { "not found" }

# pnpm
$pnpmRaw = safe { & pnpm --version 2>$null | Select-Object -First 1 }
$pnpmVersion = if ($pnpmRaw -match '^\d') { $pnpmRaw } else { "not found" }

# Python
$pythonVersion = "not found"
foreach ($cmd in @("python","python3")) {
    $v = safe { & $cmd --version 2>&1 | Select-Object -First 1 }
    if ("$v" -match "Python\s+([\d.]+)") { $pythonVersion = $Matches[1]; break }
}

# Python packages via pip
$pythonPackages = @()
if ($pythonVersion -ne "not found") {
    try {
        $pipJson = & pip list --format=json 2>$null | Out-String
        $pipObjs = $pipJson.Trim() | ConvertFrom-Json
        $pythonPackages = @($pipObjs | ForEach-Object { "$($_.name)==$($_.version)" })
    } catch {
        try {
            $pipLines = & pip list 2>$null | Select-Object -Skip 2
            $pythonPackages = @(
                $pipLines | Where-Object { $_ -match '\S' } | ForEach-Object {
                    $p = ($_ -split '\s+', 2)
                    if ($p.Count -ge 2) { "$($p[0].Trim())==$($p[1].Trim())" }
                } | Where-Object { $_ }
            )
        } catch {}
    }
}

# Git
$gitRaw = safe { & git --version 2>$null }
$gitVersion = if ($gitRaw) { $gitRaw -replace "^git version\s*","" } else { "not found" }

$gitUsername      = safe { & git config --global user.name  2>$null }
$gitEmail         = safe { & git config --global user.email 2>$null }
$gitDefaultBranch = safe { & git config --global init.defaultBranch 2>$null }

$gitConfig = [ordered]@{
    version        = $gitVersion
    username       = nfd $gitUsername
    email          = nfd $gitEmail
    default_branch = nfd $gitDefaultBranch
}

# Docker
$dockerRaw = safe { & docker --version 2>$null }
$dockerVersion = if ($dockerRaw) {
    $dockerRaw -replace "^Docker version\s*","" -replace ",.*$",""
} else { "not found" }

# Global npm packages
$globalNpmPackages = @()
if ($npmVersion -ne "not found") {
    try {
        $npmJson = & npm list -g --depth=0 --json 2>$null | Out-String
        $npmObj  = $npmJson | ConvertFrom-Json
        if ($npmObj.dependencies) {
            $globalNpmPackages = @(
                $npmObj.dependencies.PSObject.Properties |
                ForEach-Object { "$($_.Name)@$($_.Value.version)" }
            )
        }
    } catch {}
}

} catch {
    Write-Warning "runtimes detection failed: $($_.Exception.Message)"
}
Write-Host " done" -ForegroundColor Green

# ─── EDITORS ──────────────────────────────────────────────────────────────────

Write-Host "  editors (VS Code extensions may take a moment)..." -NoNewline

$vscodeVersion    = "not found"
$vscodeExtensions = @()
try {
    $vscodeRaw     = safe { & code --version 2>$null | Select-Object -First 1 }
    $vscodeVersion = nf $vscodeRaw

    if ($vscodeVersion -ne "not found") {
        $vscodeExtensions = @(
            & code --list-extensions --show-versions 2>$null |
            Where-Object { $_ -match "\." }
        )
    }
} catch {
    Write-Warning "editors detection failed: $($_.Exception.Message)"
}
Write-Host " done" -ForegroundColor Green

# ─── MOBILE DEV ───────────────────────────────────────────────────────────────

Write-Host "  mobile_dev..." -NoNewline

$flutterVersion    = "not found"
$dartVersion       = "not found"
$androidSdkPath    = "not set"
$androidSdkVersion = "not found"
try {
    $flutterRaw = safe { & flutter --version 2>$null | Select-Object -First 1 }
    if ("$flutterRaw" -match "Flutter\s+([\d.]+)") { $flutterVersion = $Matches[1] }

    $dartRaw = safe { & dart --version 2>&1 | Select-Object -First 1 }
    if ("$dartRaw" -match "[\s:]+([\d.]+)") { $dartVersion = $Matches[1] }

    # Re-read ANDROID_HOME from user environment (may have just been set this session)
    $androidHomeEnv = [Environment]::GetEnvironmentVariable("ANDROID_HOME", "User")
    if (-not $androidHomeEnv) { $androidHomeEnv = $env:ANDROID_HOME }
    if (-not $androidHomeEnv) { $androidHomeEnv = $env:ANDROID_SDK_ROOT }

    # Also probe known non-standard paths if env var still missing
    if (-not $androidHomeEnv) {
        $sdkProbe = @('D:\Sdk', 'C:\Android\Sdk', 'D:\Android\Sdk',
                      (Join-Path $env:LOCALAPPDATA "Android\Sdk"),
                      (Join-Path $env:PROGRAMFILES "Android\android-sdk"))
        foreach ($p in $sdkProbe) {
            if (Test-Path (Join-Path $p "platform-tools\adb.exe")) {
                $androidHomeEnv = $p; break
            }
        }
    }

    $androidHome       = $androidHomeEnv
    $androidSdkPath    = if ($androidHome) { $androidHome } else { "not set" }

    if ($androidHome) {
        $btDir = Join-Path $androidHome "build-tools"
        if (Test-Path $btDir) {
            $top = Get-ChildItem $btDir -Directory -ErrorAction SilentlyContinue |
                   Sort-Object Name -Descending | Select-Object -First 1
            if ($top) { $androidSdkVersion = $top.Name }
        }
        if ($androidSdkVersion -eq "not found") {
            foreach ($mgr in @(
                (Join-Path $androidHome "cmdline-tools\latest\bin\sdkmanager.bat"),
                (Join-Path $androidHome "tools\bin\sdkmanager.bat")
            )) {
                if (Test-Path $mgr) {
                    $v = safe { & $mgr --version 2>$null | Select-Object -First 1 }
                    if ($v -match '^\d') { $androidSdkVersion = $v; break }
                }
            }
        }
    }
} catch {
    Write-Warning "mobile_dev detection failed: $($_.Exception.Message)"
}
Write-Host " done" -ForegroundColor Green

# ─── NETWORK ──────────────────────────────────────────────────────────────────

Write-Host "  network & browsers..." -NoNewline

$networkType = "unknown"
$browsers    = [ordered]@{ chrome = "not found"; firefox = "not found"; edge = "not found" }
$cdnLatency  = [ordered]@{}
try {
    $adapter = Get-NetAdapter -ErrorAction Stop |
               Where-Object Status -eq "Up" | Select-Object -First 1
    if ($adapter) { $networkType = "$($adapter.InterfaceDescription) [$($adapter.Name)]" }
} catch {}

# Proxy settings
$proxyInfo = [ordered]@{ status = "unknown" }
try {
    $proxyOut = & netsh winhttp show proxy 2>&1 | Out-String
    if ($proxyOut -match "Direct access") {
        $proxyInfo = [ordered]@{ status = "direct (no proxy)" }
    } elseif ($proxyOut -match "Proxy Server\(s\)\s*:\s*(.+)") {
        $proxyServer = $Matches[1].Trim()
        $bypassList  = if ($proxyOut -match "Bypass List\s*:\s*(.+)") { $Matches[1].Trim() } else { "none" }
        $proxyInfo   = [ordered]@{
            status      = "configured"
            server      = $proxyServer
            bypass_list = $bypassList
        }
    }
} catch {
    $proxyInfo = [ordered]@{ status = "error reading proxy" }
}

# Browsers
try {
    $chromePaths = @(
        (Join-Path $env:PROGRAMFILES "Google\Chrome\Application\chrome.exe"),
        (Join-Path ${env:PROGRAMFILES(x86)} "Google\Chrome\Application\chrome.exe"),
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
    )
    $firefoxPaths = @(
        (Join-Path $env:PROGRAMFILES "Mozilla Firefox\firefox.exe"),
        (Join-Path ${env:PROGRAMFILES(x86)} "Mozilla Firefox\firefox.exe")
    )
    $edgePaths = @(
        (Join-Path $env:PROGRAMFILES "Microsoft\Edge\Application\msedge.exe"),
        (Join-Path ${env:PROGRAMFILES(x86)} "Microsoft\Edge\Application\msedge.exe")
    )

    $chromeV  = ($chromePaths  | ForEach-Object { Get-ExeVersion $_ } | Where-Object { $_ } | Select-Object -First 1)
    $firefoxV = ($firefoxPaths | ForEach-Object { Get-ExeVersion $_ } | Where-Object { $_ } | Select-Object -First 1)
    $edgeV    = ($edgePaths    | ForEach-Object { Get-ExeVersion $_ } | Where-Object { $_ } | Select-Object -First 1)

    $browsers = [ordered]@{
        chrome  = nf $chromeV
        firefox = nf $firefoxV
        edge    = nf $edgeV
    }
} catch {
    Write-Warning "browser detection failed: $($_.Exception.Message)"
}

# CDN latency (HEAD request, 8 s timeout each)
$cdnTargets = [ordered]@{
    cdnjs    = "https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.0/jquery.min.js"
    jsdelivr = "https://cdn.jsdelivr.net/npm/jquery@3.6.0/dist/jquery.min.js"
    unpkg    = "https://unpkg.com/jquery@3.6.0/dist/jquery.min.js"
    skypack  = "https://cdn.skypack.dev/lodash@4.17.21"
}

$cdnLatency = [ordered]@{}
foreach ($entry in $cdnTargets.GetEnumerator()) {
    try {
        $req         = [System.Net.WebRequest]::Create($entry.Value)
        $req.Method  = "HEAD"
        $req.Timeout = 8000
        $sw          = [System.Diagnostics.Stopwatch]::StartNew()
        $resp        = $req.GetResponse()
        $sw.Stop()
        $resp.Close()
        $cdnLatency[$entry.Key] = "$($sw.ElapsedMilliseconds) ms"
    } catch {
        $cdnLatency[$entry.Key] = "timeout/error"
    }
}

Write-Host " done" -ForegroundColor Green

# ─── INSTALLED PROGRAMS ───────────────────────────────────────────────────────

Write-Host "  installed_programs..." -ForegroundColor Cyan
$installedPrograms = Scan-InstalledPrograms

Write-Host "  preflight.json scan..." -NoNewline
$preflightDiscovered = Scan-PreflightJson
Write-Host " done ($($preflightDiscovered.Count) found)" -ForegroundColor Green

# Preserve manually-added extensions from previous run; merge with preflight.json discoveries
$existingExtensions = @()
if (Test-Path $outputPath -ErrorAction SilentlyContinue) {
    try {
        $prev = Get-Content $outputPath -Raw | ConvertFrom-Json
        if ($prev.extensions) {
            $existingExtensions = @($prev.extensions | ForEach-Object {
                [ordered]@{
                    name        = "$($_.name)"
                    version     = "$($_.version)"
                    added_at    = "$($_.added_at)"
                    description = "$($_.description)"
                }
            })
        }
    } catch {}
}
$mergedExtensions = @($preflightDiscovered)
foreach ($ext in $existingExtensions) {
    if (-not ($mergedExtensions | Where-Object { $_.name -eq $ext.name })) {
        $mergedExtensions += $ext
    }
}

# ─── ASSEMBLE ─────────────────────────────────────────────────────────────────

Write-Host "  writing JSON..." -NoNewline

$config = [ordered]@{
    config_version = "1.3"
    generated_at   = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK")

    system = [ordered]@{
        os = $osVersion
    }

    hardware = [ordered]@{
        cpu    = $cpu
        ram_GB = $ramGB
        disk_D = $diskInfo
    }

    shell = [ordered]@{
        default_shell = $defaultShell
        powershell    = [ordered]@{
            version          = $psVersion
            execution_policy = $execPolicy
        }
        env_vars         = $envVars
        ssh_keys_present = ($sshKeys.Count -gt 0)
        ssh_key_files    = @($sshKeys)
        wsl              = $wslInfo
        proxy            = $proxyInfo
        path_entries     = @($pathEntries)
    }

    runtimes = [ordered]@{
        node                = $nodeVersion
        npm                 = $npmVersion
        yarn                = $yarnVersion
        pnpm                = $pnpmVersion
        python          = $pythonVersion
        python_packages = @($pythonPackages)
        git             = $gitConfig
        docker              = $dockerVersion
        global_npm_packages = @($globalNpmPackages)
    }

    editors = [ordered]@{
        vscode = [ordered]@{
            version    = $vscodeVersion
            extensions = @($vscodeExtensions)
        }
    }

    mobile_dev = [ordered]@{
        flutter     = $flutterVersion
        dart        = $dartVersion
        android_sdk = [ordered]@{
            path    = $androidSdkPath
            version = $androidSdkVersion
        }
    }

    network = [ordered]@{
        type           = $networkType
        browsers       = $browsers
        cdn_latency_ms = $cdnLatency
    }

    installed_programs = $installedPrograms

    extensions_schema = [ordered]@{
        name        = "string - tool or package name"
        version     = "string - semver or tag"
        added_at    = "string - ISO 8601 timestamp"
        description = "string - what this extension does"
    }
    extensions = @($mergedExtensions)
}

try {
    $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath -Encoding utf8
    Write-Host " done" -ForegroundColor Green
    Write-Host ""
    Write-Host "Written to: $outputPath" -ForegroundColor Green
} catch {
    Write-Host " failed" -ForegroundColor Red
    Write-Error "Could not write output file: $($_.Exception.Message)"
}

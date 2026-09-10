# ============================================================
# DiskReport.ps1 - Version 1.6.3
# Raw data report + optional HTML + stage log
# ============================================================

$ErrorActionPreference = "Stop"
$Version = "1.6.3"
$ScriptStartTime = Get-Date

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ===== Paths =====
$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
$IniPath      = Join-Path $ScriptDir "DiskReport.ini"
$HistoryPath  = Join-Path $ScriptDir "DiskReports_History.csv"
$StageLogPath = Join-Path $ScriptDir "DiskReport_Log.csv"

# ===== Helpers =====
function Get-IniValue {
    param([string]$Path, [string]$Section, [string]$Key, [string]$Default)
    if (-not (Test-Path $Path)) { return $Default }
    $inSection = $false
    foreach ($line in (Get-Content $Path -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $line = $line.Trim()
        if ($line -match '^\[(.+)\]$') { $inSection = ($matches[1] -eq $Section); continue }
        if ($inSection -and $line -match "^$Key\s*=\s*(.*)$") { return $matches[1].Trim() }
    }
    return $Default
}

function Write-Stage {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    $color = switch ($Level) {
        "START" { "Cyan" }
        "OK"    { "Green" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
        default { "White" }
    }
    if ($script:ProgressMode -eq "fun") {
        Write-Host "[$ts] >> $Message" -ForegroundColor $color
    } else {
        Write-Host "[$ts] $Message" -ForegroundColor $color
    }
}

function Add-StageLog {
    param([string]$StageName, [string]$Status, [double]$DurationSec, [string]$Details = "")
    $script:StageLogEntries += [PSCustomObject]@{
        Timestamp      = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        ComputerNumber = $script:ComputerNumber
        UserNameInput  = $script:UserNameInput
        StageName      = $StageName
        Status         = $Status
        DurationSec    = $DurationSec
        Details        = $Details
        ComputerName   = $env:COMPUTERNAME
        UserName       = $env:USERNAME
    }
}

# ===== Default INI =====
if (-not (Test-Path $IniPath)) {
@"
[General]
EmailTo=rahimi_e@tel-aviv.gov.il
SubjectPrefix=Maintenance - Cleanup -
CompanyName=Tel Aviv Municipality

[Thresholds]
LowPercent=15
WarningPercent=30
MinFreeGB=10
CriticalFreeGB=5

[Display]
ProgressMode=formal
ShowHtmlReport=0

[Network]
EnableNetworkCheck=1
"@ | Out-File -FilePath $IniPath -Encoding UTF8
}

# ===== Load settings =====
$EmailTo            = Get-IniValue $IniPath "General" "EmailTo" "rahimi_e@tel-aviv.gov.il"
$SubjectPrefix      = Get-IniValue $IniPath "General" "SubjectPrefix" "Maintenance - Cleanup -"
$CompanyName        = Get-IniValue $IniPath "General" "CompanyName" "Tel Aviv Municipality"
$LowPercent         = [int](Get-IniValue $IniPath "Thresholds" "LowPercent" "15")
$WarningPercent     = [int](Get-IniValue $IniPath "Thresholds" "WarningPercent" "30")
$MinFreeGB          = [double](Get-IniValue $IniPath "Thresholds" "MinFreeGB" "10")
$CriticalFreeGB     = [double](Get-IniValue $IniPath "Thresholds" "CriticalFreeGB" "5")
$ProgressMode       = (Get-IniValue $IniPath "Display" "ProgressMode" "formal").ToLower()
$ShowHtmlReportRaw = (Get-IniValue $IniPath "Display" "ShowHtmlReport" "0").Trim()
$ShowHtmlReport     = ($ShowHtmlReportRaw -eq "1")
$EnableNetworkCheck = (Get-IniValue $IniPath "Network" "EnableNetworkCheck" "1") -eq "1"

# DEBUG: show loaded value
Write-Host "[DEBUG] ShowHtmlReport raw value from INI: '$ShowHtmlReportRaw' -> Will open HTML: $ShowHtmlReport" -ForegroundColor Magenta

$script:ProgressMode   = $ProgressMode
$script:StageLogEntries = @()

# ===== Header =====
Clear-Host
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "       Disk Report  v$Version" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ===== STAGE: Input =====
$StageStart = Get-Date
Write-Stage "Starting input collection..." "START"

$ComputerNumber = Read-Host "Computer Number"
$ClientName     = Read-Host "Client Name"
$UserNameInput  = Read-Host "User Name"
$UserEmail      = Read-Host "User Email"

if ([string]::IsNullOrWhiteSpace($ComputerNumber)) { $ComputerNumber = "N/A" }
if ([string]::IsNullOrWhiteSpace($ClientName))     { $ClientName = "N/A" }
if ([string]::IsNullOrWhiteSpace($UserNameInput))  { $UserNameInput = "N/A" }
if ([string]::IsNullOrWhiteSpace($UserEmail))      { $UserEmail = "N/A" }

$script:ComputerNumber = $ComputerNumber
$script:UserNameInput  = $UserNameInput

$InputDuration = [math]::Round(((Get-Date) - $StageStart).TotalSeconds, 2)
Write-Stage "Input completed ($InputDuration s)" "OK"
Add-StageLog -StageName "Input" -Status "OK" -DurationSec $InputDuration -Details "ComputerNumber=$ComputerNumber; UserName=$UserNameInput"

# ===== STAGE: System Info =====
$StageStart = Get-Date
Write-Stage "Collecting system information..." "START"

$ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
$BiosInfo       = Get-CimInstance -ClassName Win32_BIOS
$OsInfo         = Get-CimInstance -ClassName Win32_OperatingSystem
$Processor      = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1

$ComputerName  = $env:COMPUTERNAME
$UserName      = $env:USERNAME
$Manufacturer  = $ComputerSystem.Manufacturer
$Model         = $ComputerSystem.Model
$SerialNumber  = $BiosInfo.SerialNumber
$BiosVersion   = $BiosInfo.SMBIOSBIOSVersion
$OsName        = $OsInfo.Caption
$OsVersion     = $OsInfo.Version
$Domain        = $ComputerSystem.Domain

$LastBoot   = $OsInfo.LastBootUpTime
$UptimeSpan = (Get-Date) - $LastBoot
$UptimeText = "{0}d {1}h {2}m" -f $UptimeSpan.Days, $UptimeSpan.Hours, $UptimeSpan.Minutes

$CpuName     = $Processor.Name
$CpuCores    = $Processor.NumberOfCores
$CpuLogical  = $Processor.NumberOfLogicalProcessors
$CpuMaxClock = $Processor.MaxClockSpeed

$TotalRAMGB = [math]::Round($OsInfo.TotalVisibleMemorySize / 1MB, 2)
$FreeRAMGB  = [math]::Round($OsInfo.FreePhysicalMemory / 1MB, 2)
$UsedRAMGB  = [math]::Round($TotalRAMGB - $FreeRAMGB, 2)

$CurrentTime  = Get-Date -Format "dd/MM/yyyy HH:mm"
$SortableTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$SystemDuration = [math]::Round(((Get-Date) - $StageStart).TotalSeconds, 2)
Write-Stage "System information collected ($SystemDuration s)" "OK"
Add-StageLog -StageName "SystemInfo" -Status "OK" -DurationSec $SystemDuration -Details "CPU=$CpuName; RAM=${TotalRAMGB}GB; Uptime=$UptimeText"

# ===== STAGE: Storage =====
$StageStart = Get-Date
Write-Stage "Processing storage devices..." "START"

$DiskList = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $TotalGB     = [math]::Round($_.Size / 1GB, 2)
    $FreeGB      = [math]::Round($_.FreeSpace / 1GB, 2)
    $UsedGB      = [math]::Round(($_.Size - $_.FreeSpace) / 1GB, 2)
    $PercentFree = if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }

    $Level = "ok"
    if ($PercentFree -lt $LowPercent -or $FreeGB -lt $CriticalFreeGB) { $Level = "critical" }
    elseif ($PercentFree -lt $WarningPercent -or $FreeGB -lt $MinFreeGB) { $Level = "warning" }

    [PSCustomObject]@{
        Drive = $_.DeviceID
        Label = $(if ($_.VolumeName) { $_.VolumeName } else { "-" })
        TotalGB = $TotalGB; FreeGB = $FreeGB; UsedGB = $UsedGB
        PercentFree = $PercentFree; FileSystem = $_.FileSystem; Level = $Level
    }
})

$DiskTypeInfo = "N/A"
try {
    $PhysicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
    if ($PhysicalDisks) {
        $DiskTypeInfo = ($PhysicalDisks | ForEach-Object { $_.MediaType }) -join " | "
    }
} catch { $DiskTypeInfo = "Unavailable" }

$DiskRowsHtml = ""
$IssuesList = New-Object System.Collections.Generic.List[string]
$DiskDetailsList = New-Object System.Collections.Generic.List[string]
$HasCritical = $false; $HasWarning = $false

foreach ($Disk in $DiskList) {
    $rowClass = switch ($Disk.Level) { "critical" {"crit"} "warning" {"warn"} default {"ok"} }
    $DiskRowsHtml += "<tr class='$rowClass'><td>$($Disk.Drive)</td><td>$($Disk.Label)</td><td>$($Disk.TotalGB)</td><td>$($Disk.UsedGB)</td><td>$($Disk.FreeGB)</td><td>$($Disk.PercentFree)</td><td>$($Disk.FileSystem)</td><td>$($Disk.Level)</td></tr>"
    $DiskDetailsList.Add("$($Disk.Drive) [$($Disk.Label)] Total:$($Disk.TotalGB)GB Free:$($Disk.FreeGB)GB ($($Disk.PercentFree)%) Level:$($Disk.Level)") | Out-Null

    if ($Disk.Level -eq "critical") {
        $IssuesList.Add("Drive $($Disk.Drive) - CRITICAL free space: $($Disk.FreeGB) GB ($($Disk.PercentFree)%)") | Out-Null
        $HasCritical = $true
    } elseif ($Disk.Level -eq "warning") {
        $IssuesList.Add("Drive $($Disk.Drive) - Low free space: $($Disk.FreeGB) GB ($($Disk.PercentFree)%)") | Out-Null
        $HasWarning = $true
    }
}

$DisksDetailsText = $DiskDetailsList -join " || "
$OverallStatus = if ($HasCritical) { "Critical" } elseif ($HasWarning) { "Warning" } else { "OK" }
$IssuesText = if ($IssuesList.Count -gt 0) { $IssuesList -join " ; " } else { "None" }

$DiskDuration = [math]::Round(((Get-Date) - $StageStart).TotalSeconds, 2)
Write-Stage "Storage processing completed ($DiskDuration s)" "OK"
Add-StageLog -StageName "Storage" -Status "OK" -DurationSec $DiskDuration -Details "Drives=$($DiskList.Count); Status=$OverallStatus"

# ===== STAGE: Network =====
$StageStart = Get-Date
Write-Stage "Collecting network information..." "START"

$NetworkInfoText = "N/A"
$LocalIP = "N/A"; $Mac = "N/A"; $Gateway = "N/A"; $DNS = "N/A"
$ConnectivityResults = "Disabled"

try {
    $Adapters = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4Address -and $_.NetAdapter.Status -eq "Up" }
    if ($Adapters) {
        $Primary = $Adapters | Select-Object -First 1
        $LocalIP = $Primary.IPv4Address.IPAddress
        $Gateway = if ($Primary.IPv4DefaultGateway) { $Primary.IPv4DefaultGateway.NextHop } else { "N/A" }
        $DNS     = if ($Primary.DNSServer) { ($Primary.DNSServer.ServerAddresses -join ", ") } else { "N/A" }
        $Mac     = (Get-NetAdapter -InterfaceIndex $Primary.InterfaceIndex -ErrorAction SilentlyContinue).MacAddress
        $NetworkInfoText = "IP:$LocalIP | MAC:$Mac | GW:$Gateway | DNS:$DNS"
    }
} catch { $NetworkInfoText = "Unavailable" }

if ($EnableNetworkCheck) {
    $PingResults = @()
    foreach ($Target in @("8.8.8.8", "1.1.1.1")) {
        $ok = Test-Connection -ComputerName $Target -Count 1 -Quiet -ErrorAction SilentlyContinue
        $PingResults += if ($ok) { "$Target : OK" } else { "$Target : FAILED" }
    }
    $ConnectivityResults = $PingResults -join " | "
}

$NetworkDuration = [math]::Round(((Get-Date) - $StageStart).TotalSeconds, 2)
Write-Stage "Network information collected ($NetworkDuration s)" "OK"
Add-StageLog -StageName "Network" -Status "OK" -DurationSec $NetworkDuration -Details $ConnectivityResults

# ===== Final timing =====
$ScriptEndTime = Get-Date
$TotalDuration = [math]::Round(($ScriptEndTime - $ScriptStartTime).TotalSeconds, 2)
$StartTimeStr  = $ScriptStartTime.ToString("yyyy-MM-dd HH:mm:ss")
$EndTimeStr    = $ScriptEndTime.ToString("yyyy-MM-dd HH:mm:ss")

Write-Stage "Finalizing report..." "START"
Add-StageLog -StageName "Finalize" -Status "OK" -DurationSec 0 -Details "TotalDuration=$TotalDuration"

# ===== Save Stage Log =====
try {
    $logHeader = "Timestamp,ComputerNumber,UserNameInput,StageName,Status,DurationSec,Details,ComputerName,UserName"
    $needHeader = $true
    if (Test-Path $StageLogPath) {
        $first = Get-Content $StageLogPath -TotalCount 1 -ErrorAction SilentlyContinue
        if ($first -like "*Timestamp*") { $needHeader = $false }
    }
    if ($needHeader) { $logHeader | Out-File -FilePath $StageLogPath -Encoding UTF8 }

    foreach ($entry in $script:StageLogEntries) {
        $line = "`"$($entry.Timestamp)`",`"$($entry.ComputerNumber)`",`"$($entry.UserNameInput)`",`"$($entry.StageName)`",`"$($entry.Status)`",`"$($entry.DurationSec)`",`"$($entry.Details)`",`"$($entry.ComputerName)`",`"$($entry.UserName)`""
        $line | Out-File -FilePath $StageLogPath -Encoding UTF8 -Append
    }
} catch { Write-Stage "Stage log write failed" "WARN" }

# ===== Save History CSV (with lock + retry for parallel runs) =====
function Save-HistoryLine {
    param([string]$Path, [string]$Header, [string]$Line)
    $encoding = New-Object System.Text.UTF8Encoding $false
    $maxAttempts = 8
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            $dir = Split-Path -Parent $Path
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

            $needHeader = -not (Test-Path $Path)
            if (-not $needHeader) {
                $fsCheck = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                try {
                    $reader = New-Object System.IO.StreamReader($fsCheck, $true)
                    $first = $reader.ReadLine()
                    $reader.Dispose()
                    if (-not $first -or $first -notlike "*Timestamp*") { $needHeader = $true }
                } finally { $fsCheck.Dispose() }
            }

            $mode = if (Test-Path $Path) { [System.IO.FileMode]::Append } else { [System.IO.FileMode]::Create }
            $fs = [System.IO.File]::Open($Path, $mode, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try {
                $writer = New-Object System.IO.StreamWriter($fs, $encoding)
                if ($needHeader -and $mode -eq [System.IO.FileMode]::Create) {
                    $writer.WriteLine($Header)
                } elseif ($needHeader -and $mode -eq [System.IO.FileMode]::Append) {
                    # file exists but header missing - still append header then line
                    $writer.WriteLine($Header)
                }
                $writer.WriteLine($Line)
                $writer.Flush()
                $writer.Dispose()
            } finally { $fs.Dispose() }
            return $true
        } catch {
            Start-Sleep -Milliseconds (120 * $attempt)
        }
    }
    return $false
}

try {
    $CsvHeader = "Timestamp,ComputerNumber,ClientName,UserNameInput,UserEmail,ComputerName,UserName,Manufacturer,Model,SerialNumber,BiosVersion,OSName,OSVersion,Domain,Uptime,CpuName,CpuCores,CpuLogical,TotalRAMGB,FreeRAMGB,OverallStatus,Issues,DisksDetails,DiskTypeInfo,NetworkInfo,Connectivity,StartTime,EndTime,TotalDurationSec"
    # Escape quotes inside fields for safe CSV
    function CsvEsc([string]$v) { if ($null -eq $v) { return "" }; return ($v -replace '"', '""') }
    $CsvLine = "`"$(CsvEsc $SortableTime)`",`"$(CsvEsc $ComputerNumber)`",`"$(CsvEsc $ClientName)`",`"$(CsvEsc $UserNameInput)`",`"$(CsvEsc $UserEmail)`",`"$(CsvEsc $ComputerName)`",`"$(CsvEsc $UserName)`",`"$(CsvEsc $Manufacturer)`",`"$(CsvEsc $Model)`",`"$(CsvEsc $SerialNumber)`",`"$(CsvEsc $BiosVersion)`",`"$(CsvEsc $OsName)`",`"$(CsvEsc $OsVersion)`",`"$(CsvEsc $Domain)`",`"$(CsvEsc $UptimeText)`",`"$(CsvEsc $CpuName)`",`"$(CsvEsc $CpuCores)`",`"$(CsvEsc $CpuLogical)`",`"$(CsvEsc $TotalRAMGB)`",`"$(CsvEsc $FreeRAMGB)`",`"$(CsvEsc $OverallStatus)`",`"$(CsvEsc $IssuesText)`",`"$(CsvEsc $DisksDetailsText)`",`"$(CsvEsc $DiskTypeInfo)`",`"$(CsvEsc $NetworkInfoText)`",`"$(CsvEsc $ConnectivityResults)`",`"$(CsvEsc $StartTimeStr)`",`"$(CsvEsc $EndTimeStr)`",`"$(CsvEsc $TotalDuration)`""

    $saved = Save-HistoryLine -Path $HistoryPath -Header $CsvHeader -Line $CsvLine
    if ($saved) {
        Write-Stage "History saved OK" "OK"
        Write-Host "History file: $HistoryPath" -ForegroundColor Cyan
        if (Test-Path $HistoryPath) {
            $lines = @(Get-Content $HistoryPath -ErrorAction SilentlyContinue).Count
            Write-Host "History lines now: $lines" -ForegroundColor DarkGray
        }
    } else {
        Write-Stage "History save FAILED after retries" "ERROR"
        Write-Host "Could not write: $HistoryPath" -ForegroundColor Red
    }
} catch {
    Write-Stage "History save failed: $($_.Exception.Message)" "ERROR"
}

# ===== Optional Raw HTML Report =====
if ($ShowHtmlReport) {
    Write-Stage "Building HTML report..." "START"

    $IssuesRows = ""
    if ($IssuesList.Count -gt 0) {
        foreach ($iss in $IssuesList) { $IssuesRows += "<tr><td>$iss</td></tr>" }
    } else {
        $IssuesRows = "<tr><td>None</td></tr>"
    }

    $Html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Disk Report - Raw Data</title>
<style>
body { font-family: Consolas, monospace; font-size: 13px; margin: 20px; background: #f5f5f5; color: #222; }
h1 { font-size: 18px; margin-bottom: 4px; }
h2 { font-size: 15px; margin-top: 22px; margin-bottom: 8px; border-bottom: 1px solid #999; padding-bottom: 3px; }
table { border-collapse: collapse; width: 100%; margin-bottom: 12px; background: #fff; }
th, td { border: 1px solid #ccc; padding: 5px 8px; text-align: left; }
th { background: #e0e0e0; }
tr.crit { background: #ffd6d6; }
tr.warn { background: #fff3cd; }
tr.ok   { background: #e6ffed; }
.summary { background: #fff; border: 1px solid #ccc; padding: 10px; margin-bottom: 15px; }
.summary div { margin: 3px 0; }
.label { color: #555; display: inline-block; width: 140px; }
</style>
</head>
<body>
<h1>System & Storage Report (Raw)</h1>
<div>Generated: $CurrentTime | Version: $Version | Duration: $TotalDuration s</div>

<h2>Summary</h2>
<div class="summary">
  <div><span class="label">Overall Status:</span> <strong>$OverallStatus</strong></div>
  <div><span class="label">Computer Number:</span> $ComputerNumber</div>
  <div><span class="label">Client Name:</span> $ClientName</div>
  <div><span class="label">User Name:</span> $UserNameInput</div>
  <div><span class="label">User Email:</span> $UserEmail</div>
  <div><span class="label">Start / End:</span> $StartTimeStr → $EndTimeStr</div>
</div>

<h2>Computer</h2>
<table>
<tr><th>Field</th><th>Value</th></tr>
<tr><td>Computer Name</td><td>$ComputerName</td></tr>
<tr><td>Logged User</td><td>$UserName</td></tr>
<tr><td>Manufacturer</td><td>$Manufacturer</td></tr>
<tr><td>Model</td><td>$Model</td></tr>
<tr><td>Serial Number</td><td>$SerialNumber</td></tr>
<tr><td>BIOS</td><td>$BiosVersion</td></tr>
<tr><td>OS</td><td>$OsName ($OsVersion)</td></tr>
<tr><td>Domain</td><td>$Domain</td></tr>
<tr><td>Uptime</td><td>$UptimeText</td></tr>
</table>

<h2>CPU & Memory</h2>
<table>
<tr><th>Field</th><th>Value</th></tr>
<tr><td>CPU</td><td>$CpuName</td></tr>
<tr><td>Cores / Logical</td><td>$CpuCores / $CpuLogical</td></tr>
<tr><td>Max Clock</td><td>$CpuMaxClock MHz</td></tr>
<tr><td>Total RAM</td><td>$TotalRAMGB GB</td></tr>
<tr><td>Used RAM</td><td>$UsedRAMGB GB</td></tr>
<tr><td>Free RAM</td><td>$FreeRAMGB GB</td></tr>
</table>

<h2>Storage</h2>
<div>Media Type: $DiskTypeInfo</div>
<table>
<tr><th>Drive</th><th>Label</th><th>Total (GB)</th><th>Used (GB)</th><th>Free (GB)</th><th>% Free</th><th>FS</th><th>Level</th></tr>
$DiskRowsHtml
</table>

<h2>Issues</h2>
<table>
<tr><th>Description</th></tr>
$IssuesRows
</table>

<h2>Network</h2>
<table>
<tr><th>Field</th><th>Value</th></tr>
<tr><td>Local IP</td><td>$LocalIP</td></tr>
<tr><td>MAC</td><td>$Mac</td></tr>
<tr><td>Gateway</td><td>$Gateway</td></tr>
<tr><td>DNS</td><td>$DNS</td></tr>
<tr><td>Connectivity</td><td>$ConnectivityResults</td></tr>
</table>

<h2>Stage Timings</h2>
<table>
<tr><th>Stage</th><th>Seconds</th></tr>
<tr><td>Input</td><td>$InputDuration</td></tr>
<tr><td>System</td><td>$SystemDuration</td></tr>
<tr><td>Storage</td><td>$DiskDuration</td></tr>
<tr><td>Network</td><td>$NetworkDuration</td></tr>
<tr><td>Total</td><td>$TotalDuration</td></tr>
</table>

<div style="margin-top:20px;color:#666;font-size:12px;">
$CompanyName | Target mail: $EmailTo | v$Version
</div>
</body>
</html>
"@

    $HtmlFile = Join-Path $ScriptDir ("DiskReport_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".html")
    $Html | Out-File -FilePath $HtmlFile -Encoding utf8
    Start-Process $HtmlFile
    Write-Stage "HTML report created and opened" "OK"
} else {
    Write-Stage "HTML report skipped (ShowHtmlReport=0)" "OK"
}

Write-Host ""
Write-Host "Done. Total time: $TotalDuration seconds" -ForegroundColor Green
Write-Host "Version: $Version" -ForegroundColor DarkGray
Write-Host ""
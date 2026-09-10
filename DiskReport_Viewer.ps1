# ============================================================
# DiskReport_Viewer.ps1 - Version 1.5.0
# Fixed HTML/JS, theme, critical queue by free vs 4x RAM
# ============================================================

$ErrorActionPreference = "Stop"
$Version = "1.5.0"

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
$HistoryPath = Join-Path $ScriptDir "DiskReports_History.csv"
$OutHtml = Join-Path $ScriptDir "DiskReport_Analysis.html"

Clear-Host
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   Disk Report Viewer  v$Version" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $HistoryPath)) {
    Write-Host "ERROR: History file not found:" -ForegroundColor Red
    Write-Host "  $HistoryPath" -ForegroundColor Yellow
    exit 1
}

# ---- Load CSV (BOM safe) ----
try {
    $lines = Get-Content -Path $HistoryPath -Encoding UTF8
    if ($lines.Count -eq 0) { throw "Empty file" }
    if ($lines[0].Length -gt 0 -and [int][char]$lines[0][0] -eq 0xFEFF) {
        $lines[0] = $lines[0].Substring(1)
    }
    $tmp = Join-Path $env:TEMP ("dr_view_" + [guid]::NewGuid().ToString() + ".csv")
    $lines | Set-Content -Path $tmp -Encoding UTF8
    $Data = @(Import-Csv -Path $tmp)
    Remove-Item $tmp -ErrorAction SilentlyContinue
} catch {
    Write-Host "ERROR: Cannot read history file." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

if ($Data.Count -eq 0) {
    Write-Host "History file is empty." -ForegroundColor Yellow
    exit 0
}

Write-Host "Loaded $($Data.Count) records from:" -ForegroundColor Green
Write-Host "  $HistoryPath" -ForegroundColor DarkGray

# Date range
$parsedDates = @()
foreach ($r in $Data) {
    try { $parsedDates += [datetime]::Parse($r.Timestamp) } catch {}
}
if ($parsedDates.Count -gt 0) {
    $sortedDates = $parsedDates | Sort-Object
    $DateRangeText = $sortedDates[0].ToString("yyyy-MM-dd") + " -> " + $sortedDates[-1].ToString("yyyy-MM-dd")
} else {
    $DateRangeText = "N/A"
}

function Get-SystemFreeGB([string]$DisksDetails) {
    if ([string]::IsNullOrWhiteSpace($DisksDetails)) { return $null }
    if ($DisksDetails -match 'C:\s*\[[^\]]*\][^|]*Free:([0-9\.]+)GB') { return [double]$Matches[1] }
    if ($DisksDetails -match 'Free:([0-9\.]+)GB') { return [double]$Matches[1] }
    return $null
}

function Get-RamGB($row) {
    $v = 0.0
    if ([double]::TryParse([string]$row.TotalRAMGB, [ref]$v)) { return $v }
    return 0.0
}

# ---- Latest record per computer ----
$latestByComputer = @{}
foreach ($r in ($Data | Sort-Object Timestamp)) {
    $key = [string]$r.ComputerName
    if ([string]::IsNullOrWhiteSpace($key)) { $key = [string]$r.ComputerNumber }
    if ([string]::IsNullOrWhiteSpace($key)) { continue }
    $latestByComputer[$key] = $r
}

# ---- Critical queue: free should be >= 4 * RAM ----
# Severity score: higher = more urgent
# requiredFree = RAM * 4
# If free >= required => score 0 (OK for this rule)
# Else score rises as free drops toward 0
$CriticalQueue = @()
foreach ($key in $latestByComputer.Keys) {
    $r = $latestByComputer[$key]
    $ram = Get-RamGB $r
    $free = Get-SystemFreeGB $r.DisksDetails
    if ($null -eq $free) { continue }

    $required = [math]::Round($ram * 4.0, 2)
    $ratio = if ($required -gt 0) { [math]::Round($free / $required, 3) } else { 1 }

    # Severity tiers by free vs required and absolute free
    if ($free -le 0) {
        $tier = 5; $tierName = "EMPTY"
    } elseif ($free -lt 5) {
        $tier = 4; $tierName = "CRITICAL-LOW"
    } elseif ($required -gt 0 -and $free < ($required * 0.25)) {
        $tier = 3; $tierName = "SEVERE"
    } elseif ($required -gt 0 -and $free < ($required * 0.5)) {
        $tier = 2; $tierName = "HIGH"
    } elseif ($required -gt 0 -and $free < $required) {
        $tier = 1; $tierName = "WATCH"
    } else {
        $tier = 0; $tierName = "OK"
    }

    # Sort key: tier desc, then free asc (lower free first), then ratio asc
    $CriticalQueue += [PSCustomObject]@{
        ComputerNumber = $r.ComputerNumber
        ComputerName   = $r.ComputerName
        ClientName     = $r.ClientName
        Status         = $r.OverallStatus
        RamGB          = $ram
        FreeGB         = [math]::Round($free, 2)
        RequiredGB     = $required
        Ratio          = $ratio
        Tier           = $tier
        TierName       = $tierName
        Timestamp      = $r.Timestamp
    }
}

$CriticalQueue = @($CriticalQueue | Where-Object { $_.Tier -gt 0 } | Sort-Object @{Expression="Tier";Descending=$true}, @{Expression="FreeGB";Ascending=$true})

# Counts from latest snapshot optional; keep overall counts too
$TotalRecords  = $Data.Count
$CriticalCount = @($Data | Where-Object { $_.OverallStatus -eq "Critical" }).Count
$WarningCount  = @($Data | Where-Object { $_.OverallStatus -eq "Warning" }).Count
$OkCount       = @($Data | Where-Object { $_.OverallStatus -eq "OK" }).Count
$QueueCount    = $CriticalQueue.Count

# Filter option lists
function OptList($arr) {
    $vals = $arr | Where-Object { $_ -and $_.ToString().Trim() -ne "" -and $_.ToString().Trim() -ne "N/A" } |
        ForEach-Object { $_.ToString().Trim() } | Sort-Object -Unique
    return ($vals | ForEach-Object { "<option value=`"$([System.Web.HttpUtility]::HtmlEncode($_))`">$([System.Web.HttpUtility]::HtmlEncode($_))</option>" }) -join "`n"
}

# HtmlEncode may need assembly
try { Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue } catch {}
function H([string]$s) {
    if ($null -eq $s) { return "" }
    return ($s -replace "&", "&amp;" -replace "<", "&lt;" -replace ">", "&gt;" -replace '"', "&quot;")
}
function OptListSimple($arr) {
    $vals = $arr | Where-Object { $_ -and $_.ToString().Trim() -ne "" -and $_.ToString().Trim() -ne "N/A" } |
        ForEach-Object { $_.ToString().Trim() } | Sort-Object -Unique
    return ($vals | ForEach-Object { "<option value=`"$(H $_)`">$(H $_)</option>" }) -join "`n"
}

$OptComp   = OptListSimple ($Data | ForEach-Object { $_.ComputerNumber })
$OptClient = OptListSimple ($Data | ForEach-Object { $_.ClientName })
$OptUser   = OptListSimple ($Data | ForEach-Object { $_.UserNameInput })
$OptCName  = OptListSimple ($Data | ForEach-Object { $_.ComputerName })

# Top users
$TopUsers = $Data | Where-Object { $_.UserNameInput -and $_.UserNameInput -ne "N/A" } |
    Group-Object UserNameInput | Sort-Object Count -Descending | Select-Object -First 8
$UsersHtml = if ($TopUsers) {
    ($TopUsers | ForEach-Object { "<tr><td>$(H $_.Name)</td><td><strong>$($_.Count)</strong></td></tr>" }) -join "`n"
} else { "<tr><td colspan='2'>No data</td></tr>" }

# Critical queue HTML
$QueueHtml = if ($CriticalQueue.Count -gt 0) {
    ($CriticalQueue | ForEach-Object {
        $cls = switch ($_.Tier) { 5 {"t5"} 4 {"t4"} 3 {"t3"} 2 {"t2"} default {"t1"} }
        "<tr class='$cls'><td>$($_.TierName)</td><td>$(H $_.ComputerNumber)</td><td>$(H $_.ComputerName)</td><td>$(H $_.ClientName)</td><td>$($_.RamGB)</td><td>$($_.FreeGB)</td><td>$($_.RequiredGB)</td><td>$($_.Ratio)</td><td>$(H $_.Status)</td><td>$(H $_.Timestamp)</td></tr>"
    }) -join "`n"
} else { "<tr><td colspan='10'>No computers below free-space rule (Free &gt;= 4 x RAM)</td></tr>" }

# Build records JSON via file to avoid here-string breakage
$JsObjects = @(foreach ($row in $Data) {
    [PSCustomObject]@{
        ts     = [string]$row.Timestamp
        comp   = [string]$row.ComputerNumber
        client = [string]$row.ClientName
        user   = [string]$row.UserNameInput
        cname  = [string]$row.ComputerName
        status = [string]$row.OverallStatus
        ram    = [string]$row.TotalRAMGB
        dur    = [string]$row.TotalDurationSec
        issues = [string]$row.Issues
    }
})
$jsonPath = Join-Path $env:TEMP ("dr_data_" + [guid]::NewGuid().ToString() + ".json")
$JsObjects | ConvertTo-Json -Depth 4 -Compress | Set-Content -Path $jsonPath -Encoding UTF8
$JsData = Get-Content -Path $jsonPath -Raw -Encoding UTF8
Remove-Item $jsonPath -ErrorAction SilentlyContinue
if ([string]::IsNullOrWhiteSpace($JsData)) { $JsData = "[]" }
$JsData = $JsData.Trim()
if ($JsData -notmatch '^\s*\[') { $JsData = "[$JsData]" }

# Base64 embed - bulletproof against quotes/$ in HTML
$JsDataB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($JsData))

$GeneratedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$Html = @"
<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Disk Report Insights v$Version</title>
<style>
:root, [data-theme="dark"] {
  --bg:#0b1220; --card:#111827; --border:#1f2a3a; --text:#e5eef7; --muted:#8b9bb0;
  --accent:#3b82f6; --critical:#ef4444; --warning:#f59e0b; --ok:#22c55e; --input:#0f172a;
}
[data-theme="light"] {
  --bg:#f3f6fb; --card:#ffffff; --border:#dbe3ef; --text:#0f172a; --muted:#64748b;
  --accent:#2563eb; --critical:#dc2626; --warning:#d97706; --ok:#16a34a; --input:#f8fafc;
}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',system-ui,sans-serif;background:var(--bg);color:var(--text);min-height:100vh;padding:24px 16px 48px}
.container{max-width:1280px;margin:0 auto}
header{display:flex;justify-content:space-between;gap:12px;align-items:flex-start;margin-bottom:18px;flex-wrap:wrap}
header h1{font-size:26px;font-weight:700}
header p{color:var(--muted);font-size:13px;margin-top:5px}
.theme-btn{border:1px solid var(--border);background:var(--card);color:var(--text);border-radius:999px;padding:8px 14px;cursor:pointer;font-size:12px;font-weight:600}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px;margin-bottom:14px}
.card{background:var(--card);border:1px solid var(--border);border-radius:14px;padding:14px 16px;position:relative;overflow:hidden}
.card::before{content:'';position:absolute;top:0;left:0;right:0;height:3px}
.card.total::before{background:var(--accent)} .card.critical::before{background:var(--critical)}
.card.warning::before{background:var(--warning)} .card.ok::before{background:var(--ok)}
.card .label{font-size:11px;text-transform:uppercase;letter-spacing:.55px;color:var(--muted);margin-bottom:6px}
.card .value{font-size:28px;font-weight:700}
.panel{background:var(--card);border:1px solid var(--border);border-radius:14px;overflow:hidden;margin-bottom:14px}
.panel-header{padding:12px 14px;border-bottom:1px solid var(--border);display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap}
.panel-header h2{font-size:14px}
.note{color:var(--muted);font-size:12px;padding:8px 14px}
.filters{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:10px;padding:12px 14px;border-bottom:1px solid var(--border)}
.field label{display:block;font-size:11px;color:var(--muted);margin-bottom:5px;text-transform:uppercase}
.field input,.field select{width:100%;background:var(--input);border:1px solid var(--border);color:var(--text);border-radius:10px;padding:9px 10px;font-size:13px}
.btn{border:none;border-radius:10px;padding:9px 12px;font-size:12px;font-weight:600;cursor:pointer}
.btn-primary{background:var(--accent);color:#fff}
.btn-secondary{background:transparent;color:var(--muted);border:1px solid var(--border)}
.table-wrap{overflow:auto;max-height:480px}
table{width:100%;border-collapse:collapse;font-size:12.5px}
th{text-align:left;padding:10px;background:var(--input);color:var(--muted);font-size:11px;text-transform:uppercase;position:sticky;top:0}
td{padding:9px 10px;border-top:1px solid var(--border);vertical-align:top}
tr:hover td{background:rgba(59,130,246,.06)}
tr.t5 td{background:rgba(239,68,68,.25)} tr.t4 td{background:rgba(239,68,68,.16)}
tr.t3 td{background:rgba(245,158,11,.16)} tr.t2 td{background:rgba(245,158,11,.10)} tr.t1 td{background:rgba(59,130,246,.08)}
.badge{display:inline-block;padding:3px 9px;border-radius:999px;font-size:11px;font-weight:600}
.status-critical{background:rgba(239,68,68,.15);color:#fca5a5}
.status-warning{background:rgba(245,158,11,.15);color:#fcd34d}
.status-ok{background:rgba(34,197,94,.15);color:#86efac}
[data-theme="light"] .status-critical{color:#b91c1c}
[data-theme="light"] .status-warning{color:#b45309}
[data-theme="light"] .status-ok{color:#15803d}
.issues{max-width:240px;color:var(--muted);font-size:12px}
footer{margin-top:10px;text-align:center;color:var(--muted);font-size:12px}
.grid-2{display:grid;grid-template-columns:1fr 1fr;gap:14px}
@media (max-width:900px){.grid-2{grid-template-columns:1fr}}
</style>
</head>
<body>
<div class="container">
  <header>
    <div>
      <h1>Disk Report Insights</h1>
      <p>Viewer v$Version · Data range: $DateRangeText · Generated: $GeneratedAt</p>
      <p style="margin-top:4px">Rule: Free disk space should be at least <strong>4 x RAM</strong>. Queue sorted by severity then lowest free space.</p>
    </div>
    <button class="theme-btn" type="button" id="themeBtn">Switch to Light</button>
  </header>

  <div class="cards">
    <div class="card total"><div class="label">Records</div><div class="value" id="cardTotal">$TotalRecords</div></div>
    <div class="card critical"><div class="label">Critical rows</div><div class="value" id="cardCritical">$CriticalCount</div></div>
    <div class="card warning"><div class="label">Warning rows</div><div class="value" id="cardWarning">$WarningCount</div></div>
    <div class="card ok"><div class="label">Treatment queue</div><div class="value">$QueueCount</div></div>
  </div>

  <div class="panel">
    <div class="panel-header"><h2>Critical Treatment Queue (latest state per computer)</h2></div>
    <div class="note">Independent of who ran the tool. Required Free GB = RAM GB x 4. Sorted: EMPTY/CRITICAL-LOW/SEVERE/HIGH/WATCH, then lowest free space first.</div>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Tier</th><th>Comp #</th><th>Computer</th><th>Client</th>
            <th>RAM GB</th><th>Free GB</th><th>Required (4xRAM)</th><th>Ratio</th><th>Status</th><th>Last Check</th>
          </tr>
        </thead>
        <tbody>
          $QueueHtml
        </tbody>
      </table>
    </div>
  </div>

  <div class="grid-2">
    <div class="panel">
      <div class="panel-header"><h2>Top Users (most runs)</h2></div>
      <div class="table-wrap"><table><thead><tr><th>User Name</th><th>Runs</th></tr></thead><tbody>$UsersHtml</tbody></table></div>
    </div>
    <div class="panel">
      <div class="panel-header"><h2>Rule summary</h2></div>
      <div class="note">
        <div>EMPTY: Free &lt;= 0 GB</div>
        <div>CRITICAL-LOW: Free &lt; 5 GB</div>
        <div>SEVERE: Free &lt; 25% of required (4x RAM)</div>
        <div>HIGH: Free &lt; 50% of required</div>
        <div>WATCH: Free &lt; required</div>
        <div>OK: Free &gt;= required (not listed in queue)</div>
      </div>
    </div>
  </div>

  <div class="panel">
    <div class="panel-header">
      <h2>All Records</h2>
      <div style="color:var(--muted);font-size:12px">Showing <span id="shownCount">0</span></div>
    </div>
    <div class="filters">
      <div class="field"><label>Status</label>
        <select id="fStatus"><option value="">All</option><option>Critical</option><option>Warning</option><option>OK</option></select>
      </div>
      <div class="field"><label>Computer #</label><select id="fComp"><option value="">All</option>$OptComp</select></div>
      <div class="field"><label>Client</label><select id="fClient"><option value="">All</option>$OptClient</select></div>
      <div class="field"><label>User Name</label><select id="fUser"><option value="">All</option>$OptUser</select></div>
      <div class="field"><label>Computer Name</label><select id="fCName"><option value="">All</option>$OptCName</select></div>
      <div class="field"><label>From</label><input id="fFrom" type="date"></div>
      <div class="field"><label>To</label><input id="fTo" type="date"></div>
      <div class="field" style="display:flex;gap:8px;align-items:end">
        <button class="btn btn-primary" type="button" id="btnApply">Apply</button>
        <button class="btn btn-secondary" type="button" id="btnReset">Reset</button>
      </div>
    </div>
    <div class="table-wrap" style="max-height:520px">
      <table>
        <thead>
          <tr>
            <th>Timestamp</th><th>Comp #</th><th>Client</th><th>User</th><th>Computer</th>
            <th>Status</th><th>RAM</th><th>Duration</th><th>Issues</th>
          </tr>
        </thead>
        <tbody id="tbody"></tbody>
      </table>
    </div>
  </div>
  <footer>Disk Report Insights · v$Version · Fixed file: DiskReport_Analysis.html</footer>
</div>

<script>
(function(){
  // Theme
  var btn = document.getElementById('themeBtn');
  function setTheme(next){
    document.documentElement.setAttribute('data-theme', next);
    if (btn) btn.textContent = (next === 'dark') ? 'Switch to Light' : 'Switch to Dark';
    try { localStorage.setItem('dr_theme', next); } catch(e) {}
  }
  try {
    var saved = localStorage.getItem('dr_theme') || 'dark';
    setTheme(saved);
  } catch(e) { setTheme('dark'); }
  if (btn) {
    btn.addEventListener('click', function(){
      var cur = document.documentElement.getAttribute('data-theme') || 'dark';
      setTheme(cur === 'dark' ? 'light' : 'dark');
    });
  }

  // Data from base64 (safe)
  var DATA = [];
  try {
    var b64 = "$JsDataB64";
    var json = decodeURIComponent(escape(atob(b64)));
    DATA = JSON.parse(json);
    if (!Array.isArray(DATA)) DATA = [DATA];
  } catch (e) {
    console.error('DATA load failed', e);
    DATA = [];
  }

  function parseDate(ts){
    if(!ts) return null;
    var d = new Date(String(ts).replace(' ', 'T'));
    return isNaN(d.getTime()) ? null : d;
  }
  function badgeClass(s){
    if(s==='Critical') return 'status-critical';
    if(s==='Warning') return 'status-warning';
    return 'status-ok';
  }
  function applyFilters(){
    var status = document.getElementById('fStatus').value;
    var comp = document.getElementById('fComp').value;
    var client = document.getElementById('fClient').value;
    var user = document.getElementById('fUser').value;
    var cname = document.getElementById('fCName').value;
    var fromVal = document.getElementById('fFrom').value;
    var toVal = document.getElementById('fTo').value;
    var fromDate = fromVal ? new Date(fromVal + 'T00:00:00') : null;
    var toDate = toVal ? new Date(toVal + 'T23:59:59') : null;

    var critical=0, warning=0, ok=0, rows=[];
    for (var i=0;i<DATA.length;i++){
      var r = DATA[i];
      if (status && r.status !== status) continue;
      if (comp && r.comp !== comp) continue;
      if (client && r.client !== client) continue;
      if (user && r.user !== user) continue;
      if (cname && r.cname !== cname) continue;
      var d = parseDate(r.ts);
      if (fromDate && d && d < fromDate) continue;
      if (toDate && d && d > toDate) continue;
      rows.push(r);
      if (r.status === 'Critical') critical++;
      else if (r.status === 'Warning') warning++;
      else ok++;
    }
    rows.sort(function(a,b){ return String(b.ts||'').localeCompare(String(a.ts||'')); });

    var tbody = document.getElementById('tbody');
    var html = '';
    for (var j=0;j<rows.length;j++){
      var x = rows[j];
      html += '<tr>' +
        '<td>'+ (x.ts||'') +'</td>' +
        '<td><strong>'+ (x.comp||'') +'</strong></td>' +
        '<td>'+ (x.client||'') +'</td>' +
        '<td>'+ (x.user||'') +'</td>' +
        '<td>'+ (x.cname||'') +'</td>' +
        '<td><span class="badge '+ badgeClass(x.status) +'">'+ (x.status||'') +'</span></td>' +
        '<td>'+ (x.ram||'') +'</td>' +
        '<td>'+ (x.dur ? x.dur + 's' : '') +'</td>' +
        '<td class="issues">'+ (x.issues||'') +'</td>' +
      '</tr>';
    }
    tbody.innerHTML = html;
    document.getElementById('shownCount').textContent = rows.length;
    document.getElementById('cardTotal').textContent = rows.length;
    document.getElementById('cardCritical').textContent = critical;
    document.getElementById('cardWarning').textContent = warning;
  }

  document.getElementById('btnApply').addEventListener('click', applyFilters);
  document.getElementById('btnReset').addEventListener('click', function(){
    ['fStatus','fComp','fClient','fUser','fCName','fFrom','fTo'].forEach(function(id){
      document.getElementById(id).value = '';
    });
    applyFilters();
  });
  ['fStatus','fComp','fClient','fUser','fCName','fFrom','fTo'].forEach(function(id){
    document.getElementById(id).addEventListener('change', applyFilters);
  });

  applyFilters();
})();
</script>
</body>
</html>
"@

$Html | Out-File -FilePath $OutHtml -Encoding utf8
Start-Process $OutHtml

Write-Host ""
Write-Host "Dashboard opened." -ForegroundColor Green
Write-Host "File: $OutHtml" -ForegroundColor Cyan
Write-Host "Version: $Version | Date range: $DateRangeText" -ForegroundColor DarkGray
Write-Host "Treatment queue size: $QueueCount" -ForegroundColor DarkGray
Write-Host ""
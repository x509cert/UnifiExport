#Requires -Version 7
# Exports UniFi Network config + RF stats to a single JSON file for WiFi optimization review.
param([switch]$ResetKey)

$keyPath = Join-Path $env:LOCALAPPDATA 'UnifiExport\api-key.xml'
if ($ResetKey) { Remove-Item $keyPath -ErrorAction SilentlyContinue }
if (-not $env:UNIFI_API_KEY -and -not (Test-Path $keyPath)) {
    New-Item -ItemType Directory -Force (Split-Path $keyPath) | Out-Null
    Read-Host 'UniFi Network API key' -AsSecureString | Export-Clixml $keyPath
}
$key = $env:UNIFI_API_KEY ?? (Import-Clixml $keyPath | ConvertFrom-SecureString -AsPlainText)

$host_  = "https://$($env:UNIFI_HOST ?? '192.168.1.230')"
$base   = "$host_/proxy/network/integration/v1"
$legacy = "$host_/proxy/network/api/s/default"
$h      = @{'X-API-KEY'=$key; Accept='application/json'}
$out    = ".\unifi-export-$(Get-Date -Format yyyyMMdd-HHmm).json"

function Get-Api($url) { irm $url -Headers $h -SkipCertificateCheck }
function Show($label, $data) { Write-Host "   $(@($data).Count) $label" -ForegroundColor DarkGray; $data }
function Get-Details($path, $label) {
    $list = @((Get-Api "$base/${path}?limit=200").data); $i = 0
    foreach ($item in $list) { $i++; Write-Host "`r   $label $i/$($list.Count)" -NoNewline -ForegroundColor DarkGray; Get-Api "$base/$path/$($item.id)" }
    Write-Host
}

Write-Host '== Site ==' -ForegroundColor Cyan
$site = (Get-Api "$base/sites").data[0].id
Write-Host "   $site" -ForegroundColor DarkGray

Write-Host '== Devices ==' -ForegroundColor Cyan
$devices = Show 'devices' (Get-Api "$base/sites/$site/devices?limit=200").data

Write-Host '== Clients ==' -ForegroundColor Cyan
$clients = Get-Details "sites/$site/clients" 'clients'

Write-Host '== Networks ==' -ForegroundColor Cyan
$networks = Get-Details "sites/$site/networks" 'networks'

Write-Host '== WiFi Broadcasts ==' -ForegroundColor Cyan
$wifi = Get-Details "sites/$site/wifi/broadcasts" 'broadcasts'

Write-Host '== AP Radio Stats ==' -ForegroundColor Cyan
$apStats = Show 'devices' (Get-Api "$legacy/stat/device").data

Write-Host '== Client RF Stats ==' -ForegroundColor Cyan
$staStats = Show 'clients' (Get-Api "$legacy/stat/sta").data

Write-Host '== WLAN Config ==' -ForegroundColor Cyan
$wlanConf = Show 'WLANs' (Get-Api "$legacy/rest/wlanconf").data

Write-Host '== Neighbor APs ==' -ForegroundColor Cyan
$rogue = Show 'neighbor APs' (Get-Api "$legacy/stat/rogueap").data

Write-Host '== Scrubbing secrets ==' -ForegroundColor Cyan
function Scrub($o) {
    if ($o -is [pscustomobject]) {
        foreach ($p in @($o.PSObject.Properties)) {
            if ($p.Name -like 'x_*' -or $p.Name -match 'passphrase|password|psk|secret|preshared') { $o.PSObject.Properties.Remove($p.Name) }
            else { Scrub $p.Value }
        }
    } elseif ($o -is [System.Collections.IEnumerable] -and $o -isnot [string]) { foreach ($i in $o) { Scrub $i } }
}

$export = [ordered]@{
    exported = (Get-Date -Format o)
    siteId   = $site
    devices  = $devices
    clients  = $clients
    networks = $networks
    wifi     = $wifi
    apStats  = $apStats
    staStats = $staStats
    wlanConf = $wlanConf
    rogueAPs = $rogue
}
Scrub $export.Values

Write-Host "== Writing $out ==" -ForegroundColor Cyan
$export | ConvertTo-Json -Depth 30 | Set-Content $out
$leaks = Select-String $out -Pattern '"(x_\w+|\w*(passphrase|password|psk|secret)\w*)"\s*:'
if ($leaks) { Write-Warning "Possible secrets left in ${out}:"; $leaks | Select-Object -First 5 }
else { Write-Host "   Secret check: clean ($([math]::Round((Get-Item $out).Length/1KB)) KB)" -ForegroundColor Green }
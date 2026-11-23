#Requires -Version 7
# Exports UniFi Network config + RF stats to a single JSON file for WiFi optimization review.

$key  = '<key>'
$host_  = 'https://192.168.1.xxx'
$base   = "$host_/proxy/network/integration/v1"
$legacy = "$host_/proxy/network/api/s/default"
$h      = @{'X-API-KEY'=$key; Accept='application/json'}
$out    = ".\unifi-export-$(Get-Date -Format yyyyMMdd-HHmm).json"

Write-Host '== Site ==' -ForegroundColor Cyan
$site = (irm "$base/sites" -Headers $h -SkipCertificateCheck).data[0].id

Write-Host '== Devices ==' -ForegroundColor Cyan
$devices = (irm "$base/sites/$site/devices?limit=200" -Headers $h -SkipCertificateCheck).data

Write-Host '== Clients ==' -ForegroundColor Cyan
$clients = (irm "$base/sites/$site/clients?limit=200" -Headers $h -SkipCertificateCheck).data | % { irm "$base/sites/$site/clients/$($_.id)" -Headers $h -SkipCertificateCheck }

Write-Host '== Networks ==' -ForegroundColor Cyan
$networks = (irm "$base/sites/$site/networks?limit=200" -Headers $h -SkipCertificateCheck).data | % { irm "$base/sites/$site/networks/$($_.id)" -Headers $h -SkipCertificateCheck }

Write-Host '== WiFi Broadcasts ==' -ForegroundColor Cyan
$wifi = (irm "$base/sites/$site/wifi/broadcasts?limit=200" -Headers $h -SkipCertificateCheck).data | % { irm "$base/sites/$site/wifi/broadcasts/$($_.id)" -Headers $h -SkipCertificateCheck }

Write-Host '== AP Radio Stats ==' -ForegroundColor Cyan
$apStats = (irm "$legacy/stat/device" -Headers $h -SkipCertificateCheck).data

Write-Host '== Client RF Stats ==' -ForegroundColor Cyan
$staStats = (irm "$legacy/stat/sta" -Headers $h -SkipCertificateCheck).data

Write-Host '== WLAN Config ==' -ForegroundColor Cyan
$wlanConf = (irm "$legacy/rest/wlanconf" -Headers $h -SkipCertificateCheck).data

Write-Host '== Neighbor APs ==' -ForegroundColor Cyan
$rogue = (irm "$legacy/stat/rogueap" -Headers $h -SkipCertificateCheck).data

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
Select-String $out -Pattern 'passphrase|password|psk' | Select-Object -First 5

# Install Sysmon (sysmon-modular config) and the Splunk Universal Forwarder on a lab Windows host.
# The Windows counterpart of install-uf.sh. Run as SYSTEM or an elevated admin. Idempotent: a rerun
# updates the Sysmon config and rewrites the forwarder's inputs/outputs.
# From ops, through the guest agent (the wrappers base64-encode the script):
#   win-client ws01 exec "$(cat install-uf-windows.ps1)"      (clients)
#   vm152 exec "$(cat install-uf-windows.ps1)"                (dc01)
# The MSI install outlasts the 50 s exec wait: poll with exec-status <pid>, then read
# C:\ProgramData\homelab\install-uf.log.
# Design and data policy: docs/architecture/siem.md.
# No param() block: the exec wrappers prepend a line, and param() must come first.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Indexer = '10.12.30.20:9997'
$Work = "$env:ProgramData\homelab"

# Splunk Universal Forwarder (same version as the Linux hosts). SHA-512 from download.splunk.com's .sha512 file.
$UfMsi = 'splunkforwarder-10.4.4-f0f12fcdcaa1-windows-x64.msi'
$UfUrl = "https://download.splunk.com/products/universalforwarder/releases/10.4.4/windows/$UfMsi"
$UfSha512 = '96ad21a1d8146102d8e6a079b1671d02afbddae91c88b78d5112ba168fdefa4e56efa7f3798c437efaee32d09725c55303611974b28e64457f027d738ba5a419'

# Sysmon config: olafhartong/sysmon-modular (MIT), default balanced config, pinned to a release.
# The SHA-256 is the release asset's published digest.
$SysmonCfgUrl = 'https://github.com/olafhartong/sysmon-modular/releases/download/configs-082cba578667/sysmonconfig.xml'
$SysmonCfgSha256 = 'f115aac5770dae468e5cfb48c58a8b6e37588208a31f1b746812c534577a244b'
# Sysmon itself: Sysinternals publishes no hashes and updates in place, so check Microsoft's signature instead.
$SysmonZipUrl = 'https://download.sysinternals.com/files/Sysmon.zip'

New-Item -ItemType Directory -Force -Path $Work | Out-Null
$Log = "$Work\install-uf.log"
function Log($m) { $l = "$(Get-Date -Format s) $m"; Add-Content -Path $Log -Value $l; Write-Output $l }

function Get-Checked($url, $path, $algo, $hash) {
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $path
    $got = (Get-FileHash -Algorithm $algo -Path $path).Hash.ToLower()
    if ($got -ne $hash) { Remove-Item $path -Force; throw "$algo mismatch for $url (got $got)" }
}

# Native tools (Sysmon) print banners on stderr, which ErrorActionPreference=Stop would turn into a
# terminating error. Run them as processes and judge by exit code.
function Invoke-Native($exe, $argList) {
    $p = Start-Process -FilePath $exe -ArgumentList $argList -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput "$Work\native.out" -RedirectStandardError "$Work\native.err"
    return $p.ExitCode
}

function Assert-Signed($path, $publisher) {
    $s = Get-AuthenticodeSignature -FilePath $path
    if ($s.Status -ne 'Valid' -or $s.SignerCertificate.Subject -notmatch "O=$publisher") {
        throw "bad signature on $path : $($s.Status) $($s.SignerCertificate.Subject)"
    }
}

try {
    # 1. Sysmon
    $upstream = "$Work\sysmonconfig.xml"
    Get-Checked $SysmonCfgUrl $upstream 'SHA256' $SysmonCfgSha256
    # Sysmon 15.22 logs no DNS queries (event 22) at all when the config has more than one DnsQuery
    # RuleGroup, and sysmon-modular ships twelve. Each group alone works, any two together log
    # nothing (bisected on ws01, 2026-10-03). Merge their rules into the first group; the
    # exclusions still apply. The verified upstream file stays as downloaded.
    $x = [xml](Get-Content $upstream -Raw)
    $ef = $x.Sysmon.EventFiltering
    $dns = @($ef.RuleGroup | Where-Object { $_.DnsQuery })
    foreach ($rg in $dns | Select-Object -Skip 1) {
        foreach ($r in @($rg.DnsQuery.ChildNodes)) { [void]$dns[0].DnsQuery.AppendChild($r) }
        [void]$ef.RemoveChild($rg)
    }
    # Ingest budget: the forwarder relaunches its idle helper inputs (regmon, netmon, admon, ...) every
    # minute, and each launch logs a burst of image loads: ~25-30 MB/day per host of Splunk watching
    # itself (measured 2026-10-03). Exclude image loads by its binaries and file creates in its var\
    # (checkpoints), the way sysmon-modular already excludes other security agents. Writing either
    # path needs admin rights.
    $uf = "$env:ProgramFiles\SplunkUniversalForwarder"
    foreach ($e in @(@('ImageLoad', 'Image', "$uf\bin\"), @('FileCreate', 'TargetFilename', "$uf\var\"))) {
        $grp = @($ef.RuleGroup | ForEach-Object { $_.($e[0]) } | Where-Object { $_.onmatch -eq 'exclude' })[0]
        $rule = $x.CreateElement($e[1])
        $rule.SetAttribute('condition', 'begin with')
        $rule.InnerText = $e[2]
        [void]$grp.AppendChild($rule)
    }
    $cfg = "$Work\sysmonconfig-lab.xml"
    $x.Save($cfg)
    Log "sysmon config: $($dns.Count) DnsQuery groups merged into 1, forwarder self-noise excluded"
    $exe = "$env:SystemRoot\Sysmon64.exe"
    if (Get-Service Sysmon64 -ErrorAction SilentlyContinue) {
        $rc = Invoke-Native $exe @('-c', $cfg)
        if ($rc -ne 0) { throw "Sysmon config update exit code $rc" }
        Log 'sysmon: config updated'
    } else {
        $zip = "$Work\Sysmon.zip"
        Invoke-WebRequest -UseBasicParsing -Uri $SysmonZipUrl -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath "$Work\sysmon" -Force
        Assert-Signed "$Work\sysmon\Sysmon64.exe" 'Microsoft Corporation'
        $rc = Invoke-Native "$Work\sysmon\Sysmon64.exe" @('-accepteula', '-i', $cfg)
        if ($rc -ne 0) { throw "Sysmon install exit code $rc" }
        Remove-Item $zip, "$Work\sysmon" -Recurse -Force
        Log "sysmon: installed"
    }
    $sv = (Get-Item $exe).VersionInfo.FileVersion
    Log "sysmon: $sv, service $((Get-Service Sysmon64).Status)"

    # 2. Universal Forwarder package. Runs as its low-privilege virtual account (the 10.x default);
    #    the installer grants it the rights to read event logs. Admin password random, never shown.
    $UF = "$env:ProgramFiles\SplunkUniversalForwarder"
    if (-not (Test-Path "$UF\bin\splunkd.exe")) {
        $msi = "$Work\$UfMsi"
        Get-Checked $UfUrl $msi 'SHA512' $UfSha512
        Assert-Signed $msi 'Splunk'
        $p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @(
            '/i', "`"$msi`"", 'AGREETOLICENSE=Yes', 'LAUNCHSPLUNK=0', 'SERVICESTARTTYPE=auto',
            'SPLUNKUSERNAME=admin', 'GENRANDOMPASSWORD=1', '/qn', '/norestart', '/l*v', "`"$Work\uf-msi.log`"")
        if ($p.ExitCode -ne 0) { throw "UF msiexec exit code $($p.ExitCode), see $Work\uf-msi.log" }
        Remove-Item $msi -Force
        Log 'uf: installed'
    }

    # The forwarder's virtual account reads Security, System and the other channels through the rights
    # the installer grants, but Sysmon's channel admits only SYSTEM, Administrators and Event Log
    # Readers (errorCode=5 otherwise). Grant read to the service SID on that one channel. A group
    # membership wouldn't work on a DC, which has no local groups.
    $sid = ([Security.Principal.NTAccount]'NT SERVICE\SplunkForwarder').Translate([Security.Principal.SecurityIdentifier]).Value
    $ch = 'Microsoft-Windows-Sysmon/Operational'
    $sddl = ((wevtutil gl $ch) | Select-String 'channelAccess: (.*)').Matches[0].Groups[1].Value
    if ($sddl -notmatch [regex]::Escape($sid)) {
        $rc = Invoke-Native 'wevtutil.exe' @('sl', "`"$ch`"", "/ca:$sddl(A;;0x1;;;$sid)")
        if ($rc -ne 0) { throw "wevtutil sl exit code $rc" }
        Log "sysmon channel: read granted to NT SERVICE\SplunkForwarder ($sid)"
    }

    # 3. Config: management port on localhost only (as on Linux), then output + inputs in our own app.
    $host_ = $env:COMPUTERNAME.ToLower()
    Set-Content -Encoding ascii -Path "$UF\etc\system\local\web.conf" -Value "[settings]`r`nmgmtHostPort = 127.0.0.1:8089"
    $app = "$UF\etc\apps\homelab_uf\local"
    New-Item -ItemType Directory -Force -Path $app | Out-Null
    Set-Content -Encoding ascii -Path "$app\outputs.conf" -Value @"
[tcpout]
defaultGroup = splunk

[tcpout:splunk]
server = $Indexer
"@
    # XML rendering keeps every field (EventData Name/value pairs) and is smaller than the classic text.
    # Security: the Windows Filtering Platform connection events (5156-5158) and directory-object
    # access (4662) are the classic budget killers, and Sysmon covers network connections better.
    Set-Content -Encoding ascii -Path "$app\inputs.conf" -Value @"
[default]
host = $host_

[WinEventLog://Security]
index = wineventlog
renderXml = true
evt_resolve_ad_obj = 0
blacklist1 = `$XmlRegex="<EventID>(?:4662|5156|5157|5158)</EventID>"

[WinEventLog://System]
index = wineventlog
renderXml = true

[WinEventLog://Application]
index = wineventlog
renderXml = true

[WinEventLog://Microsoft-Windows-PowerShell/Operational]
index = wineventlog
renderXml = true

[WinEventLog://Microsoft-Windows-Windows Defender/Operational]
index = wineventlog
renderXml = true

[WinEventLog://Microsoft-Windows-Sysmon/Operational]
index = sysmon
renderXml = true
"@
    Restart-Service SplunkForwarder
    Start-Sleep 5
    Log "uf: service $((Get-Service SplunkForwarder).Status), host $host_, indexer $Indexer"
} catch {
    Log "FAILED: $_"
    exit 1
}

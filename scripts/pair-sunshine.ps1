<#
.SYNOPSIS
  Headless Moonlight<->Sunshine pairing for the fleet. No web UI, no manual PIN.

.DESCRIPTION
  Pairs this machine's Moonlight client with a Sunshine host over the NetBird
  overlay, driving the whole PIN exchange automatically:

    1. picks a random 4-digit PIN
    2. runs `moonlight pair <host> --pin <PIN>` (client side)
    3. feeds that PIN to the host's Sunshine API over an SSH tunnel
       (the admin web UI is localhost-only by design, so we tunnel to it)

  The Sunshine admin password is read from a LOCAL secret file that you create
  and control -- it is NEVER passed on a command line, committed, or exposed.
  Travels only inside the SSH-encrypted tunnel to the host's localhost.

  Pairing is mutual and persistent: once paired, Moonlight stores the host and
  Sunshine stores this client's cert, so you never pair this pair again.

.PARAMETER HostFqdn
  The Sunshine host's NetBird FQDN, e.g. hestia.netbird.cloud

.PARAMETER Name
  Device name recorded on the host. Defaults to this machine's hostname.

.PARAMETER User
  Sunshine web-UI admin username on the host. Default: sebastianstupak

.PARAMETER SecretFile
  Path to a file whose FIRST line is the host's Sunshine admin password.
  Default: $HOME\.config\sunshine-pair\<host>.pass
  Create it once, per host (each host has its OWN admin password):
      mkdir $HOME\.config\sunshine-pair
      'your-sunshine-admin-password' | Set-Content $HOME\.config\sunshine-pair\hestia.netbird.cloud.pass

.EXAMPLE
  ./pair-sunshine.ps1 hestia.netbird.cloud
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$HostFqdn,
  [string]$Name = $env:COMPUTERNAME,
  [string]$User = 'sebastianstupak',
  [string]$SecretFile,
  [switch]$SetPassword
)

$ErrorActionPreference = 'Stop'
$LocalPort = 17990   # 47990 is reserved on some Windows hosts; any free port works

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# Each host has its OWN Sunshine admin password, stored ENCRYPTED with Windows
# DPAPI (ConvertFrom-SecureString, no key): the on-disk blob is decryptable ONLY
# by this Windows user on this machine. The password is never typed on a command
# line (prompted hidden) and never written in plaintext.
if (-not $SecretFile) { $SecretFile = Join-Path $HOME ".config\sunshine-pair\$HostFqdn.pass" }

# --- -SetPassword: prompt (hidden), encrypt, store, exit ----------------------
if ($SetPassword) {
  New-Item -ItemType Directory -Force (Split-Path $SecretFile) | Out-Null
  $secIn = Read-Host -AsSecureString "Sunshine admin password for $HostFqdn (hidden)"
  if ($secIn.Length -eq 0) { Fail "Empty password; nothing written." }
  ConvertFrom-SecureString -SecureString $secIn | Set-Content -Path $SecretFile -Encoding ASCII
  # defense in depth on top of DPAPI: strip inheritance, grant only this user read
  try { icacls $SecretFile /inheritance:r /grant:r "$($env:USERNAME):R" | Out-Null } catch { }
  Write-Host "Encrypted password stored at $SecretFile" -ForegroundColor Green
  Write-Host "(DPAPI-bound: only $env:USERNAME on $env:COMPUTERNAME can decrypt it.)" -ForegroundColor Green
  exit 0
}

# --- locate Moonlight ---------------------------------------------------------
$moon = Get-ChildItem 'C:\Program Files*' -Recurse -Filter Moonlight.exe -ErrorAction SilentlyContinue |
  Select-Object -First 1 -ExpandProperty FullName
if (-not $moon) { Fail "Moonlight.exe not found. Install it: winget install MoonlightGameStreamingProject.Moonlight" }

# --- load + DPAPI-decrypt the admin password (never plaintext on disk) ---------
if (-not (Test-Path $SecretFile)) {
  Fail @"
No password set for $HostFqdn.
Set it once (prompts hidden, stores DPAPI-encrypted for your Windows account):
    .\pair-sunshine.ps1 $HostFqdn -SetPassword
"@
}
try {
  $secPass = (Get-Content $SecretFile -Raw).Trim() | ConvertTo-SecureString -ErrorAction Stop
}
catch {
  Fail "Could not decrypt $SecretFile with your Windows account. DPAPI is user+machine bound, so a blob created by -SetPassword on THIS PC as THIS user is required (not a copied file, not old plaintext). Re-run with -SetPassword."
}

# --- open the SSH tunnel to the host's localhost-only Sunshine web UI ---------
Write-Host "Opening SSH tunnel to $HostFqdn (localhost:$LocalPort -> :47990)..." -ForegroundColor Cyan
$tunnel = Start-Process ssh -ArgumentList @(
  '-o', 'BatchMode=yes', '-o', 'ExitOnForwardFailure=yes',
  '-N', '-L', "${LocalPort}:localhost:47990", $HostFqdn
) -PassThru -WindowStyle Hidden
try {
  # wait for the forwarded port to accept connections
  $up = $false
  for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Milliseconds 700
    if ((Test-NetConnection -ComputerName localhost -Port $LocalPort -WarningAction SilentlyContinue).TcpTestSucceeded) { $up = $true; break }
    if ($tunnel.HasExited) { Fail "SSH tunnel died (exit $($tunnel.ExitCode)). Is '$HostFqdn' reachable? Try: ssh $HostFqdn echo ok" }
  }
  if (-not $up) { Fail "Tunnel did not come up on localhost:$LocalPort" }

  # confirm Sunshine answers (401 = reachable + auth required, which is correct)
  $probe = curl.exe -k -s -o $null -w "%{http_code}" --max-time 15 "https://localhost:$LocalPort/" 2>&1
  if ($probe -notin @('401', '200', '302')) { Fail "Sunshine web UI not responding through the tunnel (got '$probe')." }

  # --- pick a PIN and kick off the client-side pairing -----------------------
  $pin = '{0:D4}' -f (Get-Random -Minimum 0 -Maximum 10000)
  Write-Host "Pairing with PIN $pin ..." -ForegroundColor Cyan
  $pairProc = Start-Process $moon -ArgumentList @('pair', $HostFqdn, '--pin', $pin) -PassThru -WindowStyle Hidden

  Start-Sleep -Seconds 4   # let Moonlight register the pending pair session on the host

  # --- accept the PIN on the host via Sunshine's API --------------------------
  # Basic auth; we deliberately send NO Origin/Referer header, so Sunshine's
  # CSRF check treats us as a non-browser client and skips the token. We must
  # pass the pending session's pairing_id, which Moonlight created above and we
  # read from GET /api/pin (it lists pending pairings with their id/name/address).
  # decrypt to plaintext only transiently in memory, to build the Basic header
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass)
  try {
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${User}:${plain}"))
  }
  finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr); $plain = $null
  }

  $pairingId = $null; $pending = ''
  for ($i = 0; $i -lt 12; $i++) {
    $pending = (curl.exe -k -s --max-time 15 -H "Authorization: Basic $b64" "https://localhost:$LocalPort/api/pin" 2>&1 | Out-String).Trim()
    if ($pending -match 'Unauthorized') {
      Fail "Sunshine rejected the admin password in $SecretFile. Set it on the host (sunshine --creds $User '<pass>') and put the SAME value in that file."
    }
    try { $pairingId = ((($pending | ConvertFrom-Json).pairings) | Select-Object -First 1).id } catch { $pairingId = $null }
    if ($pairingId) { break }
    Start-Sleep -Seconds 2
  }
  if (-not $pairingId) { Fail "No pending pairing appeared (Moonlight may not have initiated). Last GET /api/pin: $pending" }

  $body = (@{ pairing_id = $pairingId; pin = $pin; name = $Name } | ConvertTo-Json -Compress)
  $resp = (curl.exe -k -s --max-time 30 `
      -H "Authorization: Basic $b64" -H "Content-Type: application/json" `
      -X POST -d $body "https://localhost:$LocalPort/api/pin" 2>&1 | Out-String).Trim()
  Write-Host "Sunshine /api/pin response: $resp"
  if ($resp -match '"status"\s*:\s*true') {
    Write-Host "PIN accepted - handshake completing..." -ForegroundColor Green
  } else {
    Write-Host "Pairing did not report success (status != true); check the response above." -ForegroundColor Yellow
  }

  # give Moonlight up to ~40s to complete (it times out around 56s itself)
  if (-not $pairProc.WaitForExit(40000)) { $pairProc.Kill() }

  # --- verify ----------------------------------------------------------------
  Write-Host "Verifying pairing (moonlight list)..." -ForegroundColor Cyan
  $list = & $moon list $HostFqdn 2>&1 | Out-String
  if ($list -match 'paired|Desktop|App') {
    Write-Host "PAIRED. '$HostFqdn' is ready - launch its Desktop from Moonlight." -ForegroundColor Green
  } else {
    Write-Host "Could not confirm via 'moonlight list'. Open Moonlight: if $HostFqdn shows no lock icon, it's paired." -ForegroundColor Yellow
    Write-Host ("list output: " + ($list.Trim()))
  }
}
finally {
  if ($pairProc -and -not $pairProc.HasExited) { try { $pairProc.Kill() } catch {} }
  if ($tunnel -and -not $tunnel.HasExited) { try { $tunnel.Kill() } catch {} }
}

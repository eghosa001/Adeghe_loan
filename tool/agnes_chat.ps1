param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Prompt = "Hello",

    [string]$Model,

    [string]$ApiKey,

    [string]$System,

    [switch]$ListModels
)

$ErrorActionPreference = "Stop"

$baseUrl = "https://router.bynara.id/v1"

$KnownModels = @(
    "agnes-2.0-flash",
    "agnes-2.5-flash",
    "agnes-2.5-pro",
    "grok-4.5-free",
    "laguna-s-2.1",
    "ling-3.0-flash-free",
    "longcat-2.0-free",
    "tencent-hy3-free",
    "stepfun-3.7-flash",
    "mistral-medium-3-5"
)

if (-not $ApiKey) {
    $ApiKey = $env:BYNARA_API_KEY
}
if (-not $ApiKey) {
    $ApiKey = Read-Host "BYNARA_API_KEY"
}

function Get-BynaraModels {
    $live = @()
    try {
        $resp = curl.exe -sS "$baseUrl/models" `
            -H "Authorization: Bearer $ApiKey"
        $json = ($resp -join "`n") | ConvertFrom-Json
        $live = @($json.data | ForEach-Object { $_.id })
    }
    catch {
        # ignore, known models still apply
    }
    return @($live + $KnownModels | Select-Object -Unique)
}

if ($ListModels) {
    $ids = Get-BynaraModels
    $ids | ForEach-Object { Write-Output $_ }
    exit 0
}

if (-not $Model) {
    $ids = Get-BynaraModels
    if ($ids.Count -eq 0) {
        Write-Host "Could not fetch model list; defaulting to agnes-2.0-flash."
        $Model = "agnes-2.0-flash"
    }
    else {
        Write-Host "Available models:"
        Write-Host "(live from $baseUrl/models merged with known list)"
        for ($i = 0; $i -lt $ids.Count; $i++) {
            Write-Host ("{0,3}) {1}" -f ($i + 1), $ids[$i])
        }
        $choice = Read-Host "Select model number (1-$($ids.Count)) or press Enter for 1"
        $idx = 0
        if ($choice -and [int]::TryParse($choice, [ref]$idx)) {
            if ($idx -lt 1 -or $idx -gt $ids.Count) {
                Write-Error "Invalid selection: $choice"
                exit 1
            }
            $Model = $ids[$idx - 1]
        }
        else {
            $Model = $ids[0]
        }
    }
}

$messages = @()
if ($System) {
    $messages += @{ role = "system"; content = $System }
}
$messages += @{ role = "user"; content = $Prompt }

$body = @{
    model    = $Model
    messages = $messages
} | ConvertTo-Json -Depth 5

$tmp = Join-Path $env:TEMP "bynara_req_$([guid]::NewGuid().ToString('N')).json"
Set-Content -LiteralPath $tmp -Value $body -NoNewline -Encoding Ascii

try {
    curl.exe -sS "$baseUrl/chat/completions" `
        -H "Authorization: Bearer $ApiKey" `
        -H "Content-Type: application/json" `
        -d "@$tmp"
} finally {
    Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
}

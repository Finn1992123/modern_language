param(
    [ValidateSet('internal', 'production')][string]$Track = 'internal',
    [Parameter(Mandatory = $true)][string]$NotesFile,
    [switch]$Upload
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$notesPath = (Resolve-Path -LiteralPath $NotesFile).Path
$notes = [IO.File]::ReadAllText($notesPath).Trim()
if (!$notes -or $notes.Length -gt 500) { throw 'Release notes must contain 1-500 characters.' }
Push-Location $projectRoot
try {
    if (!(Test-Path -LiteralPath 'android/key.properties')) { throw 'Missing Android signing configuration.' }
    $nextCode = & node scripts/play-console.mjs next-code
    if ($LASTEXITCODE -ne 0) { throw 'Play Console access check failed.' }
    $nextCode = "$nextCode".Trim()
    if ($nextCode -notmatch '^\d+$') { throw 'Invalid version code returned.' }
    & flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed.' }
    & flutter test
    if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }
    & flutter build appbundle --release --build-number=$nextCode
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed.' }
    $aab = Join-Path $projectRoot 'build/app/outputs/bundle/release/app-release.aab'
    Write-Host "Built version code ${nextCode}: $aab"
    Get-FileHash -LiteralPath $aab -Algorithm SHA256 | Format-List
    if ($Upload) {
        & node scripts/play-console.mjs upload $aab $Track $notesPath
        if ($LASTEXITCODE -ne 0) { throw 'Play upload failed. See the message above before retrying.' }
    }
} finally {
    Pop-Location
}

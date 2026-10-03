# Incrémente le numéro de build (pubspec version: x.y.z+N) et lib/core/app_version.dart.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$pubspec = Join-Path $root "pubspec.yaml"
$versionFile = Join-Path $root "lib\core\app_version.dart"

$raw = Get-Content $pubspec -Raw
if ($raw -notmatch '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$') {
  throw "version pubspec introuvable (attendu x.y.z+N)"
}
$name = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
$code = [int]$Matches[4] + 1
$line = "version: $name+$code"

$raw = [regex]::Replace($raw, '(?m)^version:\s*\d+\.\d+\.\d+\+\d+\s*$', $line)
Set-Content -Path $pubspec -Value $raw.TrimEnd() -NoNewline
Add-Content -Path $pubspec -Value ""

$dart = @"
/// Mis a jour par tool/bump_version.ps1 avant chaque build APK.
const String appVersionName = "$name";
const int appVersionCode = $code;

String get appVersionLabel => "`$appVersionName+`$appVersionCode";
"@
Set-Content -Path $versionFile -Value $dart.TrimEnd() -Encoding utf8
Write-Host "version $name+$code"

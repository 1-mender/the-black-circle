param([string]$GodotPath = '', [switch]$DisableShaderCache, [string]$TestScript = 'res://tests/speech_test.gd')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $GodotPath) {
    $GodotPath = Join-Path $env:TEMP 'zlatogorye-godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Укажите установленный Godot через -GodotPath' }
$overridePath = Join-Path $projectRoot 'override.cfg'
$createdOverride = $false
$testUiPrefsPrevious = $env:ZLATOGORYE_UI_PREFS
$env:ZLATOGORYE_UI_PREFS = 'res://.godot/interface_defaults_for_tests.cfg'
try {
    if ($DisableShaderCache) {
        if (Test-Path -LiteralPath $overridePath) { throw 'Существующий override.cfg сохранён: временное переопределение не выполнено.' }
        # Only disk caching changes, not rendering, simulation, or user save paths.
        [System.IO.File]::WriteAllText($overridePath, "[rendering]`nshader_compiler/shader_cache/enabled=false`n", [System.Text.UTF8Encoding]::new($false))
        $createdOverride = $true
    }
    $logPath = Join-Path $projectRoot '.godot/cinema_graphics_verified.log'
    $result = & $GodotPath --path $projectRoot --rendering-driver d3d12 --script $TestScript --log-file $logPath -- --capture 2>&1
    $exitCode = $LASTEXITCODE
    $result | Write-Output
    $errors = $result | Where-Object { "$_" -match 'SCRIPT ERROR|^ERROR:' -and "$_" -notmatch 'Failed to read the root certificate store' }
    if ($exitCode -ne 0 -or $errors) { throw ('Графическая проверка не пройдена. См. ' + $logPath) }
} finally {
    $env:ZLATOGORYE_UI_PREFS = $testUiPrefsPrevious
    if ($createdOverride) { Remove-Item -LiteralPath $overridePath }
}

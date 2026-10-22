param([string]$GodotPath = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $GodotPath) {
    $installed = Get-Command godot, godot_console -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($installed) { $GodotPath = $installed.Source }
    else { $GodotPath = Join-Path $env:TEMP 'zlatogorye-godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' }
}
if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Передайте путь к Godot: -GodotPath C:\путь\Godot_console.exe' }
$checks = @(
    @{Name='import'; Args=@('--editor','--import','--quit')},
    @{Name='smoke'; Args=@('--script','res://tests/smoke_test.gd')},
    @{Name='movement_visual'; Args=@('--script','res://tests/movement_visual_test.gd')},
    @{Name='economy'; Args=@('--script','res://tests/economy_test.gd')},
    @{Name='economy_fresh'; Args=@('--script','res://tests/economy_test.gd','--','--verify-save')},
    @{Name='residents'; Args=@('--script','res://tests/resident_test.gd')},
    @{Name='residents_fresh'; Args=@('--script','res://tests/resident_test.gd','--','--verify-save')},
    @{Name='load_input'; Args=@('--script','res://tests/load_input_test.gd')},
    @{Name='production'; Args=@('--script','res://tests/production_test.gd')},
    @{Name='production_fresh'; Args=@('--script','res://tests/production_test.gd','--','--verify-save')},
    @{Name='rpg'; Args=@('--script','res://tests/rpg_test.gd')},
    @{Name='combat'; Args=@('--script','res://tests/combat_test.gd')},
    @{Name='combat_visual'; Args=@('--script','res://tests/combat_visual_test.gd')},
    @{Name='rpg_ui'; Args=@('--script','res://tests/rpg_ui_test.gd')},
    @{Name='inventory051'; Args=@('--script','res://tests/inventory_ui_test.gd')},
    @{Name='adventure_loot'; Args=@('--script','res://tests/adventure_loot_test.gd')},
    @{Name='adventure_combat'; Args=@('--script','res://tests/adventure_combat_test.gd')},
    @{Name='skills'; Args=@('--script','res://tests/skill_test.gd')},
    @{Name='adventure_journey'; Args=@('--script','res://tests/adventure_journey_test.gd')},
    @{Name='social'; Args=@('--script','res://tests/social_test.gd')},
    @{Name='social_integration'; Args=@('--script','res://tests/social_integration_test.gd')},
    @{Name='crowd_interaction'; Args=@('--script','res://tests/crowd_interaction_test.gd')},
    @{Name='conversation'; Args=@('--script','res://tests/conversation_test.gd')},
    @{Name='speech'; Args=@('--script','res://tests/speech_test.gd')},
    @{Name='dark_map'; Args=@('--script','res://tests/dark_map_test.gd')},
    @{Name='minimal_menu'; Args=@('--script','res://tests/minimal_menu_test.gd')}
    @{Name='dynamic_residents'; Args=@('--script','res://tests/dynamic_resident_test.gd')}
)
$testUiPrefsPrevious = $env:ZLATOGORYE_UI_PREFS
$env:ZLATOGORYE_UI_PREFS = 'res://.godot/interface_defaults_for_tests.cfg'
try {
foreach ($entry in $checks) {
    $logPath = Join-Path $projectRoot ('.godot/verify05_' + $entry.Name + '.log')
    $commandArgs = @('--headless','--path',$projectRoot,'--log-file',$logPath) + $entry.Args
    $result = & $GodotPath @commandArgs 2>&1
    $exitCode = $LASTEXITCODE
    $result | Write-Output
    $errors = $result | Where-Object { "$_" -match 'SCRIPT ERROR|^ERROR:' -and "$_" -notmatch 'Failed to read the root certificate store' }
    if ($exitCode -ne 0 -or $errors) { throw ('Проверка не пройдена: ' + $entry.Name + '. Журнал: ' + $logPath) }
}
Write-Output 'Все проверки проекта, включая кинематографические диалоги, пройдены. Пользовательский слот не изменялся.'



} finally {
    $env:ZLATOGORYE_UI_PREFS = $testUiPrefsPrevious
}

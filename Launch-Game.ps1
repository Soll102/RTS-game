$ErrorActionPreference = 'Stop'
$gameEnginePath = $env:GODOT_BIN
if ([string]::IsNullOrWhiteSpace($gameEnginePath)) {
    foreach ($gameCommandName in @('godot', 'godot4')) {
        $gameCommand = Get-Command $gameCommandName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $gameCommand) { $gameEnginePath = $gameCommand.Source; break }
    }
}
if ([string]::IsNullOrWhiteSpace($gameEnginePath) -and $env:LOCALAPPDATA) {
    $gameEngine = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*\Godot*console.exe') -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $gameEngine) { $gameEnginePath = $gameEngine.FullName }
}
if ([string]::IsNullOrWhiteSpace($gameEnginePath) -or -not (Test-Path -LiteralPath $gameEnginePath -PathType Leaf)) {
    throw 'Godot was not found. Install Godot 4.7.2, add it to PATH, or set GODOT_BIN to its executable.'
}
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.godot\global_script_class_cache.cfg'))) {
    & $gameEnginePath --headless --path $PSScriptRoot --import
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
& $gameEnginePath --path $PSScriptRoot
exit $LASTEXITCODE

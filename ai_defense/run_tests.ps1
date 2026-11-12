# AI 디펜스 - 자동 테스트 / 밸런스 / 성능 측정
#
#   .\run_tests.ps1            로직 테스트 (PRD 9장 1~11번)
#   .\run_tests.ps1 balance    밸런스 시뮬레이션 200판 (제안 유지/수락 두 정책)
#   .\run_tests.ps1 perf       성능 측정 (운영 PC에서 실행해 README에 기록)
#   .\run_tests.ps1 ui         화면 자동 점검 (창이 잠깐 뜸, 스크린샷 저장)

param([string]$mode = "logic")

$project = $PSScriptRoot
$godot = Join-Path $project "..\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path $project --import | Out-Null

switch ($mode) {
    "balance" {
        & $godot --headless --path $project --script res://tools/balance_sim.gd -- games=200 policy=keep
        & $godot --headless --path $project --script res://tools/balance_sim.gd -- games=200 policy=accept
    }
    "perf" { & $godot --headless --path $project --script res://tools/perf_bench.gd }
    "anim" {
        $out = Join-Path $project "..buildnim_preview"
        & $godot --path $project --resolution 1500x1260 --script res://tools/anim_preview.gd -- "out=$out"
        Write-Host "프레임 표: $out"
    }
    "ui" {
        $out = Join-Path $project "..\build\ui_smoke"
        & $godot --path $project --script res://tools/ui_smoke.gd -- "out=$out"
        Write-Host "스크린샷: $out"
    }
    default {
        & $godot --headless --path $project --script res://tests/run_tests.gd
        exit $LASTEXITCODE
    }
}

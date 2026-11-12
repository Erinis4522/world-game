# AI 디펜스 - 실행 파일 만들기 (포터블 폴더)
#
# 사용법: PowerShell에서  .\build_exe.ps1      (테스트를 건너뛰려면  .\build_exe.ps1 -SkipTests)
#
# 1) 자동 로직 테스트를 돌리고, 실패하면 멈춘다.
# 2) ../build/AI디펜스/ 폴더에 실행 파일과 시작 배치파일, 데이터, 그림 교체 폴더를 만든다.
#    이 폴더를 통째로 USB에 복사하면 운영 PC에 아무것도 설치하지 않고 실행할 수 있다.
#
# Godot은 ../tools/godot 폴더의 휴대용 버전(4.7.2, 내보내기 템플릿 포함)을 쓴다.

param([switch]$SkipTests)

$project = $PSScriptRoot
$godot = Join-Path $project "..\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
$outDir = [System.IO.Path]::GetFullPath((Join-Path $project "..\build\AI디펜스"))
$outFile = Join-Path $outDir "AIDefense.exe"

if (-not (Test-Path $godot)) {
    Write-Host "Godot을 찾을 수 없습니다: $godot" -ForegroundColor Red
    exit 1
}

if (Test-Path $outFile) {
    try {
        $stream = [System.IO.File]::Open($outFile, 'Open', 'ReadWrite', 'None')
        $stream.Close()
    } catch {
        Write-Host "AIDefense.exe 가 실행 중입니다. 게임을 닫은 뒤 다시 실행하세요." -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "[1/3] 프로젝트 가져오기" -ForegroundColor Cyan
& $godot --headless --path $project --import | Out-Null

if (-not $SkipTests) {
    Write-Host "[2/3] 자동 로직 테스트" -ForegroundColor Cyan
    & $godot --headless --path $project --script res://tests/run_tests.gd
    if ($LASTEXITCODE -ne 0) {
        Write-Host "테스트 실패로 멈춥니다. 위의 ✗ 줄을 확인하세요." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[2/3] 테스트 건너뜀" -ForegroundColor Yellow
}

Write-Host "[3/3] 실행 파일 만들기" -ForegroundColor Cyan
New-Item -ItemType Directory -Force $outDir | Out-Null
& $godot --headless --path $project --export-release "Windows" $outFile
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $outFile)) {
    Write-Host "실행 파일을 만들지 못했습니다." -ForegroundColor Red
    exit 1
}

# 수치 조정용 데이터 (exe 옆 data 폴더가 있으면 그것을 먼저 읽는다)
New-Item -ItemType Directory -Force (Join-Path $outDir "data") | Out-Null
Copy-Item (Join-Path $project "data\*.json") (Join-Path $outDir "data") -Force

# 그림 교체 폴더 (정해진 이름의 PNG를 넣으면 다시 빌드하지 않아도 바뀐다)
foreach ($sub in @("heroes", "enemies", "map", "ui", "effects")) {
    New-Item -ItemType Directory -Force (Join-Path $outDir "assets\$sub") | Out-Null
}
Copy-Item (Join-Path $project "dist\*") $outDir -Recurse -Force

$size = [math]::Round((Get-Item $outFile).Length / 1MB)
Write-Host "완료: $outDir  (AIDefense.exe $size MB)" -ForegroundColor Green
Write-Host "운영 PC에는 이 폴더를 통째로 복사하세요. '시작.bat' 또는 AIDefense.exe 실행." -ForegroundColor Green

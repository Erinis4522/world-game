# 그림 에셋 — 캐릭터 v3

8명의 전신 일러스트·SD·독립 파츠 96개가 적용되어 있다. SD는 전투/배치 지도에 사용하며 나머지 인물 UI는 전신 일러스트를 사용한다.

## 파일

각 캐릭터 ID: `sword`, `archer`, `sniper`, `fire`, `ice`, `lightning`, `bomb`, `mark`.

| 경로 | 용도 |
|---|---|
| `portraits/<id>.png` | 896×1344 전신 원화. 배경 포함. 크롭 영역은 heroes.json에서 설정 |
| `heroes/<id>.png` | 투명 SD 기준 그림, 파츠가 없을 때의 대체 그림 |
| `heroes/rigs/<id>/*.png` | 머리·머리카락·몸통·뒤옷·팔다리·무기 12개 |
| `heroes/rigs/<id>/rig.json` | 겹침 순서, 관절, 부모, 발 기준점, 발사점 |
| `effects/ice_cast.png` | 생성한 얼음 시전·투사체·명중 효과 |

## 파츠 규격

새 7명의 PNG는 빈 여백을 줄인 그림이다. `canvas_offset`을 더하면 1280×1280 공통 캔버스의 위치가 된다. `pivot`, `anchor`, `attachments.position`도 이 공통 좌표계다. `parent` 관절을 먼저 계산한 뒤 `z` 순서로 그린다. 무기는 먼 쪽 아래팔에 연결한다.

서리의 파츠는 기존 공통 캔버스 규격을 유지한다. `canvas_offset` 기본값은 [0,0]이며 `draw_bounds`와 `anchor`를 함께 사용한다. 파츠는 모두 실제 알파 채널을 가진 PNG다. 하얀 배경을 지운 그림이 아니다.

상용 Spine 파일이나 Live2D 모델 형식은 아니며 Godot의 2D 관절 렌더러용이다. 다른 도구에서는 제공된 개별 PNG와 관절 좌표를 가져와 연결할 수 있다.

## 교체

프로젝트의 같은 경로를 덮어쓰고 다시 가져오기/빌드한다. 정식 내보내기 템플릿 실행 파일은 exe 옆 assets 폴더도 우선 읽는다. 이번 포터블 검토판은 별도 PCK를 읽는 엔진 실행판이므로 소스 프로젝트에서 수정한 뒤 PCK를 다시 내보낸다.

## 출처

- 전신 일러스트: 로컬 ComfyUI / novaAnimeAM_v40. 생성 워크플로와 시드가 아트 패키지에 포함된다.
- SD 및 새 독립 파츠: 위 원화를 참조한 GPT 이미지 생성. 서리의 승인된 기존 세트를 포함한다.
- Noto Sans KR: SIL OFL 1.1, fonts/OFL.txt.
- 기존 작품에서 추출한 캐릭터 이미지나 로고는 사용하지 않았다.

## 맵과 몬스터

`map/background.png`에 연구시설 외곽 광장과 도로가 포함된다. `map/base.png`, `spawn.png`, `slot.png`는 투명 구조물이다. 전투/배치 지도에 동일하게 적용된다.

`enemies/<id>_sheet.png`는 normal/fast/armored/boss 각각 4프레임 시트다. 프레임 영역은 `data/enemies.json`의 `art_rects`를 사용한다. `enemies/<id>.png`는 오른쪽 기준 그림이다. 모든 신규 맵·몬스터 그림은 GPT 이미지 생성으로 제작했다. [상세 규격](../docs/WORLD_ART.md).

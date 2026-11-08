# docent

[English](README.md) | 한국어

사용자가 이미 아는 기술과 경험을 바탕으로 Claude Code의 설명을 맞추는 플러그인입니다.
“React로 프론트엔드 일을 하고 있고, Python은 간단한 스크립트만 짜봤어요”처럼 알려주세요. 등급을 정할 필요가 없습니다.

새 기술을 설명할 때 익숙한 개념에서 출발하고, 공통점과 중요한 차이를 짚습니다. 이미 아는 기초는 생략하고 달라지는 부분에 집중합니다. 적절한 대응 관계가 없으면 억지로 비유하지 않습니다. 등록하지 않은 기술을 모른다고 단정하지 않습니다.

## 설치

```text
/plugin marketplace add tnfhrnsss/claude-docent
/plugin install docent@docent
```

Bash가 필요합니다. Windows에서는 Git for Windows를 사용하세요.

## 사용

```text
/docent:status familiar React로 프론트엔드 일을 하고 있고, Python은 간단한 스크립트만 짜봤어요.
/docent:status
```

첫 명령은 경험 설명을 저장하고, 두 번째는 적용되는 프로필을 보여줍니다. 다시 저장하면 전체 설명을 교체합니다. 기술 이름 목록만 입력해도 됩니다. `/docent:status familiar`만 실행하면 전체 프로필을 비웁니다. 변경은 다음 세션이나 `/clear` 뒤부터 적용됩니다.

설명 깊이는 경험에 맞추되, 현재 질문의 요청을 우선합니다. 단순한 작업 완료 보고마다 비유를 붙이지는 않습니다. 이 기능은 클로드에 설명 지침을 전달하는 방식이며, 모든 답변의 품질을 보장하지는 않습니다.

## 설정과 데이터

전체 경험은 `~/.claude/docent/familiar.txt`에 일반 텍스트로 저장합니다. 직접 여러 줄로 작성해도 됩니다. 프로젝트에만 적용하려면 `<프로젝트>/.claude/docent/familiar.txt`를 직접 만드세요. 빈 파일은 그 프로젝트에서 프로필을 비웁니다. 명령은 전체 프로필만 변경하며 프로젝트에는 파일을 쓰지 않습니다.

`~/.claude/docent/config` 또는 `<프로젝트>/.claude/docent/config`에서 다음을 설정할 수 있습니다.

```ini
enabled=true
```

`false`로 하면 프로필 주입을 끕니다. 프로젝트 설정이 전체 설정보다 우선합니다.

기존 `familiar=react, typescript`도 읽습니다. 프로필 우선순위는 프로젝트 `familiar.txt`, 프로젝트 config의 `familiar`, 전체 `familiar.txt`, 전체 config의 `familiar` 순서입니다. 파일에 경험을 저장하면 `C#`, 한글, 여러 줄도 그대로 보존됩니다.

## 이전 버전에서 변경된 점

0.5.0부터 쉬운 말 강제, 자동 설명 단계 조절, 재질문 및 회피 용어 기록을 제거했습니다. `level`, `forget`, `reset`은 더 이상 사용하지 않습니다. 이전 기록은 읽거나 수정하지 않고 남겨둡니다. `familiar`는 기술 목록뿐 아니라 자연어 경험 설명도 받습니다.

## 업데이트

```text
/plugin marketplace update docent
```

`/plugin` → Marketplaces에서 자동 업데이트를 켤 수도 있습니다. 업데이트해도 플러그인 밖에 저장된 경험은 유지됩니다.

## 라이선스

MIT

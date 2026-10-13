# docent

[English](README.md) | 한국어

설명을 못 알아들었을 때("무슨 말이에요?", "쉽게 설명해 주세요")를 알아채고 맞춰 주는 Claude Code 플러그인입니다. 그 부분을 쉬운 말로 다시 설명하고, 헷갈렸던 단어를 기억하고, 다음 답변부터 더 쉽게 말합니다.

답변을 길게 만들지 않습니다. 코드, 커밋, 파일 내용은 건드리지 않습니다.

## 설치

```
/plugin marketplace add tnfhrnsss/claude-docent
/plugin install docent@docent
```

`bash`가 필요합니다. Windows에서는 [Git for Windows](https://git-scm.com/download/win)를 설치하세요.

### 업데이트

직접 추가한 마켓플레이스는 기본적으로 자동 업데이트가 꺼져 있습니다. `/plugin` → Marketplaces에서 `docent`의 자동 업데이트를 켜거나, 직접 업데이트하세요:

```
/plugin marketplace update docent
```

업데이트해도 설정과 쌓인 용어 목록은 그대로 유지됩니다. 이 데이터는 플러그인 폴더 밖인 `~/.claude/docent/`에 저장됩니다.

## 동작 방식

못 알아들었는지는 Claude가 직접 판단합니다. 언어는 상관없습니다. 다시 설명할 때는 답변 맨 끝에 헷갈렸던 단어를 적은 짧은 줄을 붙입니다.

```
(docent: 드레인)
```

docent는 답변이 끝나면 이 줄을 읽고 단어를 기억하고 되물은 횟수를 셉니다. 이 줄은 다시 설명할 때만 붙습니다. 단어가 잘못 기록됐으면 `/docent:status forget <단어>`로 지우세요.

## 설정

선택 사항입니다. `~/.claude/docent/config`(모든 프로젝트) 또는 `<프로젝트>/.claude/docent/config`(이 프로젝트만, 전체 설정보다 우선)를 만드세요.

```
enabled=true     # false로 하면 docent를 끕니다
level=auto       # auto | normal | plain | plainer
familiar=react, typescript   # 잘 아는 스택 (선택)
```

| `level` | 동작 |
|---|---|
| `auto` (기본값) | `normal`에서 시작합니다. 자주 되물으면 한 단계 쉬워지고, 일주일 동안 되묻지 않으면 한 단계 돌아갑니다 |
| `normal` | 평소 말투. 전문 용어나 설명 없는 라벨을 쓰지 않습니다 |
| `plain` | 추가로: 한 문장에 한 가지 내용, 약어는 풀어서 씁니다 |
| `plainer` | 추가로: 결론을 먼저 말하고, 구체적인 예를 하나 듭니다 |

`familiar`를 설정하면, 다른 스택의 개념을 설명할 때 비슷한 것이 있으면 잘 아는 스택에 빗대어 설명합니다. 예를 들어 화면 개발자가 Spring의 의존성 주입을 물으면 React Context와 비교해서 설명합니다. 설정하지 않으면 아무것도 바뀌지 않습니다.

바꾼 설정은 다음 세션이나 `/clear` 뒤부터 적용됩니다.

## 명령

- `/docent:status` — 현재 단계와 기억된 단어를 보여 줍니다
- `/docent:status familiar <스택>` — 잘 아는 스택을 설정합니다 (예: `react, typescript`). 스택 없이 실행하면 설정을 지웁니다
- `/docent:status forget <단어>` — 그 단어를 더 이상 피하지 않습니다
- `/docent:status reset` — 단계와 기억된 단어를 모두 지웁니다

## 데이터

`~/.claude/docent/`에 일반 텍스트로 저장합니다. 프로젝트 폴더 안에는 아무것도 쓰지 않습니다. 이 폴더를 지우면 초기화됩니다.

## 라이선스

MIT

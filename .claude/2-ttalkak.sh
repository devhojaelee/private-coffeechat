#!/bin/bash

# =================================================================
# 설정 변수 및 명령어 정의
# =================================================================
PARENT_ID="$1"
MAX_CONCURRENT=4
TMUX_SESSION_NAME="Claude-Worker-$PARENT_ID"

# -----------------------------------------------------------------
# Claude Code 워크플로우 프롬프트 (Phase 1-4 내용)
# - 이 변수는 개별 Sub Issue를 처리하는 Claude Agent에게 전달됩니다.
# -----------------------------------------------------------------
# 🚨 이중 따옴표(")와 역슬래시(\) 처리에 유의하여 정의
CLAUDE_WORKFLOW_PROMPT="
# Claude Code 에이전트 실행 워크플로우
linear mcp's team = 100products, project name = Coffeechat
---
### # Phase 1. Add Context & System Lock Management (맥락 및 시스템 잠금 관리)

**Lock의 목적**: 동시 작업으로 인한 혼란 방지 및 순서 보장 (충돌 완전 방지가 아님, 시간차 충돌은 integrate.sh에서 해결)

1. Issue 정보 로딩: 현재 Git Branch 정보(\$BRANCH_NAME)와 연결된 Linear Issue (\$ISSUE_ID)를 로드한다.
2. 잠재적 동시 작업 영역 식별 및 Lock 레이블 생성: Sub Issue의 구현 계획을 분석하여 공유 자원(파일)을 수정해야 하는지 평가한다. 수정이 필요하다면 해당 자원을 명시하는 레이블(예: 'Lock: app.py', 'Lock: email_utils.py')을 생성하거나 재사용한다.
3. 병렬 진행 확인 및 Lock 설정:
   - 동일한 Lock 레이블을 가진 다른 Sub Issue 중 'In Progress' 상태인 이슈가 있는지 Linear API를 통해 확인한다.
   - 발견 시 (Lock 발생): 현재 이슈의 상태를 'BLOCKED'로 변경한다. comment에 "동시 작업 방지를 위해 대기 중. Lock 소유 이슈: [이슈 ID]"를 기록하고, 다음 로직을 **종료**한다.
   - 발견하지 못할 시 (Lock 획득): 현재 이슈에 해당 Lock 레이블을 즉시 적용한다. 'BLOCKED' 상태였을 경우, 상태를 'In Progress'로 변경하고 다음 단계(Phase 2)를 진행한다.

---
### # Phase 2. Implementation Planning (구현 계획 수립)
1. 구현 계획 수립: 주어진 맥락과 코드베이스를 읽어서 영향을 받는 파일 목록과 핵심 로직 변경 요약을 포함하는 구체적인 구현 계획을 세운다.

---
### # Phase 3. Solve Issue (구현 및 검토)
1. 코드 구현: Phase 2에서 수립된 계획에 따라 코드를 작성하고 기능을 구현한다. <solve issue>
2. 자체 검토: Claude Code가 자체적으로 코드 리뷰를 수행하고, 구현된 코드가 기능적/인터페이스적 정합성을 위반하지 않는지 검토한다.
3. 테스트 작성: 기본적인 기능 테스트를 작성하여 구현이 올바르게 동작하는지 검증한다.

---
### # Phase 4. Issue Management & Lock Release (이슈 관리 및 잠금 해제)
1. 구현에 성공했을 경우:
   - Git: **commit 및 push 수행** (Sub 브랜치는 백업 및 공유를 위해 push)
   - status = 'In Review'로 변경한다.
   - comment에 구현 내용을 간결하게 요약하고, 통합 과정 중 발생한 충돌 해결 내역을 명시한다.
   - Lock 해제 명령 (필수): Phase 1에서 사용된 모든 Lock 레이블을 이슈에서 **즉시 제거(Remove Label)**한다.
   - comment에 "Sub 브랜치 구현 완료, Parent 브랜치에서 통합 대기 중" 문구 추가
2. 구현에 실패했을 경우:
   - status = 'To Do'로 변경한다.
   - Lock 유지: Phase 1에서 적용된 Lock 레이블은 유지한다.
   - comment에 상세한 실패 분석 보고서를 작성하고, 'failed' 레이블을 추가한다.
"

if [ -z "$PARENT_ID" ]; then
    echo "사용법: $0 <Parent_Issue_ID>"
    exit 1
fi

# -----------------------------------------------------------------
# 1. Claude Main Agent를 통해 Tmux 실행 명령 목록을 생성 (Linear MCP 활용)
# -----------------------------------------------------------------
echo "🏗️ Claude Main Agent를 통해 Linear 이슈 데이터 처리 중..."

# Tmux 명령에 포함될 Claude Code 실행 명령 인코딩
# (Bash 문자열 내에서 복잡한 따옴표 처리와 이스케이프를 위해 별도 변수화)
ENCODED_CLAUDE_PROMPT=$(echo "$CLAUDE_WORKFLOW_PROMPT" | sed 's/"/\\"/g')

# Main Agent에게 데이터 처리 및 Tmux 명령 목록 생성을 지시하는 프롬프트
DATA_PROCESSING_PROMPT="Linear MCP를 사용하여 다음 작업을 수행하라:

1. Parent Issue '$PARENT_ID'의 정보를 가져와 title을 kebab-case로 변환
2. Sub Issue 목록을 가져와 우선순위 순으로 정렬
3. 각 Sub Issue의 ID와 title을 가져오고, title을 kebab-case로 변환 (소문자, 공백/특수문자는 하이픈으로 치환)

출력 형식:
- **첫 번째 줄**: Parent 브랜치 생성 명령
  git checkout main && git pull && git checkout -b feature/[PARENT_ID]-[parent-kebab-title] && echo 'Parent 브랜치 생성 완료: feature/[PARENT_ID]-[parent-kebab-title]'

- **이후 줄들**: Sub Issue 브랜치 생성 및 작업 명령 (자동 재시도 포함)
  - 브랜치 형식: feature/[ID]-[kebab-case-title]
  - 우선순위 상위 $MAX_CONCURRENT개:
    while true; do git checkout main && git pull && git checkout -b feature/[ID]-[kebab-case-title] 2>/dev/null || git checkout feature/[ID]-[kebab-case-title]; claude \"Issue [ID]를 해결해줘. Branch: feature/[ID]-[kebab-case-title]. $ENCODED_CLAUDE_PROMPT\"; EXIT_CODE=\$?; if [ \$EXIT_CODE -eq 0 ]; then echo '✅ Issue [ID] 완료'; break; else echo '⏳ BLOCKED - 30초 후 자동 재시도...'; sleep 30; fi; done

  - 나머지:
    echo 'Issue [ID] 대기 중. 시작하려면 엔터: ' && read -r && while true; do git checkout main && git pull && git checkout -b feature/[ID]-[kebab-case-title] 2>/dev/null || git checkout feature/[ID]-[kebab-case-title]; claude \"Issue [ID]를 해결해줘. Branch: feature/[ID]-[kebab-case-title]. $ENCODED_CLAUDE_PROMPT\"; EXIT_CODE=\$?; if [ \$EXIT_CODE -eq 0 ]; then echo '✅ Issue [ID] 완료'; break; else echo '⏳ BLOCKED - 30초 후 자동 재시도...'; sleep 30; fi; done
"

# Claude를 실행하고 출력된 명령들을 변수에 저장
COMMANDS=$(claude -p "$DATA_PROCESSING_PROMPT")

if [ -z "$COMMANDS" ]; then
    echo "⚠️ Sub Issue를 찾지 못했거나 Claude의 응답이 없습니다. 스크립트를 종료합니다."
    exit 0
fi

# -----------------------------------------------------------------
# 2. Tmux 환경 설정 및 명령 실행 (Bash의 역할)
# -----------------------------------------------------------------
echo "🛠️ Git 환경 설정 및 Tmux 세션 등록 시작..."

# 기존 세션 정리
tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null && tmux kill-session -t "$TMUX_SESSION_NAME"
# 새 Tmux 세션 시작
tmux new-session -d -s "$TMUX_SESSION_NAME"

# 명령 라인들을 배열로 변환
IFS=$'\n' read -r -d '' -a EXEC_CMDS <<< "$COMMANDS"

for i in "${!EXEC_CMDS[@]}"; do
    CMD=${EXEC_CMDS[i]}
    
    # Git 명령과 Claude 명령이 모두 포함된 CMD를 Tmux에 전달
    if [ "$i" -eq 0 ]; then
        # 첫 번째 명령은 기본 패인에서 실행
        tmux send-keys -t "$TMUX_SESSION_NAME" "$CMD" C-m
    else
        # 나머지 명령은 새 패인에서 실행
        tmux split-window -t "$TMUX_SESSION_NAME" -d -c "$PWD"
        tmux send-keys -t "$TMUX_SESSION_NAME" "$CMD" C-m
    fi
done

echo "
===================================================================
✅ Claude Parallel Runner 준비 완료
===================================================================
세션 이름: $TMUX_SESSION_NAME
접속 명령: tmux attach -t $TMUX_SESSION_NAME

- 우선순위 상위 4개는 자동으로 작업을 시작했습니다.
- 나머지 작업은 해당 패인에서 엔터를 누르면 시작됩니다.
"
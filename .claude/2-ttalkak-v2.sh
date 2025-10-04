#!/bin/bash

# =================================================================
# 설정 변수 및 명령어 정의
# =================================================================
PARENT_ID="$1"
BASE_BRANCH="${2:-main}"  # 두 번째 인자로 base 브랜치 지정, 기본값은 main
MAX_CONCURRENT=4
TMUX_SESSION_NAME="Claude-Worker-$PARENT_ID"

# 프로젝트 루트 디렉토리로 이동
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# .env 파일에서 LINEAR_API_KEY 로드
if [ -f .env.prod ]; then
    set -a
    source .env.prod
    set +a
elif [ -f .env.dev ]; then
    set -a
    source .env.dev
    set +a
fi

if [ -z "$LINEAR_API_KEY" ]; then
    echo "❌ LINEAR_API_KEY가 .env.prod 또는 .env.dev 파일에 설정되지 않았습니다."
    echo "현재 디렉토리: $(pwd)"
    echo ".env 파일 존재 여부:"
    ls -la .env* 2>/dev/null || echo "  .env 파일 없음"
    exit 1
fi

# GitHub 레포지토리 정보 추출
REPO_URL=$(git remote get-url origin 2>/dev/null)
GITHUB_REPO=$(echo "$REPO_URL" | sed -E 's/.*github\.com[\/:](.+)(\.git)?$/\1/' | sed 's/\.git$//')

# -----------------------------------------------------------------
# Claude Code 워크플로우 프롬프트
# -----------------------------------------------------------------
read -r -d '' CLAUDE_WORKFLOW_PROMPT <<'EOF'
# Claude Code 에이전트 실행 워크플로우
linear mcp's team = 100products, project name = Coffeechat
GitHub Repository = ${GITHUB_REPO}
---
### # Phase 1. Add Context & System Lock Management (맥락 및 시스템 잠금 관리)

**Lock의 목적**: 동시 작업으로 인한 혼란 방지 및 순서 보장 (충돌 완전 방지가 아님, 시간차 충돌은 integrate.sh에서 해결)

1. Issue 정보 로딩: 현재 Git Branch 정보($BRANCH_NAME)와 연결된 Linear Issue ($ISSUE_ID)를 로드한다.
2. 잠재적 동시 작업 영역 식별 및 Lock 레이블 생성: Sub Issue의 구현 계획을 분석하여 공유 자원(파일)을 수정해야 하는지 평가한다. 수정이 필요하다면 해당 자원을 명시하는 레이블(예: 'Lock: app.py', 'Lock: email_utils.py')을 생성하거나 재사용한다.
3. 병렬 진행 확인 및 Lock 설정:
   - 동일한 Lock 레이블을 가진 다른 Sub Issue 중 'In Progress' 상태인 이슈가 있는지 Linear API를 통해 확인한다.
   - 발견 시 (Lock 발생): 현재 이슈의 상태를 'BLOCKED'로 변경한다. comment에 "동시 작업 방지를 위해 대기 중. Lock 소유 이슈: {이슈 ID}"를 기록하고, 다음 로직을 **종료**한다.
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
EOF

# GITHUB_REPO 변수 치환
CLAUDE_WORKFLOW_PROMPT="${CLAUDE_WORKFLOW_PROMPT//\$\{GITHUB_REPO\}/$GITHUB_REPO}"

if [ -z "$PARENT_ID" ]; then
    echo "사용법: $0 <Parent_Issue_ID> [Base_Branch]"
    echo "예시:"
    echo "  $0 100P-123                                    # main 브랜치 기준"
    echo "  $0 100P-123 feature/workflow-automation-docs  # 특정 브랜치 기준"
    exit 1
fi

# Base 브랜치 존재 확인
if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
    echo "❌ Base 브랜치 '$BASE_BRANCH'가 존재하지 않습니다."
    exit 1
fi

# -----------------------------------------------------------------
# 1. Linear GraphQL API 직접 호출 (Bash에서 처리)
# -----------------------------------------------------------------
echo "🏗️ Linear API에서 이슈 데이터 가져오는 중..."

# 워크플로우 프롬프트를 임시 파일에 저장
WORKFLOW_FILE="/tmp/ttalkak-workflow-${PARENT_ID}.txt"
echo "$CLAUDE_WORKFLOW_PROMPT" > "$WORKFLOW_FILE"
trap "rm -f $WORKFLOW_FILE" EXIT

# Linear API 호출
RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  --data "{\"query\":\"query{issue(id:\\\"$PARENT_ID\\\"){id title children{nodes{id identifier title priority state{name}}}}}\"}")

# 에러 확인
if echo "$RESPONSE" | grep -q "errors"; then
    echo "❌ Linear API 호출 실패:"
    echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
    exit 1
fi

# jq 있는지 확인
if ! command -v jq &> /dev/null; then
    echo "❌ jq가 설치되지 않았습니다. brew install jq로 설치하세요."
    exit 1
fi

# Parent title 추출 및 kebab-case 변환 (한글 제거, 영문/숫자만)
PARENT_TITLE=$(echo "$RESPONSE" | jq -r '.data.issue.title' | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
# 제목이 비어있으면 parent로 대체
if [ -z "$PARENT_TITLE" ] || [ "$PARENT_TITLE" = "-" ]; then
    PARENT_TITLE="parent"
fi

# Parent 브랜치 생성 명령 (지정된 base 브랜치 기준)
COMMANDS="git stash push -m 'ttalkak-auto-stash' && git checkout $BASE_BRANCH && git pull && git checkout -b feature/$PARENT_ID-$PARENT_TITLE && echo 'Parent 브랜치 생성 완료: feature/$PARENT_ID-$PARENT_TITLE (base: $BASE_BRANCH)'"

# Sub Issue 목록 추출 및 정렬 (priority 낮은 숫자 = 높은 우선순위)
SUB_ISSUES=$(echo "$RESPONSE" | jq -r '.data.issue.children.nodes | sort_by(.priority) | .[] | "\(.identifier)|\(.title)|\(.priority)"')

# 각 Sub Issue의 상세 정보를 파일로 저장
mkdir -p /tmp/ttalkak-issues-${PARENT_ID}
echo "$RESPONSE" | jq -r '.data.issue.children.nodes[] | "\(.identifier)\n\(.title)\n\(.description // "설명 없음")\n---"' > /tmp/ttalkak-issues-${PARENT_ID}/all-issues.txt

if [ -z "$SUB_ISSUES" ]; then
    echo "⚠️ Sub Issue가 없습니다."
    exit 0
fi

# Sub Issue 명령 생성
COUNT=0
while IFS='|' read -r ID TITLE PRIORITY; do
    # kebab-case 변환 (한글 제거, 영문/숫자만)
    KEBAB_TITLE=$(echo "$TITLE" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
    # 제목이 비어있으면 issue-N으로 대체
    if [ -z "$KEBAB_TITLE" ] || [ "$KEBAB_TITLE" = "-" ]; then
        KEBAB_TITLE="issue-$COUNT"
    fi

    # 각 Sub Issue 정보를 Linear API에서 가져와 임시 파일에 저장
    ISSUE_FILE="/tmp/ttalkak-issues-${PARENT_ID}/${ID}.txt"
    curl -s -X POST https://api.linear.app/graphql \
      -H "Authorization: $LINEAR_API_KEY" \
      -H "Content-Type: application/json" \
      --data "{\"query\":\"query{issue(id:\\\"$ID\\\"){id identifier title description}}\"}" | \
      jq -r '.data.issue | "Issue ID: \(.identifier)\nTitle: \(.title)\nDescription:\n\(.description // "설명 없음")"' > "$ISSUE_FILE"

    if [ $COUNT -lt $MAX_CONCURRENT ]; then
        # 우선순위 상위: 자동 시작 (base 브랜치 기준)
        COMMANDS="$COMMANDS
while true; do git stash push -m 'ttalkak-auto-stash' 2>/dev/null; git checkout $BASE_BRANCH && git pull && git checkout -b feature/$ID-$KEBAB_TITLE 2>/dev/null || git checkout feature/$ID-$KEBAB_TITLE; ISSUE_CONTENT=\$(cat $ISSUE_FILE); claude \"\$ISSUE_CONTENT. Branch: feature/$ID-$KEBAB_TITLE. \$(cat $WORKFLOW_FILE)\"; EXIT_CODE=\$?; if [ \$EXIT_CODE -eq 0 ]; then echo '✅ Issue $ID 완료'; break; else echo '⏳ BLOCKED - 30초 후 자동 재시도...'; sleep 30; fi; done"
    else
        # 나머지: 대기 (base 브랜치 기준)
        COMMANDS="$COMMANDS
echo 'Issue $ID 대기 중. 시작하려면 엔터: ' && read -r && while true; do git stash push -m 'ttalkak-auto-stash' 2>/dev/null; git checkout $BASE_BRANCH && git pull && git checkout -b feature/$ID-$KEBAB_TITLE 2>/dev/null || git checkout feature/$ID-$KEBAB_TITLE; ISSUE_CONTENT=\$(cat $ISSUE_FILE); claude \"\$ISSUE_CONTENT. Branch: feature/$ID-$KEBAB_TITLE. \$(cat $WORKFLOW_FILE)\"; EXIT_CODE=\$?; if [ \$EXIT_CODE -eq 0 ]; then echo '✅ Issue $ID 완료'; break; else echo '⏳ BLOCKED - 30초 후 자동 재시도...'; sleep 30; fi; done"
    fi

    COUNT=$((COUNT + 1))
done <<< "$SUB_ISSUES"

# -----------------------------------------------------------------
# 2. Tmux 환경 설정 및 명령 실행
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
        # 첫 번째 명령은 기본 윈도우에서 실행
        tmux send-keys -t "$TMUX_SESSION_NAME" -- "$CMD" C-m
    else
        # 나머지 명령은 새 윈도우에서 실행
        tmux new-window -t "$TMUX_SESSION_NAME" -c "$PWD"
        tmux send-keys -t "$TMUX_SESSION_NAME" -- "$CMD" C-m
    fi
done

echo "
===================================================================
✅ Claude Parallel Runner 준비 완료
===================================================================
Base Branch: $BASE_BRANCH
세션 이름: $TMUX_SESSION_NAME
접속 명령: tmux attach -t $TMUX_SESSION_NAME

- Parent 및 Sub 브랜치는 모두 '$BASE_BRANCH'에서 분기합니다.
- 우선순위 상위 $MAX_CONCURRENT개는 자동으로 작업을 시작했습니다.
- 나머지 작업은 해당 윈도우에서 엔터를 누르면 시작됩니다.
- 윈도우 이동: Ctrl+b, n (다음) / Ctrl+b, p (이전) / Ctrl+b, w (목록)
"

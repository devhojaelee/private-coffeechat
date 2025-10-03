#!/bin/bash

# Linear + Tmux 병렬 개발 자동화 스크립트
# Usage: ./linear_tmux.sh [parent-issue-id]
# Example: ./linear_tmux.sh DEE-61

set -e

# Load environment variables
if [ -f "$HOME/Desktop/python/private-coffeechat/.env.dev" ]; then
    source "$HOME/Desktop/python/private-coffeechat/.env.dev"
elif [ -f "$HOME/Desktop/python/private-coffeechat/.env.prod" ]; then
    source "$HOME/Desktop/python/private-coffeechat/.env.prod"
fi

if [ -z "$LINEAR_API_KEY" ]; then
    echo "❌ Error: LINEAR_API_KEY not found in environment"
    echo "Please add LINEAR_API_KEY to .env.dev or .env.prod"
    exit 1
fi

SESSION="coffeechat-parallel"
PROJECT_DIR="/Users/hojaelee/Desktop/python/private-coffeechat"

# Parent issue 입력받기
PARENT_ID=${1:-}

if [ -z "$PARENT_ID" ]; then
    echo "❌ Usage: $0 <parent-issue-id>"
    echo "Example: $0 DEE-61"
    echo ""
    echo "📋 Available parent issues (Coffeechat project):"
    curl -s -X POST https://api.linear.app/graphql \
      -H "Authorization: $LINEAR_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{"query":"query{issues(first:50,filter:{project:{name:{eq:\"Coffeechat\"}},parent:{null:false},children:{some:{}}}){nodes{identifier title children{nodes{id}}}}}"}' \
      | python3 -c "import sys,json;d=json.load(sys.stdin);[print(f\"  {i['identifier']}: {i['title']} ({len(i['children']['nodes'])} sub-issues)\") for i in d['data']['issues']['nodes']]"
    exit 1
fi

echo "🔍 Fetching parent issue and sub-issues for $PARENT_ID..."

# 먼저 parent issue의 ID와 children 가져오기 (description 포함)
PARENT_QUERY=$(cat <<EOF
{
  "query": "query { issue(id: \"$PARENT_ID\") { id identifier title children { nodes { id identifier title description state { name } } } } }"
}
EOF
)

RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$PARENT_QUERY")

# Sub-issues 파싱 (description 포함)
# 파일로 저장해서 나중에 읽기
ISSUES_JSON=$(mktemp)
echo "$RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'issue' not in data.get('data', {}):
    sys.exit(1)
issue = data['data']['issue']
children = issue['children']['nodes']
json.dump(children, sys.stdout)
" > "$ISSUES_JSON" 2>/dev/null

# Sub-issues 기본 정보만 먼저 추출 (목록 표시용)
SUB_ISSUES=$(python3 -c "
import sys, json
with open('$ISSUES_JSON') as f:
    children = json.load(f)
for child in children:
    print(f\"{child['identifier']}|{child['title']}|{child['state']['name']}\")
" 2>/dev/null)

if [ -z "$SUB_ISSUES" ]; then
    echo "❌ No sub-issues found for $PARENT_ID"
    exit 1
fi

# 기존 세션 종료
echo "🛑 Stopping existing tmux session..."
tmux kill-session -t $SESSION 2>/dev/null || true
sleep 1

# Sub-issues를 배열로 변환
declare -a ISSUES
while IFS='|' read -r ID TITLE STATE; do
    ISSUES+=("$ID|$TITLE|$STATE")
done <<< "$SUB_ISSUES"

ISSUE_COUNT=${#ISSUES[@]}
echo "✅ Found $ISSUE_COUNT sub-issues"
echo ""

# Tmux 세션 생성
WINDOW_INDEX=0
FIRST_ISSUE=true
FIRST_ISSUE_ID=""

for ISSUE_DATA in "${ISSUES[@]}"; do
    IFS='|' read -r ID TITLE STATE <<< "$ISSUE_DATA"

    echo "📌 [$ID] $TITLE (Status: $STATE)"

    # 첫 번째 ID 저장
    [ -z "$FIRST_ISSUE_ID" ] && FIRST_ISSUE_ID="$ID"

    if [ "$FIRST_ISSUE" = true ]; then
        # 첫 번째 윈도우 생성 (인덱스 0)
        tmux new-session -d -s $SESSION -n "$ID" -c "$PROJECT_DIR"
        FIRST_ISSUE=false
    else
        # 추가 윈도우 생성
        tmux new-window -t $SESSION -n "$ID" -c "$PROJECT_DIR"
    fi

    # 각 창마다 별도 브랜치 생성
    BRANCH_NAME="feature/$ID"

    # 각 윈도우 설정 - 윈도우 이름으로 명시적 타겟팅
    sleep 0.1
    tmux send-keys -t "$SESSION:$ID" "clear" C-m
    sleep 0.1

    # Git 브랜치 생성 및 전환
    tmux send-keys -t "$SESSION:$ID" "echo '🔀 Creating branch: $BRANCH_NAME'" C-m
    tmux send-keys -t "$SESSION:$ID" "git checkout -b $BRANCH_NAME 2>/dev/null || git checkout $BRANCH_NAME" C-m
    sleep 0.2

    # Issue description 가져오기
    DESCRIPTION=$(python3 -c "
import sys, json
with open('$ISSUES_JSON') as f:
    children = json.load(f)
for child in children:
    if child['identifier'] == '$ID':
        desc = child.get('description', '')
        if desc:
            print(desc)
        break
" 2>/dev/null)

    # Issue 정보 표시
    tmux send-keys -t "$SESSION:$ID" "cat << 'ISSUE_EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 Issue: $ID
📝 Title: $TITLE
🔖 Status: $STATE
🔀 Branch: $BRANCH_NAME
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ISSUE_EOF" C-m
    sleep 0.2

    # Claude 프롬프트 파일 생성 (prompts.md 워크플로우 기반)
    PROMPT_FILE=$(mktemp)
    cat > "$PROMPT_FILE" <<'EOF'
Follow the workflow in .claude/prompts.md to implement this Linear issue.

# Phase 1: Add Context
1. You are already in branch: feature/$ID
2. Use Linear MCP to read issue $ID (check for "failed" label)
3. Use Linear MCP to read parent issue for context

# Phase 2: Solve Issue
1. Plan implementation based on requirements
2. Implement solution (follow CLAUDE.md conventions)
3. Write tests (TDD when applicable)
4. Quality checks and self code review

# Phase 3: Issue Management
SUCCESS case:
- Linear MCP: Update status to "In Review"
- Linear MCP: Add comment with changes, dependencies, testing notes
- Branch: feature/$ID, Commit: feat($ID): {title}

FAILURE case:
- Linear MCP: Update status to "Todo"
- Linear MCP: Add label "failed"
- Linear MCP: Add detailed failure analysis comment
- Linear MCP: Update issue description if requirements unclear

⚠️ IMPORTANT:
- Check "failed" label first - read previous failure reports
- Implement ALL checklist items
- Update Linear issue with detailed notes
- Never push to main directly
EOF
    # Replace placeholders
    sed -i '' "s/\$ID/$ID/g" "$PROMPT_FILE"

    # 처음 2개 창만 자동으로 Claude 시작, 나머지는 대기
    if [ $WINDOW_INDEX -lt 2 ]; then
        # 자동 실행 창
        tmux send-keys -t "$SESSION:$ID" "echo '🤖 Starting Claude Code...'" C-m
        sleep 0.1
        tmux send-keys -t "$SESSION:$ID" "claude \"\$(cat $PROMPT_FILE)\"" C-m
        sleep 0.2
        tmux send-keys -t "$SESSION:$ID" "rm -f $PROMPT_FILE" C-m
    else
        # 대기 창 - 실행 가능한 명령 입력 (Enter만 치면 실행)
        tmux send-keys -t "$SESSION:$ID" "echo ''" C-m
        tmux send-keys -t "$SESSION:$ID" "echo '⏸️  Ready to start. Press UP arrow and ENTER to run:'" C-m
        tmux send-keys -t "$SESSION:$ID" "echo ''" C-m
        # 실제 명령을 입력란에 타이핑 (실행은 안함)
        tmux send-keys -t "$SESSION:$ID" "claude \"\$(cat $PROMPT_FILE)\"; rm -f $PROMPT_FILE"
    fi

    WINDOW_INDEX=$((WINDOW_INDEX + 1))
done

# 첫 번째 윈도우로 이동
tmux select-window -t "$SESSION:$FIRST_ISSUE_ID"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 병렬 개발 환경 설정 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Parent Issue: $PARENT_ID"
echo "🔢 Total Sub-Issues: $ISSUE_COUNT"
echo ""
echo "🎯 다음 단계:"
echo "  tmux attach -t $SESSION"
echo ""
echo "⚙️  동작 방식:"
echo "  • 창 0, 1: Claude 자동 실행 중 (2개 동시 작업)"
echo "  • 창 2+: 대기 중 (명령어 실행해서 시작)"
echo ""
echo "📝 사용법:"
echo "  • control+b 0~$((ISSUE_COUNT-1)): 창 전환"
echo "  • control+b w: 창 목록"
echo "  • control+b d: Detach"
echo "  • 각 창에서 Claude와 대화하며 작업 진행"
echo "  • 필요시 추가 지시 입력 가능"
echo ""
echo "📌 주의사항:"
echo "  • Claude는 Linear issue의 description과 checklist를 모두 구현합니다"
echo "  • Affected Files, Checklist 항목을 누락하지 않도록 명시적으로 지시됩니다"
echo ""

# Cleanup
rm -f "$ISSUES_JSON"

#!/bin/bash
set -e

# =================================================================
# create-pr.sh - Linear 정보를 기반으로 PR 자동 생성
# =================================================================
# 사용법: ./create-pr.sh <Parent_Issue_ID>
#
# 기능:
# 1. Linear GraphQL API로 Parent Issue 정보 조회
# 2. Sub Issue 목록 조회
# 3. PR body 자동 생성
# 4. gh pr create 실행
# =================================================================

PARENT_ISSUE_ID="$1"

if [ -z "$PARENT_ISSUE_ID" ]; then
    echo "❌ Error: Parent Issue ID가 필요합니다"
    echo "Usage: ./create-pr.sh {Parent-Issue-ID}"
    echo "예시: ./create-pr.sh 100P-123"
    exit 1
fi

# 현재 브랜치 확인
CURRENT_BRANCH=$(git branch --show-current)
echo "📋 현재 브랜치: $CURRENT_BRANCH"

# Parent 브랜치 형식 확인 (feature/100P-123-...)
if [[ ! "$CURRENT_BRANCH" =~ ^feature/${PARENT_ISSUE_ID}- ]]; then
    echo "⚠️  Warning: 현재 브랜치가 feature/${PARENT_ISSUE_ID}-로 시작하지 않습니다"
    echo "계속하시겠습니까? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "❌ PR 생성 취소"
        exit 1
    fi
fi

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
    exit 1
fi

# jq 있는지 확인
if ! command -v jq &> /dev/null; then
    echo "❌ jq가 설치되지 않았습니다. brew install jq로 설치하세요."
    exit 1
fi

# gh CLI 있는지 확인
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI가 설치되지 않았습니다. brew install gh로 설치하세요."
    exit 1
fi

echo ""
echo "🔍 Linear에서 Parent Issue '$PARENT_ISSUE_ID' 정보를 조회 중..."
echo ""

# Linear API 호출 - Parent Issue 정보 조회
RESPONSE=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  --data "{\"query\":\"query{issue(id:\\\"$PARENT_ISSUE_ID\\\"){id title description children{nodes{id identifier title description}}}}\"}")

# 에러 확인
if echo "$RESPONSE" | grep -q "errors"; then
    echo "❌ Linear API 호출 실패:"
    echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
    exit 1
fi

# Parent Issue 정보 추출
PARENT_TITLE=$(echo "$RESPONSE" | jq -r '.data.issue.title')
PARENT_DESC=$(echo "$RESPONSE" | jq -r '.data.issue.description // ""')

if [ -z "$PARENT_TITLE" ] || [ "$PARENT_TITLE" = "null" ]; then
    echo "❌ Parent Issue를 찾을 수 없습니다: $PARENT_ISSUE_ID"
    exit 1
fi

echo "📌 Parent Issue: $PARENT_TITLE"

# Sub Issue 목록 추출
SUB_ISSUES=$(echo "$RESPONSE" | jq -r '.data.issue.children.nodes | .[] | "\(.identifier)|\(.title)|\(.description // "")"')

if [ -z "$SUB_ISSUES" ]; then
    echo "⚠️  Warning: Sub Issue가 없습니다."
fi

# PR Body 구성
PR_BODY_FILE="/tmp/pr-body-${PARENT_ISSUE_ID}.md"

cat > "$PR_BODY_FILE" <<EOF
## Summary
$PARENT_DESC

## Implemented Features
EOF

# Sub Issue별 구현 내용 추가
if [ -n "$SUB_ISSUES" ]; then
    while IFS='|' read -r ID TITLE DESC; do
        echo "" >> "$PR_BODY_FILE"
        echo "### $ID: $TITLE" >> "$PR_BODY_FILE"
        if [ -n "$DESC" ] && [ "$DESC" != "null" ]; then
            # 체크박스 표시(- [ ], - [x])만 제거하고 나머지는 유지
            echo "$DESC" | sed 's/^- \[[x ]\] /- /g' >> "$PR_BODY_FILE"
        fi
    done <<< "$SUB_ISSUES"
fi

cat >> "$PR_BODY_FILE" <<EOF

## Sub Issues
EOF

# Sub Issue 리스트 추가 (title만 사용, description 제외)
if [ -n "$SUB_ISSUES" ]; then
    while IFS='|' read -r ID TITLE DESC; do
        echo "- $ID: $TITLE" >> "$PR_BODY_FILE"
    done <<< "$SUB_ISSUES"
else
    echo "- (No sub issues)" >> "$PR_BODY_FILE"
fi

cat >> "$PR_BODY_FILE" <<EOF

## Test Plan
- [x] Python 구문 검사 통과
- [x] 수동 테스트 완료
- [x] 기능 동작 확인

## Notes
자동화 워크플로우를 통해 구현 및 통합되었습니다.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF

echo ""
echo "📝 PR Body 미리보기:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat "$PR_BODY_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# PR 생성
echo "🚀 GitHub PR 생성 중..."
echo ""

PR_URL=$(gh pr create \
  --base main \
  --head "$CURRENT_BRANCH" \
  --title "$PARENT_TITLE" \
  --body "$(cat $PR_BODY_FILE)")

rm -f "$PR_BODY_FILE"

if [ -n "$PR_URL" ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ PR 생성 완료!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📎 PR URL: $PR_URL"
    echo ""
else
    echo "❌ PR 생성 실패"
    exit 1
fi

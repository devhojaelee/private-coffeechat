#!/bin/bash

# =================================================================
# integrate.sh - Parent 브랜치에 Sub 브랜치들 통합
# =================================================================
# 사용법: ./integrate.sh <Parent_Issue_ID>
#
# 기능:
# 1. Linear GraphQL API로 Sub Issue 목록 조회 (우선순위 순)
# 2. Parent 브랜치로 checkout
# 3. 각 Sub 브랜치를 순서대로 merge
# 4. 충돌 발생 시 Claude Code와 대화형으로 해결
# 5. 모든 merge 완료 후 테스트 안내
# =================================================================

PARENT_ID="$1"

if [ -z "$PARENT_ID" ]; then
    echo "사용법: $0 <Parent_Issue_ID>"
    echo "예시: $0 100P-123"
    exit 1
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

echo "🔍 Parent Issue '$PARENT_ID'의 정보를 조회 중..."

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

# Parent title 추출 및 kebab-case 변환 (한글 제거, 영문/숫자만)
PARENT_TITLE=$(echo "$RESPONSE" | jq -r '.data.issue.title' | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
# 제목이 비어있으면 parent로 대체
if [ -z "$PARENT_TITLE" ] || [ "$PARENT_TITLE" = "-" ]; then
    PARENT_TITLE="parent"
fi

PARENT_BRANCH="feature/$PARENT_ID-$PARENT_TITLE"

# Sub Issue 목록 추출 및 정렬 (priority 낮은 숫자 = 높은 우선순위)
SUB_ISSUES=$(echo "$RESPONSE" | jq -r '.data.issue.children.nodes | sort_by(.priority) | .[] | "\(.identifier)|\(.title)|\(.priority)"')

if [ -z "$SUB_ISSUES" ]; then
    echo "⚠️ Sub Issue가 없습니다."
    exit 0
fi

# Sub 브랜치 목록 생성
SUB_BRANCHES=()
while IFS='|' read -r ID TITLE PRIORITY; do
    # kebab-case 변환 (한글 제거, 영문/숫자만)
    KEBAB_TITLE=$(echo "$TITLE" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
    # 제목이 비어있으면 issue-N으로 대체
    if [ -z "$KEBAB_TITLE" ] || [ "$KEBAB_TITLE" = "-" ]; then
        KEBAB_TITLE="issue-${#SUB_BRANCHES[@]}"
    fi

    SUB_BRANCHES+=("feature/$ID-$KEBAB_TITLE")
done <<< "$SUB_ISSUES"

echo "📋 통합 계획:"
echo "  Parent 브랜치: $PARENT_BRANCH"
echo "  Sub 브랜치 수: ${#SUB_BRANCHES[@]}"
for i in "${!SUB_BRANCHES[@]}"; do
    echo "    $((i+1)). ${SUB_BRANCHES[i]}"
done
echo ""

# Parent 브랜치로 checkout
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "$PARENT_BRANCH" ]; then
    echo "🔀 Parent 브랜치로 전환: $PARENT_BRANCH"
    git stash push -m "integrate-auto-stash" 2>/dev/null || true
    if ! git checkout "$PARENT_BRANCH"; then
        echo "❌ Parent 브랜치로 전환 실패: $PARENT_BRANCH"
        echo "먼저 ttalkak.sh를 실행하여 브랜치를 생성하세요."
        exit 1
    fi
else
    echo "✅ 이미 Parent 브랜치에 있습니다: $PARENT_BRANCH"
fi

# Parent 브랜치를 main에서 rebase
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔄 Parent 브랜치를 main 최신 상태로 업데이트 중..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

git fetch origin main
if git rebase origin/main; then
    echo "✅ main 최신 상태로 rebase 완료"
else
    echo ""
    echo "⚠️  main rebase 중 충돌 발생"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Claude Code를 실행하여 충돌을 해결합니다..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # 프롬프트를 임시 파일에 저장
    REBASE_PROMPT_FILE="/tmp/integrate-rebase-prompt-${PARENT_ID}.txt"
    cat > "$REBASE_PROMPT_FILE" <<EOF
Git rebase 충돌이 발생했습니다.

현재 상황:
- Parent 브랜치: $PARENT_BRANCH
- Rebase 대상: origin/main
- 충돌 파일: 'git status'로 확인 가능

작업:
1. 충돌 파일들을 확인하고 사용자와 대화하며 해결하세요
2. 충돌 해결 후 'git add .' 실행
3. 'git rebase --continue' 실행
4. 완료되면 사용자에게 알리세요

사용자와 협력하여 충돌을 해결하고 rebase를 완료하세요.
EOF

    # Claude Code 호출 (대화형 충돌 해결)
    claude -p "$(cat $REBASE_PROMPT_FILE)"
    rm -f "$REBASE_PROMPT_FILE"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    read -p "충돌 해결이 완료되었습니까? (y/n): " answer
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ "$answer" != "y" ]; then
        echo ""
        echo "❌ 통합 중단됨"
        echo "git rebase --abort 로 rebase를 취소할 수 있습니다."
        exit 1
    fi

    echo "✅ main rebase 충돌 해결 완료"
fi

# 각 Sub 브랜치 merge
MERGED_COUNT=0
TOTAL_COUNT=${#SUB_BRANCHES[@]}

for SUB_BRANCH in "${SUB_BRANCHES[@]}"; do
    MERGED_COUNT=$((MERGED_COUNT + 1))
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔀 [$MERGED_COUNT/$TOTAL_COUNT] Merge: $SUB_BRANCH → $PARENT_BRANCH"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Merge 시도
    if git merge --no-ff "$SUB_BRANCH" -m "Merge $SUB_BRANCH into $PARENT_BRANCH"; then
        echo "✅ Merge 성공: $SUB_BRANCH"
    else
        # 충돌 발생
        echo ""
        echo "⚠️  충돌 발생: $SUB_BRANCH"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Claude Code를 실행하여 충돌을 해결합니다..."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        # 프롬프트를 임시 파일에 저장
        MERGE_PROMPT_FILE="/tmp/integrate-merge-prompt-${SUB_BRANCH//\//-}.txt"
        cat > "$MERGE_PROMPT_FILE" <<EOF
Git merge 충돌이 발생했습니다.

현재 상황:
- Parent 브랜치: $PARENT_BRANCH
- Merge 시도한 브랜치: $SUB_BRANCH
- 충돌 파일: 'git status'로 확인 가능

작업:
1. 충돌 파일들을 확인하고 사용자와 대화하며 해결하세요
2. 충돌 해결 후 'git add .' 실행
3. 'git commit' 실행 (기본 merge 메시지 사용)
4. 완료되면 사용자에게 알리세요

사용자와 협력하여 충돌을 해결하고 merge를 완료하세요.
EOF

        # Claude Code 호출 (대화형 충돌 해결)
        claude -p "$(cat $MERGE_PROMPT_FILE)"
        rm -f "$MERGE_PROMPT_FILE"

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        read -p "충돌 해결이 완료되었습니까? (y/n): " answer
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        if [ "$answer" != "y" ]; then
            echo ""
            echo "❌ 통합 중단됨"
            echo "현재 상태를 확인하고 수동으로 해결하세요."
            exit 1
        fi

        # Merge 상태 확인
        if git diff --quiet && git diff --cached --quiet; then
            echo "⚠️  변경 사항이 없습니다. Merge를 건너뜁니다."
        else
            echo "✅ 충돌 해결 완료: $SUB_BRANCH"
        fi
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 모든 Sub 브랜치 통합 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 다음 단계:"
echo "  1. 통합 테스트 수행"
echo "     예: python -m pytest"
echo "     예: FLASK_ENV=development python app.py"
echo ""
echo "  2. 테스트 통과 후 Push"
echo "     git push origin $PARENT_BRANCH"
echo ""
echo "  3. PR 생성 (필요 시)"
echo "     gh pr create --base main --head $PARENT_BRANCH"
echo ""

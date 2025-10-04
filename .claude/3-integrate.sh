#!/bin/bash

# =================================================================
# integrate.sh - Parent 브랜치에 Sub 브랜치들 통합
# =================================================================
# 사용법: ./integrate.sh <Parent_Issue_ID>
#
# 기능:
# 1. Linear MCP로 Sub Issue 목록 조회 (우선순위 순)
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

echo "🔍 Parent Issue '$PARENT_ID'의 정보를 조회 중..."

# Claude에게 Linear MCP로 브랜치 목록 요청
BRANCH_INFO_PROMPT="Linear MCP를 사용하여 다음 작업을 수행하라:

1. Parent Issue '$PARENT_ID'의 title을 가져와 kebab-case로 변환
2. Sub Issue 목록을 우선순위 순으로 정렬
3. 각 Sub Issue의 ID와 title을 kebab-case로 변환

출력 형식 (각 줄에 브랜치명만 출력):
feature/[PARENT_ID]-[parent-kebab-title]
feature/[SUB_ID_1]-[sub-kebab-title-1]
feature/[SUB_ID_2]-[sub-kebab-title-2]
...

예시:
feature/100P-123-email-verification
feature/100P-124-email-send
feature/100P-125-email-verify
"

BRANCHES=$(claude --prompt "$BRANCH_INFO_PROMPT")

if [ -z "$BRANCHES" ]; then
    echo "⚠️  브랜치 정보를 가져오지 못했습니다."
    exit 1
fi

# 브랜치 목록을 배열로 변환
IFS=$'\n' read -r -d '' -a BRANCH_ARRAY <<< "$BRANCHES"

PARENT_BRANCH="${BRANCH_ARRAY[0]}"
SUB_BRANCHES=("${BRANCH_ARRAY[@]:1}")

echo "📋 통합 계획:"
echo "  Parent 브랜치: $PARENT_BRANCH"
echo "  Sub 브랜치 수: ${#SUB_BRANCHES[@]}"
for i in "${!SUB_BRANCHES[@]}"; do
    echo "    $((i+1)). ${SUB_BRANCHES[i]}"
done
echo ""

# Parent 브랜치로 checkout
echo "🔀 Parent 브랜치로 전환: $PARENT_BRANCH"
if ! git checkout "$PARENT_BRANCH" 2>/dev/null; then
    echo "❌ Parent 브랜치가 존재하지 않습니다: $PARENT_BRANCH"
    echo "먼저 ttalkak.sh를 실행하여 브랜치를 생성하세요."
    exit 1
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

    # Claude Code 호출 (대화형 충돌 해결)
    claude --prompt "Git rebase 충돌이 발생했습니다.

현재 상황:
- Parent 브랜치: $PARENT_BRANCH
- Rebase 대상: origin/main
- 충돌 파일: 'git status'로 확인 가능

작업:
1. 충돌 파일들을 확인하고 사용자와 대화하며 해결하세요
2. 충돌 해결 후 'git add .' 실행
3. 'git rebase --continue' 실행
4. 완료되면 사용자에게 알리세요

사용자와 협력하여 충돌을 해결하고 rebase를 완료하세요."

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

        # Claude Code 호출 (대화형 충돌 해결)
        claude --prompt "Git merge 충돌이 발생했습니다.

현재 상황:
- Parent 브랜치: $PARENT_BRANCH
- Merge 시도한 브랜치: $SUB_BRANCH
- 충돌 파일: 'git status'로 확인 가능

작업:
1. 충돌 파일들을 확인하고 사용자와 대화하며 해결하세요
2. 충돌 해결 후 'git add .' 실행
3. 'git commit' 실행 (기본 merge 메시지 사용)
4. 완료되면 사용자에게 알리세요

사용자와 협력하여 충돌을 해결하고 merge를 완료하세요."

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

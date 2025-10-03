#!/bin/bash

# Feature 브랜치들을 임시 통합 브랜치에 병합하여 테스트
# Usage: ./integrate_and_test.sh <parent-issue-id>
# Example: ./integrate_and_test.sh 100P-61

set -e

PARENT_ID=${1:-}
BASE_BRANCH=${2:-main}

if [ -z "$PARENT_ID" ]; then
    echo "❌ Usage: $0 <parent-issue-id> [base-branch]"
    echo "Example: $0 100P-61"
    exit 1
fi

INTEGRATION_BRANCH="integration-$PARENT_ID"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 Integration & Test Workflow"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# feature/ 브랜치 목록 가져오기
echo "🔍 Finding feature branches for $PARENT_ID..."
FEATURE_BRANCHES=$(git branch -a | grep -E "feature/${PARENT_ID%-*}-[0-9]+" | sed 's/remotes\/origin\///' | sed 's/^\s*//' | sort -u)

if [ -z "$FEATURE_BRANCHES" ]; then
    echo "❌ No feature branches found for $PARENT_ID"
    exit 1
fi

echo ""
echo "📋 Found feature branches:"
echo "$FEATURE_BRANCHES" | nl
echo ""

# 통합 브랜치 생성
echo "🔀 Creating integration branch: $INTEGRATION_BRANCH"
git checkout $BASE_BRANCH
git pull origin $BASE_BRANCH
git checkout -b $INTEGRATION_BRANCH 2>/dev/null || git checkout $INTEGRATION_BRANCH

echo ""
echo "🚀 Merging feature branches..."
echo ""

# 각 feature 브랜치 병합
MERGED_COUNT=0
FAILED_BRANCHES=()

while IFS= read -r BRANCH; do
    BRANCH=$(echo "$BRANCH" | xargs)

    if [ -z "$BRANCH" ]; then
        continue
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📌 Merging: $BRANCH"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 원격에서 최신 가져오기
    git fetch origin "$BRANCH" 2>/dev/null || true

    # 병합 시도
    if git merge "origin/$BRANCH" --no-ff -m "Integrate $BRANCH for testing"; then
        echo "✅ Successfully merged: $BRANCH"
        MERGED_COUNT=$((MERGED_COUNT + 1))
    else
        echo "❌ Failed to merge: $BRANCH"
        echo "⚠️  Conflicts detected!"

        # 충돌 파일 표시
        echo ""
        echo "Conflicted files:"
        CONFLICT_FILES=$(git diff --name-only --diff-filter=U)
        echo "$CONFLICT_FILES" | sed 's/^/  - /'
        echo ""

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🛠️  Conflict Resolution Required"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "📝 다음 단계:"
        echo "  1. Claude Code에서 충돌 파일 수정"
        echo "  2. git add <충돌 파일들>"
        echo "  3. git commit -m 'Resolve merge conflicts for $BRANCH'"
        echo "  4. 이 스크립트 재실행: ./integrate_and_test.sh $PARENT_ID"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        # 스크립트 종료
        exit 1
    fi

    echo ""
done <<< "$FEATURE_BRANCHES"

# 병합 결과
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Integration Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Successfully merged: $MERGED_COUNT branches"

if [ ${#FAILED_BRANCHES[@]} -gt 0 ]; then
    echo "⏭️  Skipped: ${#FAILED_BRANCHES[@]} branches"
fi

echo ""
echo "🧪 Integration branch ready: $INTEGRATION_BRANCH"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 Next Steps (Phase 4: Integration & Testing):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1️⃣  Test the integrated features:"
echo "   FLASK_ENV=development python app.py"
echo "   # Manual testing: verify all features work together"
echo "   # Run automated tests if available: pytest / npm test"
echo ""
echo "2️⃣  If tests PASS - merge to $BASE_BRANCH:"
echo "   ./scripts/merge_features.sh $PARENT_ID"
echo ""
echo "3️⃣  If tests FAIL - fix in feature branches:"
echo "   # Identify which feature caused the issue"
echo "   git checkout feature/{issue-id}"
echo "   # Make fixes"
echo "   git add <files>"
echo "   git commit -m 'fix({issue-id}): {description}'"
echo "   git push origin feature/{issue-id}"
echo "   # Update Linear issue with failure notes"
echo "   # Re-run integration: ./integrate_and_test.sh $PARENT_ID"
echo ""
echo "4️⃣  After successful merge to $BASE_BRANCH:"
echo "   # Update all Linear issues to 'Done'"
echo "   # Integration branch will be cleaned up automatically"
echo ""
echo "📚 See .claude/prompts.md for complete workflow details"
echo ""

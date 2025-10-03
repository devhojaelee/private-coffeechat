#!/bin/bash

# Integration 브랜치를 main에 병합하는 스크립트
# 사용 전에 integrate_and_test.sh로 통합 테스트 완료 필수!
# Usage: ./merge_features.sh [parent-issue-id]
# Example: ./merge_features.sh 100P-61

set -e

PARENT_ID=${1:-}
BASE_BRANCH=${2:-main}
INTEGRATION_BRANCH="integration-$PARENT_ID"

if [ -z "$PARENT_ID" ]; then
    echo "❌ Usage: $0 <parent-issue-id> [base-branch]"
    echo "Example: $0 100P-61"
    echo "Example: $0 100P-61 develop"
    exit 1
fi

# Integration 브랜치 존재 확인
if ! git show-ref --verify --quiet "refs/heads/$INTEGRATION_BRANCH"; then
    echo "❌ Integration branch '$INTEGRATION_BRANCH' not found!"
    echo ""
    echo "💡 You need to run integrate_and_test.sh first:"
    echo "   ./scripts/integrate_and_test.sh $PARENT_ID"
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Merging Integration Branch to Main"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Integration branch: $INTEGRATION_BRANCH"
echo "🎯 Target branch: $BASE_BRANCH"
echo ""

# 확인
read -p "🤔 Merge $INTEGRATION_BRANCH into $BASE_BRANCH? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "⏭️  Merge cancelled"
    exit 0
fi

# Base 브랜치로 전환 및 업데이트
echo ""
echo "🔀 Switching to $BASE_BRANCH..."
git checkout $BASE_BRANCH
git pull origin $BASE_BRANCH

# Integration 브랜치 병합
echo ""
echo "🚀 Merging $INTEGRATION_BRANCH..."
echo ""

if git merge "$INTEGRATION_BRANCH" --no-ff -m "Merge $INTEGRATION_BRANCH into $BASE_BRANCH

Integrates all features from parent issue $PARENT_ID"; then
    echo "✅ Successfully merged $INTEGRATION_BRANCH into $BASE_BRANCH"
else
    echo "❌ Failed to merge $INTEGRATION_BRANCH"
    echo "⚠️  Please resolve conflicts manually"
    git merge --abort 2>/dev/null || true
    exit 1
fi

echo ""

# Push 확인
read -p "🚀 Push $BASE_BRANCH to remote? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "📤 Pushing to origin/$BASE_BRANCH..."
    git push origin $BASE_BRANCH
    echo "✅ Push complete!"
else
    echo "⏭️  Push skipped. You can push manually later:"
    echo "   git push origin $BASE_BRANCH"
fi

echo ""

# Integration 브랜치 정리
read -p "🗑️  Delete integration branch $INTEGRATION_BRANCH? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    git branch -D "$INTEGRATION_BRANCH"
    echo "✅ Integration branch deleted"
else
    echo "⏭️  Integration branch kept: $INTEGRATION_BRANCH"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 Merge Process Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 Final Steps:"
echo ""
echo "1️⃣  Update Linear issues to 'Done':"
echo "   - Use Linear MCP to update all sub-issue statuses"
echo "   - Add final completion comments"
echo "   - Close parent issue $PARENT_ID"
echo ""
echo "2️⃣  Clean up feature branches (optional):"
echo "   git branch -D feature/{issue-id}"
echo "   git push origin --delete feature/{issue-id}"
echo ""
echo "3️⃣  Deploy to production (if applicable):"
echo "   # Follow your deployment workflow"
echo ""
echo "📚 See .claude/prompts.md Phase 4 for complete workflow"
echo ""

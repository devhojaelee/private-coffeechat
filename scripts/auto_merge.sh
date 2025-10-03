#!/bin/bash

# 자동 병합 스크립트 (로컬 실행용)
# 사용법: ./scripts/auto_merge.sh 100P-116

set -e  # 에러 발생 시 즉시 종료

PARENT_ID=$1

if [ -z "$PARENT_ID" ]; then
    echo "❌ Usage: ./scripts/auto_merge.sh <PARENT_ISSUE_ID>"
    echo "   Example: ./scripts/auto_merge.sh 100P-116"
    exit 1
fi

echo "🚀 Starting auto merge process for $PARENT_ID"
echo ""

# Step 1: Integration
echo "📦 Step 1: Running integration script..."
./scripts/integrate_and_test.sh "$PARENT_ID"

if [ $? -ne 0 ]; then
    echo "❌ Integration failed. Please resolve conflicts manually."
    exit 1
fi

echo "✅ Integration complete"
echo ""

# Step 2: Run tests
echo "🧪 Step 2: Running tests..."
python -m py_compile app.py email_utils.py calendar_utils.py

if [ -d "tests" ] || ls test_*.py 2>/dev/null | grep -q .; then
    pytest || {
        echo "❌ Tests failed! Aborting merge."
        exit 1
    }
else
    echo "⚠️  No tests found, proceeding with syntax check only"
fi

echo "✅ Tests passed"
echo ""

# Step 3: Confirmation
echo "⚠️  Ready to merge integration-$PARENT_ID → main"
read -p "Continue? (y/N): " confirm

if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "❌ Merge cancelled by user"
    exit 1
fi

# Step 4: Merge to main
echo "🔀 Step 3: Merging to main..."
./scripts/merge_features.sh "$PARENT_ID"

if [ $? -ne 0 ]; then
    echo "❌ Merge to main failed"
    exit 1
fi

echo ""
echo "✅ Complete! All changes merged to main"
echo "📋 Summary:"
echo "   - Integration branch: integration-$PARENT_ID"
echo "   - Target branch: main"
echo "   - Status: Success"

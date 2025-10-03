#!/bin/bash

PROJECT_NAME="coffeechat"
BASE_DIR="../"
SESSION="${PROJECT_NAME}-parallel"

# Tmux 세션 종료
echo "🛑 Stopping tmux session..."
tmux kill-session -t $SESSION 2>/dev/null

# Worktree 목록 확인
echo ""
echo "📋 Current worktrees:"
git worktree list

# Worktree 삭제 (사용자 확인)
echo ""
read -p "🗑️  Remove all worktrees? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    for dir in ${BASE_DIR}${PROJECT_NAME}-*; do
        if [ -d "$dir" ]; then
            echo "Removing: $dir"
            git worktree remove "$dir" --force
        fi
    done
    git worktree prune
    echo "✅ Cleanup complete!"
else
    echo "⏭️  Skipped worktree removal"
fi

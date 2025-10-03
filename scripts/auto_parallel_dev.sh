#!/bin/bash

# 설정
PROJECT_NAME="coffeechat"
BASE_DIR="../"
SESSION="${PROJECT_NAME}-parallel"

# Worktree 설정 (기능명:브랜치명)
declare -A FEATURES=(
    ["progress"]="features/progress-indicator"
    ["email"]="features/email-resend"
    ["session"]="features/session-tracking"
    ["mobile"]="features/mobile-calendar"
)

# 기존 세션 종료
tmux kill-session -t $SESSION 2>/dev/null

# Worktree 생성 및 Tmux 윈도우 생성
WINDOW_INDEX=0
for FEATURE in "${!FEATURES[@]}"; do
    BRANCH="${FEATURES[$FEATURE]}"
    WORKTREE_PATH="${BASE_DIR}${PROJECT_NAME}-${FEATURE}"

    echo "🔧 Creating worktree: $WORKTREE_PATH -> $BRANCH"

    # Worktree 생성 (이미 존재하면 무시)
    git worktree add "$WORKTREE_PATH" "$BRANCH" 2>/dev/null || echo "⚠️  Worktree already exists"

    # Tmux 윈도우 생성
    if [ $WINDOW_INDEX -eq 0 ]; then
        # 첫 번째 윈도우는 세션 생성과 함께
        tmux new-session -d -s $SESSION -n "$FEATURE"
    else
        # 나머지는 윈도우 추가
        tmux new-window -t $SESSION:$WINDOW_INDEX -n "$FEATURE"
    fi

    # 각 윈도우에서 worktree로 이동
    tmux send-keys -t $SESSION:$WINDOW_INDEX "cd $WORKTREE_PATH" C-m
    tmux send-keys -t $SESSION:$WINDOW_INDEX "clear" C-m
    tmux send-keys -t $SESSION:$WINDOW_INDEX "echo '📁 Working on: $BRANCH'" C-m
    tmux send-keys -t $SESSION:$WINDOW_INDEX "git status" C-m

    WINDOW_INDEX=$((WINDOW_INDEX + 1))
done

# 첫 번째 윈도우로 이동
tmux select-window -t $SESSION:0

echo ""
echo "✅ 병렬 개발 환경 설정 완료!"
echo "📊 총 ${#FEATURES[@]}개 작업 환경 생성됨"
echo ""
echo "📌 접속: tmux attach -t $SESSION"
echo "📌 창 전환: Ctrl+b 0-$((${#FEATURES[@]}-1))"
echo "📌 목록: Ctrl+b w"
echo "📌 종료: Ctrl+b d"
echo ""
echo "🗑️  정리: ./cleanup_parallel_dev.sh"

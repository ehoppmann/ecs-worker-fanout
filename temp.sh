#!/usr/bin/env bash
set -euo pipefail

# Squash all commits into the initial commit and reset both dates to now.

INITIAL=$(git rev-list --max-parents=0 HEAD)
NOW=$(date -R)

git reset "$INITIAL"
git add -A
git commit --amend --no-edit \
    --date="$NOW" \
    --reset-author

GIT_COMMITTER_DATE="$NOW" git commit --amend --no-edit

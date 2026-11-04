#!/bin/bash
# Merge the latest WebDriverAgent changes from the appium/appium-ios monorepo
# into the current branch.
#
# Upstream WebDriverAgent moved to appium/appium-ios as packages/webdriveragent
# (appium/appium-ios#76). The monorepo did not keep this repository's commit
# history, so a plain merge is impossible. Instead this script rebuilds the
# history of that folder as the local branch appium-ios-wda, rooted at the
# import commit, and merges it. The rebuild is deterministic: the same monorepo
# history always yields the same commit IDs, so every run only brings in the
# commits that arrived since the previous sync.
#
# Usage: Scripts/sync-from-appium-ios.sh   (with a clean working tree)
#
# Nothing is pushed. If the merge stops on conflicts, resolve them and run
# `git commit`, or run `git merge --abort` to back out.
#
# Limitations:
#   - Expects linear monorepo history since the import (it squash-merges PRs);
#     aborts if a merge commit shows up instead of guessing an order.
#   - Only the folder's contents are synced. CI and tooling that live at the
#     appium-ios root are not.

set -euo pipefail

REMOTE_NAME=appium-ios
REMOTE_URL=https://github.com/appium/appium-ios.git
REMOTE_BRANCH=main
PREFIX=packages/webdriveragent
# Monorepo commit that imported WebDriverAgent (appium/appium-ios#76)
IMPORT_COMMIT=e5886f6f2265f4fc94e5c4c35889f67bd09aad96
SPLIT_BRANCH=appium-ios-wda

cd "$(git rev-parse --show-toplevel)"

current_branch=$(git branch --show-current)
if [ -z "$current_branch" ]; then
  echo "HEAD is detached; check out the branch to sync first." >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "The working tree has uncommitted changes; commit or stash them first." >&2
  exit 1
fi

if ! git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
  git remote add "$REMOTE_NAME" "$REMOTE_URL"
fi
git fetch --no-tags "$REMOTE_NAME" "$REMOTE_BRANCH"
src="$REMOTE_NAME/$REMOTE_BRANCH"

if [ -n "$(git rev-list --merges "$IMPORT_COMMIT..$src")" ]; then
  echo "$src has merge commits since the import; this script only handles linear history." >&2
  exit 1
fi

# Re-create each commit that touched the folder with the folder as its root tree,
# keeping the original author, committer, dates and message
parent=""
for c in $IMPORT_COMMIT $(git rev-list --reverse "$IMPORT_COMMIT..$src" -- "$PREFIX"); do
  tree=$(git rev-parse "$c:$PREFIX")
  export GIT_AUTHOR_NAME="$(git log -1 --format=%an "$c")"
  export GIT_AUTHOR_EMAIL="$(git log -1 --format=%ae "$c")"
  export GIT_AUTHOR_DATE="$(git log -1 --format=%ad --date=raw "$c")"
  export GIT_COMMITTER_NAME="$(git log -1 --format=%cn "$c")"
  export GIT_COMMITTER_EMAIL="$(git log -1 --format=%ce "$c")"
  export GIT_COMMITTER_DATE="$(git log -1 --format=%cd --date=raw "$c")"
  msg="$(git log -1 --format=%B "$c")"
  if [ -z "$parent" ]; then
    root=$(printf '%s\n' "$msg" | git commit-tree "$tree")
    parent=$root
  else
    parent=$(printf '%s\n' "$msg" | git commit-tree "$tree" -p "$parent")
  fi
done
git branch -f "$SPLIT_BRANCH" "$parent"

if [ "$(git rev-parse "$SPLIT_BRANCH^{tree}")" != "$(git rev-parse "$src:$PREFIX")" ]; then
  echo "The rebuilt $SPLIT_BRANCH does not match $src:$PREFIX; not merging." >&2
  exit 1
fi
if ! git merge-base --is-ancestor "$root" HEAD; then
  echo "$current_branch was never connected to the appium-ios history." >&2
  echo "Record the import as merged once, then re-run this script:" >&2
  echo "  git merge -s ours --allow-unrelated-histories $root" >&2
  exit 1
fi

before=$(git rev-parse HEAD)
if ! git merge --no-edit -m "Merge appium/appium-ios $PREFIX into $current_branch" "$SPLIT_BRANCH"; then
  echo "Resolve the conflicts above and run 'git commit', or run 'git merge --abort'." >&2
  exit 1
fi

if [ "$(git rev-parse HEAD)" = "$before" ]; then
  echo "$current_branch already has everything from $src:$PREFIX."
else
  echo "Merged into $current_branch:"
  git log --oneline --no-merges "$before..HEAD"
  echo "Review, test, then push when ready."
fi

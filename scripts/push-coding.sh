#!/usr/bin/env bash
# ============================================================
# push-coding.sh — 把本地分支同步到 coding.jd.com，作者统一改写为 weiyanhai
# ============================================================
# 背景：git 作者身份写进 commit 对象并参与 hash，无法「同一 commit 在不同
# remote 显示不同作者」。因此：
#   - origin (github)      保留原始作者历史（Aniwei），正常 push。
#   - coding (coding.jd.com) 作为「作者全部改写为 weiyanhai」的镜像。
#
# 做法：在独立 bare 克隆里用 git-filter-repo 改写 author+committer，再强推。
# 全程不触碰当前工作区（不检出、不改 index、不动 origin）。
#
# 用法：  scripts/push-coding.sh [branch]
#        默认 branch = 当前分支
# 依赖：  git-filter-repo（brew install git-filter-repo）
# ============================================================

set -euo pipefail

BRANCH="${1:-$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --abbrev-ref HEAD)}"
NAME="weiyanhai"
EMAIL="weiyanhai@jd.com"
CODING_URL="git@coding.jd.com:otto/otto-registry.git"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coding-mirror.XXXXXX")"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

if ! command -v git-filter-repo >/dev/null 2>&1; then
  echo "错误：未找到 git-filter-repo。请先安装：brew install git-filter-repo" >&2
  exit 1
fi

echo "[coding 1/4] bare 克隆本地分支 '$BRANCH'（不检出工作树）…"
git clone --quiet --bare --branch "$BRANCH" --single-branch "file://$REPO_ROOT" "$TMP_DIR/mirror.git"

cd "$TMP_DIR/mirror.git"
COUNT="$(git rev-list --count HEAD)"
echo "[coding 2/4] 改写全部 $COUNT 个提交的作者/提交者为 $NAME <$EMAIL>…"
git filter-repo --force \
  --name-callback "return b\"$NAME\"" \
  --email-callback "return b\"$EMAIL\""

# 校验：改写后不得残留任何其它作者
AUTHORS="$(git log --all --pretty=format:'%an <%ae>' | sort -u)"
if [ "$AUTHORS" != "$NAME <$EMAIL>" ]; then
  echo "错误：改写后仍存在其它作者：" >&2
  echo "$AUTHORS" >&2
  exit 1
fi
echo "         ✓ 全部提交作者已统一为 $NAME <$EMAIL>"

echo "[coding 3/4] 强推到 coding/$BRANCH …"
git remote add coding "$CODING_URL"
git push --force --no-verify coding "HEAD:$BRANCH"

echo "[coding 4/4] 完成。coding/$BRANCH 现为全 $NAME 历史。"
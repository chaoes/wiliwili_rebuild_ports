#!/usr/bin/env bash
# 检查上游新 tag 上，本地补丁是否还能干净打上。
#
#   scripts/merge-upstream.sh v1.7.0
#
# 只做检查与提示，不改仓库、不提交。确认没问题后：
#   1. 改 VERSION
#   2. 在 MERGE_LOG.md 追加记录
#   3. 打 tag 推送触发 build-port
set -euo pipefail

TAG=${1:?用法: scripts/merge-upstream.sh <上游 tag>}
REPO=https://github.com/xfangfang/wiliwili.git
WORK=$(mktemp -d /tmp/wiliwili-merge-XXXXXX)
trap 'rm -rf "$WORK"' EXIT

echo "==> 拉取上游 $TAG"
git clone -q --depth 1 --branch "$TAG" --recurse-submodules --shallow-submodules "$REPO" "$WORK/src"

echo "==> 逐个检查补丁"
failed=0
for p in patches/*.patch; do
  if git -C "$WORK/src" apply --check "$p" 2>"$WORK/err"; then
    git -C "$WORK/src" apply "$p"
    echo "  [ok]   $p"
  else
    echo "  [fail] $p"
    sed 's/^/         /' "$WORK/err"
    failed=$((failed + 1))
  fi
done

echo
if [ "$failed" -eq 0 ]; then
  cat <<EOF
补丁全部可打。接着做：
  1. echo "$TAG" > VERSION
  2. 在 MERGE_LOG.md 追加一条记录（模板见文件末尾）
  3. git commit -am "merge upstream $TAG" && git tag "$TAG" && git push origin main "$TAG"
  4. 等 build-port 出包，上机复测后把结果补进 MERGE_LOG.md
EOF
else
  cat <<EOF
有 $failed 个补丁打不上，需要手动 rebase：
  $WORK/src   (脚本退出时会删除，需要保留请自行重新 clone)
改完把新的补丁丢回 patches/ 再跑一次本脚本。
EOF
  exit 1
fi
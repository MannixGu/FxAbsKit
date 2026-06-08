#!/usr/bin/env bash
# release.sh —— SPM xcframework 一键发布脚本
#
# 用法:
#   scripts/release.sh <zip路径> <版本号> [--notes "release 说明"] [--dry-run]
#
# 例:
#   scripts/release.sh ~/Downloads/abs.xcframework.zip 1.0.1
#   scripts/release.sh ./abs.xcframework.zip 1.1.0 --notes "修复 xxx"
#
# 流程:
#   1. 校验环境 (gh / swift / git 工作区干净)
#   2. swift package compute-checksum
#   3. 复制 zip 为 abs.xcframework_<version>.zip
#   4. 更新 Package.swift 的 url / checksum
#   5. git commit
#   6. git tag <version>
#   7. git push origin <branch> && git push origin <version>
#   8. gh release create <version> 上传 zip

set -euo pipefail

# ---------- 颜色 ----------
RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RESET=$'\033[0m'
# 全部走 stderr: stdout 留给真实数据 (例如 $(git_net ...) 的命令替换)
log()  { printf "%s[release]%s %s\n" "$BLUE"   "$RESET" "$*" >&2; }
ok()   { printf "%s[  ok  ]%s %s\n" "$GREEN"  "$RESET" "$*" >&2; }
warn() { printf "%s[ warn ]%s %s\n" "$YELLOW" "$RESET" "$*" >&2; }
die()  { printf "%s[ fail ]%s %s\n" "$RED"    "$RESET" "$*" >&2; exit 1; }

# ---------- git 网络重试 ----------
# GitHub 偶尔出 "HTTP2 framing layer" 错误，第一次失败时降级到 HTTP/1.1 重试一次。
git_net() {
  if git "$@"; then return 0; fi
  warn "git $* 失败，使用 HTTP/1.1 重试"
  git -c http.version=HTTP/1.1 "$@"
}

# ---------- 失败回滚指引 ----------
# 跟踪每一步状态，脚本意外退出时打印对应的回滚命令，让用户能精准恢复。
DID_COMMIT=0; DID_TAG=0; DID_PUSH_BRANCH=0; DID_PUSH_TAG=0; DID_RELEASE=0

print_recovery() {
  local -a hints=()
  [[ $DID_RELEASE     -eq 1 ]] && hints+=("  删 GitHub release : gh release delete ${VERSION} --repo ${OWNER}/${REPO} --yes")
  [[ $DID_PUSH_TAG    -eq 1 ]] && hints+=("  删远端 tag        : git push origin :refs/tags/${VERSION}")
  [[ $DID_PUSH_BRANCH -eq 1 ]] && hints+=("  回滚远端分支      : git push --force-with-lease origin HEAD~1:${BRANCH}")
  [[ $DID_TAG         -eq 1 ]] && hints+=("  删本地 tag        : git tag -d ${VERSION}")
  [[ $DID_COMMIT      -eq 1 ]] && hints+=("  撤销本地 commit   : git reset --hard HEAD~1")
  if [[ ${#hints[@]} -gt 0 ]]; then
    printf "\n%s[回滚指引]%s 发布中断，按 *从上到下* 的顺序执行以恢复:\n" "$YELLOW" "$RESET" >&2
    printf "%s\n" "${hints[@]}" >&2
    printf "\n" >&2
  fi
}

cleanup() {
  local rc=$?
  [[ -n "${WORK_DIR:-}" ]] && rm -rf "$WORK_DIR"
  [[ $rc -ne 0 ]] && print_recovery
  return $rc
}
trap cleanup EXIT

# ---------- 参数解析 ----------
ZIP_INPUT=""
VERSION=""
NOTES=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --notes)   NOTES="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,20p' "$0"; exit 0 ;;
    -*)
      die "未知参数: $1" ;;
    *)
      if [[ -z "$ZIP_INPUT" ]]; then ZIP_INPUT="$1"
      elif [[ -z "$VERSION" ]];   then VERSION="$1"
      else die "多余参数: $1"; fi
      shift ;;
  esac
done

[[ -n "$ZIP_INPUT" ]] || die "缺少 <zip路径> 参数。用法: $0 <zip> <version>"
[[ -n "$VERSION" ]]   || die "缺少 <版本号> 参数。用法: $0 <zip> <version>"
[[ -f "$ZIP_INPUT" ]] || die "zip 文件不存在: $ZIP_INPUT"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+.][0-9A-Za-z.-]+)?$ ]] \
  || die "版本号格式不合法 (期望 SemVer，如 1.0.1): $VERSION"

# ---------- 切到项目根 ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"
log "项目根目录: $ROOT_DIR"

# ---------- 依赖检查 ----------
command -v gh    >/dev/null 2>&1 || die "未找到 gh CLI，请先安装: brew install gh"
command -v swift >/dev/null 2>&1 || die "未找到 swift"
command -v git   >/dev/null 2>&1 || die "未找到 git"

gh auth status >/dev/null 2>&1 || die "gh 未登录，请先执行: gh auth login"

# ---------- 解析 remote ----------
REMOTE_URL="$(git remote get-url origin)"
# 支持 git@github.com:owner/repo.git 与 https://github.com/owner/repo(.git)
if [[ "$REMOTE_URL" =~ github\.com[:/]+([^/]+)/([^/.]+)(\.git)?$ ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
else
  die "无法从 origin 解析 owner/repo: $REMOTE_URL"
fi
log "GitHub 仓库: ${OWNER}/${REPO}"

# ---------- 工作区检查 ----------
if [[ -n "$(git status --porcelain)" ]]; then
  warn "工作区不干净。脚本只会提交 Package.swift，其它改动请先处理:"
  git status --short
  read -r -p "继续? [y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || die "已取消"
fi

# 已存在 tag 检查
if git rev-parse -q --verify "refs/tags/${VERSION}" >/dev/null; then
  die "本地已存在 tag ${VERSION}，请换版本号或先删除该 tag"
fi
# 显式判错: ls-remote 网络失败不能当作"远端没 tag"误放过去
REMOTE_TAGS="$(git_net ls-remote --tags origin "refs/tags/${VERSION}")" \
  || die "查询远端 tag 失败 (网络问题?)，请稍后重试"
if echo "$REMOTE_TAGS" | grep -q "refs/tags/${VERSION}$"; then
  die "远端已存在 tag ${VERSION}"
fi
if gh release view "${VERSION}" --repo "${OWNER}/${REPO}" >/dev/null 2>&1; then
  die "远端已存在 release ${VERSION}"
fi

# ---------- 准备 zip ----------
ZIP_NAME="abs.xcframework_${VERSION}.zip"
WORK_DIR="$(mktemp -d -t fxabskit-release-XXXX)"
ZIP_PATH="${WORK_DIR}/${ZIP_NAME}"
cp "$ZIP_INPUT" "$ZIP_PATH"
log "zip: $ZIP_PATH"

# ---------- 计算 checksum ----------
CHECKSUM="$(swift package compute-checksum "$ZIP_PATH")"
ok "checksum: $CHECKSUM"

NEW_URL="https://github.com/${OWNER}/${REPO}/releases/download/${VERSION}/${ZIP_NAME}"
log "binaryTarget url: $NEW_URL"

# ---------- 改 Package.swift ----------
PKG="Package.swift"
[[ -f "$PKG" ]] || die "未找到 $PKG"

# 用 python 做严谨替换，匹配 .binaryTarget(...) 块里的 url/checksum
python3 - "$PKG" "$NEW_URL" "$CHECKSUM" <<'PY'
import re, sys, pathlib
path, new_url, new_sum = sys.argv[1], sys.argv[2], sys.argv[3]
src = pathlib.Path(path).read_text(encoding="utf-8")

def sub_block(m):
    block = m.group(0)
    block = re.sub(r'(url:\s*)"[^"]*"',      lambda _m: f'{_m.group(1)}"{new_url}"', block, count=1)
    block = re.sub(r'(checksum:\s*)"[^"]*"', lambda _m: f'{_m.group(1)}"{new_sum}"', block, count=1)
    return block

new_src, n = re.subn(r'\.binaryTarget\([^)]*\)', sub_block, src, flags=re.DOTALL)
if n == 0:
    sys.exit("Package.swift 中未找到 .binaryTarget(...) 块")
pathlib.Path(path).write_text(new_src, encoding="utf-8")
PY
ok "已更新 $PKG"
git --no-pager diff -- "$PKG" || true

# ---------- dry-run 截止 ----------
if [[ "$DRY_RUN" -eq 1 ]]; then
  warn "dry-run 模式，跳过 commit / tag / push / release"
  log "回滚 Package.swift 修改"
  git checkout -- "$PKG"
  exit 0
fi

# ---------- 确认 ----------
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
cat <<EOF

  即将执行:
    - git commit Package.swift  (chore: release ${VERSION})
    - git tag ${VERSION}
    - git push origin ${BRANCH}
    - git push origin ${VERSION}
    - gh release create ${VERSION} (上传 ${ZIP_NAME})

EOF
read -r -p "确认执行? [y/N] " ans
[[ "$ans" =~ ^[yY]$ ]] || { git checkout -- "$PKG"; die "已取消，Package.swift 已回滚"; }

# ---------- commit / tag / push ----------
git add "$PKG"
git commit -m "chore: release ${VERSION}"
DID_COMMIT=1
ok "已 commit"

git tag -a "${VERSION}" -m "Release ${VERSION}"
DID_TAG=1
ok "已打 tag ${VERSION}"

git_net push origin "${BRANCH}" || die "push 分支失败，请按下方回滚指引处理"
DID_PUSH_BRANCH=1
ok "已 push ${BRANCH}"

git_net push origin "${VERSION}" || die "push tag 失败，请按下方回滚指引处理"
DID_PUSH_TAG=1
ok "已 push tag ${VERSION}"

# ---------- gh release ----------
REL_ARGS=( "${VERSION}" "$ZIP_PATH" --repo "${OWNER}/${REPO}" --title "${VERSION}" )
if [[ -n "$NOTES" ]]; then
  REL_ARGS+=( --notes "$NOTES" )
else
  REL_ARGS+=( --generate-notes )
fi

gh release create "${REL_ARGS[@]}" || die "gh release 创建失败，请按下方回滚指引处理"
DID_RELEASE=1
ok "release 已发布: https://github.com/${OWNER}/${REPO}/releases/tag/${VERSION}"

cat <<EOF

完成。SPM 用户可通过以下方式引用:
  .package(url: "https://github.com/${OWNER}/${REPO}.git", from: "${VERSION}")

binaryTarget URL: ${NEW_URL}
checksum:         ${CHECKSUM}
EOF

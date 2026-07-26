#!/usr/bin/env bash
# 将 agents/cookbook 中的 skills 同步到本机 Agent 消费路径。
# 默认符号链接到 ~/.cursor/skills/，便于在仓库内迭代 recipe。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/skills"
CURSOR_SKILLS="${CURSOR_SKILLS_DIR:-$HOME/.cursor/skills}"
CLAUDE_SKILLS="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

DRY_RUN=0
TARGET="cursor"
COPY_MODE=0

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}▶ $*${NC}"; }

usage() {
    cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") <command> [options]

${BOLD}命令:${NC}
  sync      将 cookbook skills 同步到本机 Agent skills 目录
  status    查看已发现的 skills 与本机链接状态
  unlink    移除由本脚本创建的 skills 链接（不删仓库源文件）

${BOLD}选项:${NC}
  --dry-run         只预览，不改动文件系统
  --target <name>   cursor（默认）| claude | all
  --copy            复制目录而非符号链接
  -h, --help        显示帮助

${BOLD}示例:${NC}
  $(basename "$0") sync
  $(basename "$0") sync --dry-run
  $(basename "$0") sync --target all
  $(basename "$0") status
  $(basename "$0") unlink --dry-run

EOF
}

# 从 SKILL.md frontmatter 读取 name；失败则用目录名
_skill_name() {
    local skill_md="$1"
    local skill_dir
    skill_dir="$(dirname "$skill_md")"
    local name=""
    if [[ -f "$skill_md" ]]; then
        name="$(sed -n 's/^name:[[:space:]]*//p' "$skill_md" | head -n 1 | tr -d '\r')"
    fi
    if [[ -z "$name" ]]; then
        name="$(basename "$skill_dir")"
    fi
    printf '%s\n' "$name"
}

# 列出 skills：每行 "name<TAB>abs_dir"
_list_skills() {
    local skill_md skill_dir name
    if [[ ! -d "$SKILLS_SRC" ]]; then
        return 0
    fi
    while IFS= read -r -d '' skill_md; do
        skill_dir="$(cd "$(dirname "$skill_md")" && pwd)"
        name="$(_skill_name "$skill_md")"
        printf '%s\t%s\n' "$name" "$skill_dir"
    done < <(find "$SKILLS_SRC" -type f -name 'SKILL.md' -print0 | sort -z)
}

_dest_dirs_for_target() {
    case "$1" in
        cursor) printf '%s\n' "$CURSOR_SKILLS" ;;
        claude) printf '%s\n' "$CLAUDE_SKILLS" ;;
        all)
            printf '%s\n' "$CURSOR_SKILLS"
            printf '%s\n' "$CLAUDE_SKILLS"
            ;;
        *)
            error "未知 --target: $1（期望 cursor|claude|all）"
            exit 1
            ;;
    esac
}

_is_cookbook_link() {
    local dest="$1"
    local src="$2"
    [[ -L "$dest" ]] || return 1
    local resolved
    resolved="$(readlink "$dest" 2>/dev/null || true)"
    [[ "$resolved" == "$src" ]]
}

_sync_one() {
    local name="$1"
    local src="$2"
    local dest_root="$3"
    local dest="$dest_root/$name"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        if [[ "$COPY_MODE" -eq 1 ]]; then
            info "[dry-run] copy $src -> $dest"
        else
            info "[dry-run] link $dest -> $src"
        fi
        return 0
    fi

    mkdir -p "$dest_root"

    if [[ -e "$dest" || -L "$dest" ]]; then
        if _is_cookbook_link "$dest" "$src"; then
            success "已是 cookbook 链接: $dest"
            return 0
        fi
        if [[ -L "$dest" ]]; then
            warn "替换已有符号链接: $dest"
            rm -f "$dest"
        elif [[ -d "$dest" ]]; then
            warn "目标已存在目录，跳过（避免覆盖）: $dest"
            warn "如需改用 cookbook 版本，请先手动备份并删除该目录"
            return 0
        else
            warn "目标已存在文件，跳过: $dest"
            return 0
        fi
    fi

    if [[ "$COPY_MODE" -eq 1 ]]; then
        cp -R "$src" "$dest"
        success "已复制: $dest"
    else
        ln -s "$src" "$dest"
        success "已链接: $dest -> $src"
    fi
}

_unlink_one() {
    local name="$1"
    local src="$2"
    local dest_root="$3"
    local dest="$dest_root/$name"

    if [[ ! -e "$dest" && ! -L "$dest" ]]; then
        info "不存在，跳过: $dest"
        return 0
    fi

    if ! _is_cookbook_link "$dest" "$src"; then
        warn "不是指向本 cookbook 的链接，跳过: $dest"
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "[dry-run] unlink $dest"
        return 0
    fi

    rm -f "$dest"
    success "已移除链接: $dest"
}

cmd_sync() {
    step "同步 cookbook skills → $TARGET"
    local dest_root name src
    local count=0

    while IFS=$'\t' read -r name src; do
        [[ -z "${name:-}" ]] && continue
        while IFS= read -r dest_root; do
            _sync_one "$name" "$src" "$dest_root"
            count=$((count + 1))
        done < <(_dest_dirs_for_target "$TARGET")
    done < <(_list_skills)

    if [[ "$count" -eq 0 ]]; then
        warn "未找到任何 SKILL.md（在 $SKILLS_SRC）"
        return 0
    fi
    success "完成（处理 $count 项）"
}

cmd_unlink() {
    step "移除 cookbook skills 链接 → $TARGET"
    local dest_root name src

    while IFS=$'\t' read -r name src; do
        [[ -z "${name:-}" ]] && continue
        while IFS= read -r dest_root; do
            _unlink_one "$name" "$src" "$dest_root"
        done < <(_dest_dirs_for_target "$TARGET")
    done < <(_list_skills)
}

cmd_status() {
    step "Cookbook skills 状态"
    local name src dest_root dest
    local found=0

    echo -e "${BOLD}源目录:${NC} $SKILLS_SRC"
    echo -e "${BOLD}Cursor:${NC} $CURSOR_SKILLS"
    echo -e "${BOLD}Claude:${NC} $CLAUDE_SKILLS"
    echo

    while IFS=$'\t' read -r name src; do
        [[ -z "${name:-}" ]] && continue
        found=1
        echo -e "${BOLD}$name${NC}"
        echo "  src: $src"
        for dest_root in "$CURSOR_SKILLS" "$CLAUDE_SKILLS"; do
            dest="$dest_root/$name"
            if _is_cookbook_link "$dest" "$src"; then
                echo -e "  ${GREEN}linked${NC}: $dest"
            elif [[ -e "$dest" || -L "$dest" ]]; then
                echo -e "  ${YELLOW}exists${NC}:  $dest (非本 cookbook 链接)"
            else
                echo -e "  ${YELLOW}missing${NC}: $dest"
            fi
        done
    done < <(_list_skills)

    if [[ "$found" -eq 0 ]]; then
        warn "未找到任何 SKILL.md"
    fi
}

parse_global_opts() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=1; shift ;;
            --copy) COPY_MODE=1; shift ;;
            --target)
                [[ $# -ge 2 ]] || { error "--target 需要参数"; exit 1; }
                TARGET="$2"
                shift 2
                ;;
            -h|--help) usage; exit 0 ;;
            *)
                error "未知选项: $1"
                usage
                exit 1
                ;;
        esac
    done
}

main() {
    local cmd="${1:-}"
    if [[ -z "$cmd" || "$cmd" == "-h" || "$cmd" == "--help" ]]; then
        usage
        exit 0
    fi
    shift || true
    parse_global_opts "$@"

    case "$cmd" in
        sync) cmd_sync ;;
        status) cmd_status ;;
        unlink) cmd_unlink ;;
        *)
            error "未知命令: $cmd"
            usage
            exit 1
            ;;
    esac
}

main "$@"

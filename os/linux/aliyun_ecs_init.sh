#!/usr/bin/env bash
# 阿里云 ECS 初始化脚本
# 用途：创建普通用户、初始化数据盘并挂载到家目录、生成 SSH 密钥

set -euo pipefail

if [[ "${BASH_VERSINFO[0]}" -lt 3 ]]; then
  echo "ERROR: 此脚本需要 bash 3.2 或更高版本（当前: ${BASH_VERSION}）" >&2
  exit 1
fi

# ─── 颜色定义 ────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# ─── 工具函数 ────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}▶ $*${NC}"; }

is_installed() { command -v "$1" &>/dev/null; }

# ─── 全局选项（由 main 解析） ────────────────────────────────────────────────
DRY_RUN=false
ASSUME_YES=false
TARGET_USER=""
USER_PASSWORD=""
RANDOM_PASSWORD=false
DISK_DEVICE=""
FS_TYPE="ext4"
FS_TYPE_FROM_CLI=false
SSH_COMMENT=""

# ─── 用法说明 ────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") <subcommand> [选项]

${BOLD}说明:${NC}
  阿里云 ECS 初始化脚本：创建普通用户、识别并初始化数据盘挂到家目录、生成 SSH 密钥。
  未传参时以交互方式询问用户名、密码方式、数据盘、SSH 注释等。

${BOLD}子命令:${NC}
  create-user   创建普通用户，配置 sudo（首次输密码后 1 小时内免密）
  init-disk     识别数据盘、分区/格式化，挂载到 /home/<user>
                （无数据盘时跳过，家目录留在系统盘）
  init-ssh      为用户生成 ed25519 密钥对并打印公钥
  all           按推荐顺序执行：create-user → init-disk → init-ssh
  status        只读：查看用户、磁盘、挂载、SSH 状态

${BOLD}全局选项（均可省略，改为交互输入）:${NC}
  -h, --help              显示此帮助信息并退出
  --dry-run               只打印将要执行的操作，不实际修改
  --user NAME             目标用户名
  --yes                   跳过危险操作确认（格式化磁盘等）

${BOLD}create-user 选项:${NC}
  --password PASS         指定用户密码
  --random-password       随机生成密码并打印一次

${BOLD}init-disk 选项:${NC}
  --disk DEVICE           显式指定数据盘设备（如 /dev/vdb）
  --fs TYPE               文件系统类型，默认 ext4（可选 xfs）

${BOLD}init-ssh 选项:${NC}
  --email COMMENT         SSH 密钥 -C 注释（默认 <user>@<hostname>）

${BOLD}推荐步骤:${NC}
  1. create-user
  2. init-disk     # 有数据盘则挂到 /home/<user>；没有则跳过
  3. init-ssh

${BOLD}示例:${NC}
  sudo $(basename "$0") all                 # 全程交互
  sudo $(basename "$0") create-user
  sudo $(basename "$0") init-disk --yes
  sudo $(basename "$0") init-ssh
  sudo $(basename "$0") status
  sudo $(basename "$0") all --user alice --yes   # 部分参数预填

EOF
}
# ─── 权限检查 ────────────────────────────────────────────────────────────────
require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "请使用 root 用户或 sudo 运行此脚本"
    exit 1
  fi
}

run_cmd() {
  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] $*"
    return 0
  fi
  "$@"
}

# ─── 交互输入 ────────────────────────────────────────────────────────────────
prompt_line() {
  # 用法: prompt_line "提示" [默认值]
  local prompt="$1"
  local default="${2:-}"
  local reply
  if [[ -n "$default" ]]; then
    echo -e "${CYAN}${prompt}${NC} [${default}]: \c" >&2
  else
    echo -e "${CYAN}${prompt}${NC}: \c" >&2
  fi
  if ! read -r reply; then
    # EOF
    echo "$default"
    return
  fi
  if [[ -z "$reply" ]]; then
    echo "$default"
  else
    echo "$reply"
  fi
}

validate_username() {
  local name="$1"
  # 允许点号（如 dev.user）；禁止以数字/点/连字符开头，最长 32
  [[ ${#name} -le 32 ]] && [[ "$name" =~ ^[a-z_][a-z0-9._-]*$ ]]
}

ensure_target_user() {
  # 可选参数: require（默认 true）— status 可传 false 允许留空
  local required="${1:-true}"

  if [[ -n "$TARGET_USER" ]]; then
    if ! validate_username "$TARGET_USER"; then
      error "非法用户名: ${TARGET_USER}（需以小写字母或下划线开头，可含数字/点/下划线/连字符）"
      exit 1
    fi
    return 0
  fi

  if [[ "$required" != true ]]; then
    TARGET_USER=$(prompt_line "目标用户名（回车跳过）" "")
    if [[ -n "$TARGET_USER" ]] && ! validate_username "$TARGET_USER"; then
      error "非法用户名: ${TARGET_USER}"
      exit 1
    fi
    return 0
  fi

  while true; do
    TARGET_USER=$(prompt_line "目标用户名" "")
    if [[ -z "$TARGET_USER" ]]; then
      warn "用户名不能为空"
      if [[ ! -t 0 ]]; then
        error "非交互模式请使用 --user NAME"
        exit 1
      fi
      continue
    fi
    if ! validate_username "$TARGET_USER"; then
      warn "非法用户名（需以小写字母或下划线开头，可含数字/点/下划线/连字符，如 alice、dev.user）"
      if [[ ! -t 0 ]]; then
        error "非法用户名: ${TARGET_USER}"
        exit 1
      fi
      continue
    fi
    break
  done
}

ensure_password_mode() {
  if [[ -n "$USER_PASSWORD" ]] || [[ "$RANDOM_PASSWORD" == true ]]; then
    return 0
  fi
  if user_exists "$TARGET_USER"; then
    return 0
  fi
  if [[ "$DRY_RUN" == true ]]; then
    RANDOM_PASSWORD=true
    return 0
  fi

  echo -e "${CYAN}密码设置方式:${NC}"
  echo "  1) 手动输入密码"
  echo "  2) 随机生成密码"
  local choice
  while true; do
    choice=$(prompt_line "请选择" "1")
    case "$choice" in
      1)
        USER_PASSWORD=$(prompt_password)
        return 0
        ;;
      2)
        RANDOM_PASSWORD=true
        return 0
        ;;
      *)
        warn "请输入 1 或 2"
        if [[ ! -t 0 ]]; then
          error "非交互模式请使用 --password 或 --random-password"
          exit 1
        fi
        ;;
    esac
  done
}

ensure_ssh_comment() {
  local default_comment="${TARGET_USER}@$(hostname -s 2>/dev/null || hostname)"
  if [[ -n "$SSH_COMMENT" ]]; then
    return 0
  fi
  if [[ "$DRY_RUN" == true ]]; then
    SSH_COMMENT="$default_comment"
    return 0
  fi
  SSH_COMMENT=$(prompt_line "SSH 密钥注释 (-C)" "$default_comment")
  if [[ -z "$SSH_COMMENT" ]]; then
    SSH_COMMENT="$default_comment"
  fi
}

prompt_fs_type() {
  echo -e "${CYAN}文件系统类型:${NC}"
  echo "  1) ext4（推荐）"
  echo "  2) xfs"
  local choice
  while true; do
    choice=$(prompt_line "请选择" "1")
    case "$choice" in
      1) FS_TYPE="ext4"; return 0 ;;
      2) FS_TYPE="xfs"; return 0 ;;
      ext4|xfs) FS_TYPE="$choice"; return 0 ;;
      *)
        warn "请输入 1/2 或 ext4/xfs"
        if [[ ! -t 0 ]]; then
          FS_TYPE="ext4"
          return 0
        fi
        ;;
    esac
  done
}

# ─── 用户名校验 ──────────────────────────────────────────────────────────────
require_user_arg() {
  ensure_target_user true
}

user_exists() {
  id "$1" &>/dev/null
}

# ─── sudo 组检测 ─────────────────────────────────────────────────────────────
detect_sudo_group() {
  if getent group wheel &>/dev/null; then
    echo "wheel"
  elif getent group sudo &>/dev/null; then
    echo "sudo"
  else
    echo "wheel"
  fi
}

# ─── 密码处理 ────────────────────────────────────────────────────────────────
generate_random_password() {
  if is_installed openssl; then
    openssl rand -base64 18 | tr -d '/+=' | head -c 20
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20
  fi
  echo
}

prompt_password() {
  local pass1 pass2
  while true; do
    read -r -s -p "请输入用户 ${TARGET_USER} 的密码: " pass1
    echo
    read -r -s -p "请再次确认密码: " pass2
    echo
    if [[ -z "$pass1" ]]; then
      warn "密码不能为空"
      continue
    fi
    if [[ "$pass1" != "$pass2" ]]; then
      warn "两次输入不一致，请重试"
      continue
    fi
    echo "$pass1"
    return
  done
}

# ─── create-user ──────────────────────────────────────────────────────────────
cmd_create_user() {
  require_user_arg
  step "创建用户: ${TARGET_USER}"
  require_root

  local sudo_group
  sudo_group=$(detect_sudo_group)

  if user_exists "$TARGET_USER"; then
    success "用户已存在: ${TARGET_USER} (uid=$(id -u "$TARGET_USER"))"
  else
    ensure_password_mode
    local password="$USER_PASSWORD"
    if [[ "$RANDOM_PASSWORD" == true ]]; then
      password=$(generate_random_password)
    elif [[ -z "$password" ]]; then
      if [[ "$DRY_RUN" == true ]]; then
        password="(dry-run-placeholder)"
      else
        password=$(prompt_password)
      fi
    fi

    info "创建用户 ${TARGET_USER}（家目录 /home/${TARGET_USER}，shell /bin/bash）..."
    run_cmd useradd -m -s /bin/bash "$TARGET_USER"
    if [[ "$DRY_RUN" == true ]]; then
      info "[dry-run] 将为用户设置密码"
    else
      echo "${TARGET_USER}:${password}" | chpasswd
      if [[ "$RANDOM_PASSWORD" == true ]]; then
        echo -e "  ${BOLD}随机密码${NC}: ${password}"
        warn "请立即保存此密码，之后将不再显示"
      fi
    fi
    success "用户已创建: ${TARGET_USER}"
  fi

  # 加入 sudo 组
  if id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$sudo_group"; then
    success "用户已在 ${sudo_group} 组中"
  else
    info "将用户加入 ${sudo_group} 组..."
    run_cmd usermod -aG "$sudo_group" "$TARGET_USER"
    success "已加入 ${sudo_group} 组"
  fi

  # sudoers: timestamp_timeout=60
  local ts_file="/etc/sudoers.d/00-timestamp"
  local user_sudo_file="/etc/sudoers.d/${TARGET_USER}"

  info "配置 sudo timestamp_timeout=60（首次输密码后 1 小时内免密）..."
  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 写入 ${ts_file}"
    info "[dry-run] 写入 ${user_sudo_file}"
  else
    printf 'Defaults timestamp_timeout=60\n' >"$ts_file"
    chmod 440 "$ts_file"
    if ! visudo -cf "$ts_file" &>/dev/null; then
      error "sudoers 校验失败: ${ts_file}"
      rm -f "$ts_file"
      exit 1
    fi

    printf '%s ALL=(ALL) ALL\n' "$TARGET_USER" >"$user_sudo_file"
    chmod 440 "$user_sudo_file"
    if ! visudo -cf "$user_sudo_file" &>/dev/null; then
      error "sudoers 校验失败: ${user_sudo_file}"
      rm -f "$user_sudo_file"
      exit 1
    fi
  fi
  success "sudo 已配置（timestamp_timeout=60）"
}

# ─── 磁盘识别 ────────────────────────────────────────────────────────────────
# 返回系统盘设备路径列表（如 /dev/vda /dev/nvme0n1）
list_system_disks() {
  local mounts=("/" "/boot" "/boot/efi")
  local m src parent
  for m in "${mounts[@]}"; do
    src=$(findmnt -n -o SOURCE --target "$m" 2>/dev/null || true)
    [[ -z "$src" ]] && continue
    # 去掉分区后缀，得到整盘
    parent=$(lsblk -n -o PKNAME "$src" 2>/dev/null | head -1 || true)
    if [[ -n "$parent" ]]; then
      echo "/dev/${parent}"
    else
      # 本身可能就是整盘
      echo "$src" | sed -E 's/p?[0-9]+$//'
    fi
  done | sort -u
}

# 列出候选数据盘（未挂载的整盘，排除系统盘）
list_candidate_disks() {
  local sys_disks
  sys_disks=$(list_system_disks)

  # TYPE=disk 的整盘
  local disk
  while read -r disk; do
    [[ -z "$disk" ]] && continue
    # 排除系统盘
    if echo "$sys_disks" | grep -qx "$disk"; then
      continue
    fi
    # 排除已有任何分区被挂载的盘
    if lsblk -n -o MOUNTPOINT "$disk" 2>/dev/null | grep -qv '^$'; then
      continue
    fi
    echo "$disk"
  done < <(lsblk -dn -o PATH,TYPE 2>/dev/null | awk '$2=="disk"{print $1}')
}

resolve_data_disk() {
  if [[ -n "$DISK_DEVICE" ]]; then
    if [[ ! -b "$DISK_DEVICE" ]]; then
      error "设备不存在或不是块设备: ${DISK_DEVICE}"
      exit 1
    fi
    local sys_disks
    sys_disks=$(list_system_disks)
    if echo "$sys_disks" | grep -qx "$DISK_DEVICE"; then
      error "拒绝操作：${DISK_DEVICE} 是系统盘"
      exit 1
    fi
    echo "$DISK_DEVICE"
    return
  fi

  local candidates
  candidates=$(list_candidate_disks)
  local count
  count=$(echo "$candidates" | grep -c . || true)

  if [[ "$count" -eq 0 ]]; then
    # 无数据盘：返回空，由调用方决定跳过（家目录留在系统盘）
    return 0
  fi

  if [[ "$count" -eq 1 ]]; then
    local only
    only=$(echo "$candidates" | head -1)
    if [[ "$ASSUME_YES" == true ]] || [[ "$DRY_RUN" == true ]]; then
      echo "$only"
      return
    fi
    local size
    size=$(lsblk -dn -o SIZE "$only" 2>/dev/null | xargs)
    local yn
    yn=$(prompt_line "检测到数据盘 ${only} (${size})，是否使用？" "Y")
    if [[ "$yn" =~ ^[Yy]$ ]]; then
      echo "$only"
    else
      warn "已跳过数据盘挂载" >&2
      return 0
    fi
    return
  fi

  # 多块盘：交互选择
  echo -e "${CYAN}发现多块候选数据盘:${NC}" >&2
  local -a disk_arr=()
  local i=1
  local d size model
  while read -r d; do
    [[ -z "$d" ]] && continue
    disk_arr+=("$d")
    size=$(lsblk -dn -o SIZE "$d" 2>/dev/null | xargs)
    model=$(lsblk -dn -o MODEL "$d" 2>/dev/null | xargs || true)
    echo "  ${i}) ${d}  ${size}  ${model}" >&2
    i=$((i + 1))
  done <<<"$candidates"
  echo "  0) 跳过（使用系统盘上的家目录）" >&2

  local choice
  while true; do
    choice=$(prompt_line "请选择数据盘编号" "1")
    if [[ "$choice" == "0" ]]; then
      warn "已跳过数据盘挂载" >&2
      return 0
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#disk_arr[@]} ]]; then
      echo "${disk_arr[$((choice - 1))]}"
      return 0
    fi
    warn "请输入 0-${#disk_arr[@]} 之间的数字" >&2
  done
}

# 获取盘的第一个分区路径（兼容 nvme / 普通盘）
disk_first_partition() {
  local disk="$1"
  local part
  part=$(lsblk -ln -o PATH,TYPE "$disk" | awk '$2=="part"{print $1; exit}')
  if [[ -n "$part" ]]; then
    echo "$part"
    return
  fi
  # 尚未分区时推算名称
  if [[ "$disk" == *nvme* ]] || [[ "$disk" == *mmcblk* ]]; then
    echo "${disk}p1"
  else
    echo "${disk}1"
  fi
}

confirm_destructive() {
  local msg="$1"
  if [[ "$ASSUME_YES" == true ]] || [[ "$DRY_RUN" == true ]]; then
    return 0
  fi
  echo -e "${YELLOW}${msg} [y/N]${NC} \c"
  local confirm
  read -r confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    info "已取消"
    exit 0
  fi
}

# ─── init-disk ────────────────────────────────────────────────────────────────
cmd_init_disk() {
  require_user_arg
  step "初始化数据盘 → /home/${TARGET_USER}"
  require_root

  if ! user_exists "$TARGET_USER"; then
    error "用户 ${TARGET_USER} 不存在，请先执行 create-user"
    exit 1
  fi

  if ! is_installed lsblk || ! is_installed findmnt; then
    error "需要 lsblk / findmnt（通常来自 util-linux）"
    exit 1
  fi

  local home_dir="/home/${TARGET_USER}"
  local disk part uuid mount_src

  # 幂等：已挂载到家目录
  mount_src=$(findmnt -n -o SOURCE --target "$home_dir" 2>/dev/null || true)
  if [[ -n "$mount_src" ]]; then
    local root_src
    root_src=$(findmnt -n -o SOURCE --target / 2>/dev/null || true)
    if [[ "$mount_src" != "$root_src" ]]; then
      success "数据盘已挂载到 ${home_dir}（${mount_src}），跳过"
      return 0
    fi
  fi

  disk=$(resolve_data_disk)
  if [[ -z "$disk" ]]; then
    warn "未检测到数据盘，跳过挂载；用户数据将使用系统盘上的 ${home_dir}"
    info "当前块设备："
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT || true
    success "init-disk 已跳过（无数据盘）"
    return 0
  fi

  info "选用数据盘: ${disk}"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$disk" || true

  part=$(disk_first_partition "$disk")
  local has_part=false
  if [[ -b "$part" ]]; then
    has_part=true
  fi

  # 分区
  if [[ "$has_part" != true ]]; then
    confirm_destructive "将对 ${disk} 创建 GPT 单分区，是否继续？"
    info "创建分区表与单分区..."
    if ! is_installed parted; then
      error "需要 parted 命令"
      exit 1
    fi
    run_cmd parted -s "$disk" mklabel gpt
    run_cmd parted -s "$disk" mkpart primary 0% 100%
    run_cmd partprobe "$disk" 2>/dev/null || true
    # 等待 udev
    if [[ "$DRY_RUN" != true ]]; then
      sleep 1
      # 重新解析分区名
      part=$(disk_first_partition "$disk")
      local i=0
      while [[ ! -b "$part" && $i -lt 10 ]]; do
        sleep 0.5
        part=$(disk_first_partition "$disk")
        i=$((i + 1))
      done
      if [[ ! -b "$part" ]]; then
        error "分区创建后未找到设备: ${part}"
        exit 1
      fi
    fi
    success "分区已创建: ${part}"
  else
    success "已存在分区: ${part}"
  fi

  # 格式化
  local existing_fs
  existing_fs=$(lsblk -n -o FSTYPE "$part" 2>/dev/null | head -1 | tr -d '[:space:]' || true)
  if [[ -z "$existing_fs" ]]; then
    if [[ "$FS_TYPE_FROM_CLI" != true ]]; then
      if [[ "$ASSUME_YES" == true ]] || [[ "$DRY_RUN" == true ]]; then
        FS_TYPE="ext4"
      else
        prompt_fs_type
      fi
    fi
    confirm_destructive "将对 ${part} 格式化为 ${FS_TYPE}，数据将清空。是否继续？"
    case "$FS_TYPE" in
      ext4)
        run_cmd mkfs.ext4 -F -L "ecs-data" "$part"
        ;;
      xfs)
        if ! is_installed mkfs.xfs; then
          error "需要 mkfs.xfs（安装 xfsprogs）"
          exit 1
        fi
        run_cmd mkfs.xfs -f -L "ecs-data" "$part"
        ;;
      *)
        error "不支持的文件系统: ${FS_TYPE}（支持 ext4 / xfs）"
        exit 1
        ;;
    esac
    success "已格式化为 ${FS_TYPE}: ${part}"
  else
    success "分区已有文件系统: ${existing_fs}，跳过格式化"
    FS_TYPE="$existing_fs"
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将迁移 ${home_dir} 内容并挂载 ${part} → ${home_dir}"
    info "[dry-run] 将写入 /etc/fstab（UUID）"
    return 0
  fi

  uuid=$(blkid -s UUID -o value "$part")
  if [[ -z "$uuid" ]]; then
    error "无法获取 ${part} 的 UUID"
    exit 1
  fi

  local tmp_mnt="/mnt/ecs-data"
  mkdir -p "$tmp_mnt"
  # 若已挂在临时点则先卸
  if findmnt -n "$tmp_mnt" &>/dev/null; then
    umount "$tmp_mnt" || true
  fi
  mount "$part" "$tmp_mnt"
  success "临时挂载 ${part} → ${tmp_mnt}"

  # 迁移现有家目录
  local bak=""
  if [[ -d "$home_dir" ]] && [[ -n "$(ls -A "$home_dir" 2>/dev/null || true)" ]]; then
    info "迁移 ${home_dir} 内容到数据盘..."
    if is_installed rsync; then
      rsync -aHAX --info=progress2 "$home_dir"/ "$tmp_mnt"/
    else
      cp -a "$home_dir"/. "$tmp_mnt"/
    fi
    bak="${home_dir}.bak.$(date +%Y%m%d%H%M%S)"
    mv "$home_dir" "$bak"
    success "原家目录已备份为 ${bak}"
  else
    mkdir -p "$home_dir"
    # 空目录或刚创建：仍可能需要骨架文件
    if [[ -z "$(ls -A "$tmp_mnt" 2>/dev/null || true)" ]]; then
      if [[ -d /etc/skel ]]; then
        cp -a /etc/skel/. "$tmp_mnt"/ 2>/dev/null || true
      fi
    fi
  fi

  umount "$tmp_mnt"
  rmdir "$tmp_mnt" 2>/dev/null || true

  mkdir -p "$home_dir"
  mount "$part" "$home_dir"
  chown -R "${TARGET_USER}:${TARGET_USER}" "$home_dir"
  success "已挂载 ${part} → ${home_dir}"

  # fstab（按 UUID）
  local fstab_line="UUID=${uuid}  ${home_dir}  ${FS_TYPE}  defaults,nofail  0  2"
  if grep -qE "[[:space:]]${home_dir}[[:space:]]" /etc/fstab 2>/dev/null; then
    info "更新 /etc/fstab 中 ${home_dir} 条目..."
    # 备份 fstab
    cp -a /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
    # 删除旧条目（匹配挂载点）
    local tmp_fstab
    tmp_fstab=$(mktemp)
    awk -v mp="$home_dir" '
      /^[[:space:]]*#/ { print; next }
      NF == 0 { print; next }
      {
        # 第 2 列为挂载点
        if ($2 == mp) next
        print
      }
    ' /etc/fstab >"$tmp_fstab"
    echo "$fstab_line" >>"$tmp_fstab"
    mv "$tmp_fstab" /etc/fstab
  else
    info "写入 /etc/fstab..."
    cp -a /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
    echo "$fstab_line" >>/etc/fstab
  fi
  success "fstab 已更新: UUID=${uuid} → ${home_dir}"

  # 验证
  if findmnt -n --target "$home_dir" | grep -q .; then
    success "挂载验证通过"
    df -h "$home_dir"
  else
    error "挂载验证失败"
    exit 1
  fi

  if [[ -n "$bak" ]]; then
    info "确认无误后可手动删除备份: rm -rf ${bak}"
  fi
}

# ─── init-ssh ─────────────────────────────────────────────────────────────────
cmd_init_ssh() {
  require_user_arg
  step "生成 SSH 密钥: ${TARGET_USER}"
  require_root

  if ! user_exists "$TARGET_USER"; then
    error "用户 ${TARGET_USER} 不存在，请先执行 create-user"
    exit 1
  fi

  local home_dir
  home_dir=$(getent passwd "$TARGET_USER" | cut -d: -f6)
  if [[ -z "$home_dir" ]] || [[ ! -d "$home_dir" ]]; then
    error "家目录不存在: ${home_dir:-unknown}"
    exit 1
  fi

  local ssh_dir="${home_dir}/.ssh"
  local key_path="${ssh_dir}/id_ed25519"
  local pub_path="${key_path}.pub"

  ensure_ssh_comment
  local comment="${SSH_COMMENT}"

  if [[ -f "$key_path" ]]; then
    success "SSH 密钥已存在: ${key_path}，跳过生成"
  else
    info "生成 ed25519 密钥对（-C ${comment}）..."
    if [[ "$DRY_RUN" == true ]]; then
      info "[dry-run] mkdir -p ${ssh_dir} && ssh-keygen -t ed25519 -C \"${comment}\" ..."
    else
      mkdir -p "$ssh_dir"
      chmod 700 "$ssh_dir"
      ssh-keygen -t ed25519 -N "" -f "$key_path" -C "$comment"
      chmod 600 "$key_path"
      chmod 644 "$pub_path"
      chown -R "${TARGET_USER}:${TARGET_USER}" "$ssh_dir"
      success "密钥已生成: ${key_path}"
    fi
  fi

  if [[ "$DRY_RUN" != true ]] && [[ -f "$pub_path" ]]; then
    echo
    echo -e "${BOLD}公钥 (${pub_path}):${NC}"
    echo "----------------------------------------"
    cat "$pub_path"
    echo "----------------------------------------"
  fi
}

# ─── status ───────────────────────────────────────────────────────────────────
cmd_status() {
  step "状态概览"

  # 未指定用户时交互询问（可回车跳过）
  if [[ -z "$TARGET_USER" ]] && [[ -t 0 ]]; then
    ensure_target_user false
  fi

  echo -e "  ${BOLD}主机名${NC}     : $(hostname 2>/dev/null || echo unknown)"
  if [[ -f /etc/os-release ]]; then
    echo -e "  ${BOLD}系统${NC}       : $(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')"
  fi
  echo

  step "块设备"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL,UUID
  echo

  step "系统盘"
  list_system_disks | while read -r d; do
    echo -e "  ${d}"
  done
  echo

  step "候选数据盘"
  local cands
  cands=$(list_candidate_disks || true)
  if [[ -z "$cands" ]]; then
    echo "  （无未挂载候选盘）"
  else
    echo "$cands" | while read -r d; do
      echo -e "  ${d}  ($(lsblk -dn -o SIZE "$d" 2>/dev/null | xargs))"
    done
  fi
  echo

  if [[ -n "$TARGET_USER" ]]; then
    step "用户: ${TARGET_USER}"
    if user_exists "$TARGET_USER"; then
      local home_dir uid gid groups
      home_dir=$(getent passwd "$TARGET_USER" | cut -d: -f6)
      uid=$(id -u "$TARGET_USER")
      gid=$(id -g "$TARGET_USER")
      groups=$(id -nG "$TARGET_USER")
      echo -e "  ${BOLD}存在${NC}       : 是 (uid=${uid} gid=${gid})"
      echo -e "  ${BOLD}组${NC}         : ${groups}"
      echo -e "  ${BOLD}家目录${NC}     : ${home_dir}"
      if [[ -d "$home_dir" ]]; then
        local src fstype
        src=$(findmnt -n -o SOURCE --target "$home_dir" 2>/dev/null || echo "(未单独挂载)")
        fstype=$(findmnt -n -o FSTYPE --target "$home_dir" 2>/dev/null || echo "-")
        echo -e "  ${BOLD}挂载源${NC}     : ${src} (${fstype})"
        df -h "$home_dir" 2>/dev/null | awk 'NR==2{printf "  磁盘使用   : %s 总计 / %s 已用 / %s 可用\n",$2,$3,$4}'
      fi
      if [[ -f "${home_dir}/.ssh/id_ed25519.pub" ]]; then
        echo -e "  ${BOLD}SSH 公钥${NC}   : 已存在"
        echo -e "  $(cat "${home_dir}/.ssh/id_ed25519.pub")"
      else
        echo -e "  ${BOLD}SSH 公钥${NC}   : 未生成"
      fi
      if [[ -f /etc/sudoers.d/00-timestamp ]]; then
        echo -e "  ${BOLD}sudo 超时${NC}  : $(grep timestamp_timeout /etc/sudoers.d/00-timestamp 2>/dev/null || echo 已配置)"
      else
        echo -e "  ${BOLD}sudo 超时${NC}  : 未配置 timestamp_timeout"
      fi
    else
      echo -e "  ${BOLD}存在${NC}       : 否"
    fi
  else
    info "提示: 可指定用户查看详情（交互询问或 --user NAME）"
  fi
  echo
}

# ─── all ──────────────────────────────────────────────────────────────────────
cmd_all() {
  step "一键初始化（create-user → init-disk → init-ssh）"
  require_user_arg
  cmd_create_user
  cmd_init_disk
  cmd_init_ssh
  echo -e "\n${GREEN}${BOLD}✓ 全部步骤完成${NC}\n"
  info "推荐后续：用新用户登录，执行 df -h ~ 确认家目录所在磁盘"
}

# ─── 参数解析 ────────────────────────────────────────────────────────────────
parse_global_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --dry-run)
        DRY_RUN=true
        ;;
      --yes|-y)
        ASSUME_YES=true
        ;;
      --user)
        shift
        TARGET_USER="${1:-}"
        if [[ -z "$TARGET_USER" ]]; then
          error "--user 需要参数"
          exit 1
        fi
        ;;
      --password)
        shift
        USER_PASSWORD="${1:-}"
        if [[ -z "$USER_PASSWORD" ]]; then
          error "--password 需要参数"
          exit 1
        fi
        ;;
      --random-password)
        RANDOM_PASSWORD=true
        ;;
      --disk)
        shift
        DISK_DEVICE="${1:-}"
        if [[ -z "$DISK_DEVICE" ]]; then
          error "--disk 需要参数"
          exit 1
        fi
        ;;
      --fs)
        shift
        FS_TYPE="${1:-}"
        if [[ -z "$FS_TYPE" ]]; then
          error "--fs 需要参数"
          exit 1
        fi
        FS_TYPE_FROM_CLI=true
        ;;
      --email)
        shift
        SSH_COMMENT="${1:-}"
        if [[ -z "$SSH_COMMENT" ]]; then
          error "--email 需要参数"
          exit 1
        fi
        ;;
      -*)
        error "未知选项: $1"
        usage
        exit 1
        ;;
      *)
        error "意外参数: $1（子命令后只接受选项）"
        usage
        exit 1
        ;;
    esac
    shift
  done
}

main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 1
  fi

  local subcommand="$1"
  shift

  case "$subcommand" in
    -h|--help)
      usage
      exit 0
      ;;
    create-user|init-disk|init-ssh|all|status)
      ;;
    *)
      error "未知子命令: ${subcommand}"
      usage
      exit 1
      ;;
  esac

  parse_global_args "$@"

  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║   阿里云 ECS 初始化脚本              ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"

  if [[ "$DRY_RUN" == true ]]; then
    warn "dry-run 模式：不会实际修改系统"
  fi

  case "$subcommand" in
    create-user) cmd_create_user ;;
    init-disk)   cmd_init_disk ;;
    init-ssh)    cmd_init_ssh ;;
    all)         cmd_all ;;
    status)      cmd_status ;;
  esac
}

main "$@"

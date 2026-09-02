#!/usr/bin/env bash
# =============================================================
# ShellExp main.sh — 模板拼装生成器
#
# 将 script/biz/ 下的段模板（认证 auth -> 提权 escalate -> 业务 biz）
# 按需拼装为完整 expect 脚本，输出到 --out 指定路径（惯例为 bin/ 下）。
#
# 拼装帧: shebang 头 -> 公共头(timeout/环境变量校验) -> usage/argv
#         -> script/lib/util.tcl 工具函数 -> auth 段 -> escalate 段
#         -> biz 段 -> epilogue 收尾
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIZ_ROOT="$ROOT/script/biz"

die() { echo "main.sh: $1" >&2; exit "${2:-64}"; }

show_usage() {
    cat <<'USAGE'
Usage:
  ./main.sh --auth <name> --escalate <name> --biz <name> --out <file>
      --auth <name>      auth segment:     script/biz/auth/auth_<name>.tpl (ssh/telnet)
      --escalate <name>  escalate segment: script/biz/escalate/escalate_<name>.tpl (none/su/sudo)
      --biz <name>       biz segment:      unique <name>.tpl under script/biz/ category dirs
      --out <file>       output path (conventionally under bin/)

  ./main.sh --list       list available segment templates
  ./main.sh --help       show this help

Example:
  ./main.sh --auth ssh --escalate sudo --biz chpasswd --out bin/ssh_sudo_chpasswd.exp
  AUTH_PASS='loginpass' ESCALATE_PASS='sudopass' NEW_PASS='newpass' \
      ./bin/ssh_sudo_chpasswd.exp <host> <port> <auth_user> <target_user>
USAGE
}

list_templates() {
    echo "Available segment templates (script/biz/):"
    local dir base names
    for dir in "$BIZ_ROOT"/*/; do
        base="$(basename "$dir")"
        names="$(cd "$dir" && ls -1 *.tpl 2>/dev/null | sed 's/\.tpl$//' \
            | sed 's/^auth_//;s/^escalate_//;s/^password_//' | paste -sd ' ' -)"
        printf '  %-10s %s\n' "$base" "${names:-(empty)}"
    done
    echo
    echo "Note: --auth <n> -> auth/auth_<n>.tpl; --escalate <n> -> escalate/escalate_<n>.tpl;"
    echo "      --biz <n> -> <n>.tpl or <category>_<n>.tpl under biz category dirs (auth/escalate excluded)."
}

# ----------------------------------------------------------------
# 参数解析
# ----------------------------------------------------------------
AUTH="" ESCALATE="" BIZ="" OUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auth)     [[ $# -ge 2 ]] || die "option $1 requires a value"; AUTH="$2"; shift 2 ;;
        --escalate) [[ $# -ge 2 ]] || die "option $1 requires a value"; ESCALATE="$2"; shift 2 ;;
        --biz)      [[ $# -ge 2 ]] || die "option $1 requires a value"; BIZ="$2"; shift 2 ;;
        --out)      [[ $# -ge 2 ]] || die "option $1 requires a value"; OUT="$2"; shift 2 ;;
        --list)     list_templates; exit 0 ;;
        -h|--help)  show_usage; exit 0 ;;
        *)          echo "main.sh: unknown option: $1" >&2; show_usage; exit 64 ;;
    esac
done

[[ -n "$AUTH"     ]] || die "missing --auth" 64
[[ -n "$ESCALATE" ]] || die "missing --escalate" 64
[[ -n "$BIZ"      ]] || die "missing --biz" 64
[[ -n "$OUT"      ]] || die "missing --out" 64

# ----------------------------------------------------------------
# 定位段模板
# ----------------------------------------------------------------
auth_f="$BIZ_ROOT/auth/auth_${AUTH}.tpl"
esc_f="$BIZ_ROOT/escalate/escalate_${ESCALATE}.tpl"

[[ -f "$auth_f" ]] || die "auth template not found: $auth_f"
[[ -f "$esc_f" ]] || die "escalate template not found: $esc_f"

mapfile -t biz_files < <(find "$BIZ_ROOT" -mindepth 2 -maxdepth 2 -type f \
    \( -name "$BIZ.tpl" -o -name "*_${BIZ}.tpl" \) \
    ! -path "$BIZ_ROOT/auth/*" ! -path "$BIZ_ROOT/escalate/*" | sort)
if (( ${#biz_files[@]} == 0 )); then
    die "biz template not found: $BIZ.tpl"
fi
if (( ${#biz_files[@]} > 1 )); then
    die "ambiguous biz template name: $BIZ.tpl -> ${biz_files[*]}"
fi
biz_f="${biz_files[0]}"

# ----------------------------------------------------------------
# 解析模板自描述契约: REQUIRE_ENV / REQUIRE_ARGV
# ----------------------------------------------------------------
REQ_ENVS="$(grep -h '^# REQUIRE_ENV:' "$auth_f" "$esc_f" "$biz_f" 2>/dev/null \
    | sed 's/^#[[:space:]]*REQUIRE_ENV:[[:space:]]*//' \
    | tr -s '[:space:]' '\n' | sed '/^$/d' | awk '!seen[$0]++' | tr '\n' ' ' | sed 's/ *$//' || true)"

ARGV_NAMES=()
ARGV_DESCS=()
while IFS=$'\t' read -r name desc; do
    [[ -z "$name" ]] && continue
    ARGV_NAMES+=("$name")
    ARGV_DESCS+=("$desc")
done < <(grep -h '^# REQUIRE_ARGV:' "$auth_f" "$esc_f" "$biz_f" 2>/dev/null \
    | sed 's/^#[[:space:]]*REQUIRE_ARGV:[[:space:]]*//' \
    | awk '{n=$1; sub(/^[^[:space:]]*[[:space:]]*/, ""); print n "\t" $0}')

# ----------------------------------------------------------------
# 组装 usage / argv 解析块（argv 位置全部由 REQUIRE_ARGV 声明, 从 0 号位起）
# ----------------------------------------------------------------
usage_params=""
param_descs=()

argv_lines=""
idx=0
for i in "${!ARGV_NAMES[@]}"; do
    name="${ARGV_NAMES[$i]}"
    desc="${ARGV_DESCS[$i]}"
    printf -v line 'set %s [lindex $argv %d]' "$name" "$idx"
    argv_lines+="$line"$'\n'
    usage_params+=" <$name>"
    param_descs+=("$(printf '%-12s %s' "$name" "$desc")")
    idx=$((idx + 1))
done
usage_params="${usage_params# }"
ARGC=$idx
printf -v argc_line 'if {$argc != %d} { usage }' "$ARGC"
ARGV_BLOCK="$argc_line"$'\n'"$argv_lines"

# ----------------------------------------------------------------
# 组装 usage proc / 环境变量校验块
# ----------------------------------------------------------------
env_prefix=""
for v in $REQ_ENVS; do env_prefix+="${v}=... "; done

env_descs=()
for v in $REQ_ENVS; do
    case "$v" in
        AUTH_PASS)     env_descs+=("AUTH_PASS        SSH/telnet login password (required)") ;;
        ESCALATE_PASS) env_descs+=("ESCALATE_PASS    privilege escalation password (required; su: target user's password, sudo: current user's password)") ;;
        NEW_PASS)      env_descs+=("NEW_PASS         new password (required)") ;;
        *)             env_descs+=("$v") ;;
    esac
done
if [[ "$BIZ" == "passwd" ]]; then
    env_descs+=("OLD_PASS         current password (optional; required when the target user changes own password without privilege)")
fi
env_descs+=("TIMEOUT          expect timeout in seconds (optional, default 30)")

desc_block=""
for d in "${param_descs[@]}"; do
    printf -v line '    puts stderr "  %s"' "$d"
    desc_block+="$line"$'\n'
done
envdesc_block=""
for d in "${env_descs[@]}"; do
    printf -v line '    puts stderr "  %s"' "$d"
    envdesc_block+="$line"$'\n'
done

read -r -d '' USAGE_TPL <<'TPL' || true
proc usage {} {
    global argv0
    puts stderr "Usage: ${ENVPREFIX}$argv0 ${PARAMS}"
    puts stderr ""
    puts stderr "Positional args:"
${DESC}
    puts stderr ""
    puts stderr "Environment variables:"
${ENVDESC}
    exit 1
}
TPL
USAGE_BLOCK="$USAGE_TPL"
USAGE_BLOCK="${USAGE_BLOCK//\$\{ENVPREFIX\}/$env_prefix}"
USAGE_BLOCK="${USAGE_BLOCK//\$\{PARAMS\}/$usage_params}"
USAGE_BLOCK="${USAGE_BLOCK//\$\{DESC\}/$desc_block}"
USAGE_BLOCK="${USAGE_BLOCK//\$\{ENVDESC\}/$envdesc_block}"

read -r -d '' ENVCHECK_TPL <<'TPL' || true
# 运行时校验: 缺少必需环境变量立即报错退出（凭据不进 argv, 防 ps 泄露）
foreach _v {${REQLIST}} {
    if {![info exists env($_v)]} {
        puts stderr "ERROR: missing required env var $_v"
        usage
    }
}
TPL
ENVCHECK_BLOCK="${ENVCHECK_TPL//\$\{REQLIST\}/$REQ_ENVS}"

# ----------------------------------------------------------------
# 拼装输出
# ----------------------------------------------------------------
mkdir -p "$(dirname "$OUT")"

{
    echo '#!/usr/bin/expect'
    echo '# ============================================================'
    echo '# ShellExp 生成的 expect 脚本 —— 构建产物, 请勿手工编辑'
    echo "# 组合: auth=$AUTH escalate=$ESCALATE biz=$BIZ"
    echo "# 重新生成: ./main.sh --auth $AUTH --escalate $ESCALATE --biz $BIZ --out $OUT"
    echo "# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo '# ============================================================'
    echo
    cat <<'FRAME'

# ------------------------------------------------------------
# 段0 公共头 · 超时（可用环境变量 TIMEOUT 覆盖, 默认 30 秒）
# ------------------------------------------------------------
set timeout 30
if {[info exists env(TIMEOUT)]} { set timeout $env(TIMEOUT) }

FRAME
    printf '%s\n' "$USAGE_BLOCK"
    echo
    printf '%s\n' "$ENVCHECK_BLOCK"
    echo
    printf '%s\n' "$ARGV_BLOCK"
    echo
    cat <<'FRAME'

# ------------------------------------------------------------
# 公共工具函数（源: script/lib/util.tcl, 拼装时内联）
# ------------------------------------------------------------
FRAME
    cat "$ROOT/script/lib/util.tcl"
    echo
    cat "$auth_f"
    echo
    cat <<'FRAME'
# ------------------------------------------------------------
# 段1.5 公共 · locale 固定 —— 认证成功后、提权/业务前执行；
# 统一远端提示语言，规避中文 locale 下的提示漂移（调研 4.4）。
# 注意: 要求远端为 POSIX shell；网络设备等非 shell 目标应在业务模板内处理。
# ------------------------------------------------------------
send "export LANG=C LC_ALL=C\r"
expect {
    -re {[%#$>]\s*$} { }
    timeout { puts stderr "LOCALE_TIMEOUT"; exit 2 }
    eof     { puts stderr "LOCALE_EOF";     exit 2 }
}
log_info "remote locale fixed to C"

FRAME
    cat "$esc_f"
    echo
    cat "$biz_f"
    echo
    cat <<'FRAME'

# ------------------------------------------------------------
# 段4 收尾 · epilogue —— 逐层退出嵌套 shell 直至 eof
# ------------------------------------------------------------
log_info "epilogue: exiting session"
foreach _i {1 2 3 4 5} {
    expect {
        eof     { break }
        -re {[%#$>]\s*$} { send "exit\r" }
        timeout { break }
    }
}
catch { wait }
exit 0
FRAME
} > "$OUT"

chmod +x "$OUT"
echo "Generated: $OUT (auth=$AUTH escalate=$ESCALATE biz=$BIZ, argc=$ARGC, env: ${REQ_ENVS:-none})"

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
用法:
  ./main.sh --auth <name> --escalate <name> --biz <name> --out <file>
      --auth <name>      认证段: script/biz/auth/<name>.tpl
      --escalate <name>  提权段: script/biz/escalate/<name>.tpl (none/su/sudo)
      --biz <name>       业务段: script/biz/ 业务子目录中唯一匹配的 <name>.tpl
      --out <file>       输出路径 (惯例 bin/<auth>_<escalate>_<biz>.exp)

  ./main.sh --list       列出可用段模板
  ./main.sh --help       显示本帮助

示例:
  ./main.sh --auth generic --escalate sudo --biz chpasswd --out bin/generic_sudo_chpasswd.exp
  AUTH_PASS='登录密码' ESCALATE_PASS='sudo密码' NEW_PASS='新密码' \
      ./bin/generic_sudo_chpasswd.exp <host> <port> <auth_user> <target_user>
USAGE
}

list_templates() {
    echo "可用段模板 (script/biz/):"
    local dir base names
    for dir in "$BIZ_ROOT"/*/; do
        base="$(basename "$dir")"
        names="$(cd "$dir" && ls -1 *.tpl 2>/dev/null | sed 's/\.tpl$//' | paste -sd ' ' -)"
        printf '  %-10s %s\n' "$base" "${names:-(空)}"
    done
    echo
    echo "说明: --auth 取 auth/ 下文件名; --escalate 取 escalate/ 下文件名;"
    echo "      --biz 在业务子目录(auth/escalate 除外)中按文件名唯一匹配。"
}

# ----------------------------------------------------------------
# 参数解析
# ----------------------------------------------------------------
AUTH="" ESCALATE="" BIZ="" OUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auth)     [[ $# -ge 2 ]] || die "选项 $1 缺少参数"; AUTH="$2"; shift 2 ;;
        --escalate) [[ $# -ge 2 ]] || die "选项 $1 缺少参数"; ESCALATE="$2"; shift 2 ;;
        --biz)      [[ $# -ge 2 ]] || die "选项 $1 缺少参数"; BIZ="$2"; shift 2 ;;
        --out)      [[ $# -ge 2 ]] || die "选项 $1 缺少参数"; OUT="$2"; shift 2 ;;
        --list)     list_templates; exit 0 ;;
        -h|--help)  show_usage; exit 0 ;;
        *)          echo "main.sh: 未知选项: $1" >&2; show_usage; exit 64 ;;
    esac
done

[[ -n "$AUTH"     ]] || die "缺少 --auth" 64
[[ -n "$ESCALATE" ]] || die "缺少 --escalate" 64
[[ -n "$BIZ"      ]] || die "缺少 --biz" 64
[[ -n "$OUT"      ]] || die "缺少 --out" 64

# ----------------------------------------------------------------
# 定位段模板
# ----------------------------------------------------------------
auth_f="$BIZ_ROOT/auth/$AUTH.tpl"
esc_f="$BIZ_ROOT/escalate/$ESCALATE.tpl"

[[ -f "$auth_f" ]] || die "认证段模板不存在: $auth_f"
[[ -f "$esc_f" ]] || die "提权段模板不存在: $esc_f"

mapfile -t biz_files < <(find "$BIZ_ROOT" -mindepth 2 -maxdepth 2 -type f -name "$BIZ.tpl" \
    ! -path "$BIZ_ROOT/auth/*" ! -path "$BIZ_ROOT/escalate/*" | sort)
if (( ${#biz_files[@]} == 0 )); then
    die "业务段模板不存在: $BIZ.tpl"
fi
if (( ${#biz_files[@]} > 1 )); then
    die "业务段模板名不唯一: $BIZ.tpl -> ${biz_files[*]}"
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
        AUTH_PASS)     env_descs+=("AUTH_PASS        SSH 登录密码（必填）") ;;
        ESCALATE_PASS) env_descs+=("ESCALATE_PASS    提权密码（必填; su 输目标身份密码, sudo 输当前用户密码）") ;;
        NEW_PASS)      env_descs+=("NEW_PASS         新密码（必填）") ;;
        *)             env_descs+=("$v") ;;
    esac
done
if [[ "$BIZ" == "passwd" ]]; then
    env_descs+=("OLD_PASS         当前密码（可选; 目标用户非提权自改时必需）")
fi
env_descs+=("TIMEOUT          expect 超时秒数（可选, 默认 30）")

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
    puts stderr "用法: ${ENVPREFIX}$argv0 ${PARAMS}"
    puts stderr ""
    puts stderr "位置参数:"
${DESC}
    puts stderr ""
    puts stderr "环境变量:"
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
        puts stderr "ERROR: 缺少必需的环境变量 $_v"
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
echo "已生成: $OUT (auth=$AUTH escalate=$ESCALATE biz=$BIZ, argc=$ARGC, env: ${REQ_ENVS:-无})"

# ------------------------------------------------------------
# 段1 认证 · ssh —— SSH 密码登录（全脚本唯一 spawn 点）
# REQUIRE_ENV: AUTH_PASS
# REQUIRE_ARGV: host target host address
# REQUIRE_ARGV: port SSH port (e.g. 22)
# REQUIRE_ARGV: auth_user SSH login username
# OPT_ENV: PROXY_COMMAND complete ProxyCommand string (e.g. "nc -X connect -x proxy:8080 %h %p"); framework injects it verbatim as "-o ProxyCommand=..."
# OPT_ENV: SSH_KEEPALIVE ServerAliveInterval seconds (proxy only, default 30, 0 disables)
# 前置: 无
# 后置: 已到达远端 shell 提示符（locale 固定由公共帧完成，见 main.sh 段1.5）
# 退出码: 2 认证失败 / 连接不可达 / 超时 / 会话中断
# ------------------------------------------------------------
# 模式说明（调研 11.4 实测坑位）：
#   - 用 [Pp] 字符类而非 (?i)，规避 Expect gate keeper 优化导致大写 P 永不匹配
#   - 提示符/密码提示均锚定行尾 \s*$，避免误匹配命令回显
# 过代理说明（详见 README「过代理连接」，均为建议，框架不解析 PROXY_COMMAND 内容）：
#   - PROXY_COMMAND 存在且非空时注入 -o ProxyCommand；telnet 不支持过代理
#   - 过代理易被空闲切断（调研坑点 3），默认 ServerAliveInterval=30，SSH_KEEPALIVE 可覆盖（0=关闭）

if {![info exists env(AUTH_PASS)]} { die 1 "missing env AUTH_PASS" }

set _ssh_opts [list -p $port -o ConnectTimeout=10]
set _proxy 0
if {[info exists env(PROXY_COMMAND)] && $env(PROXY_COMMAND) ne ""} {
    set _proxy 1
    lappend _ssh_opts -o "ProxyCommand=$env(PROXY_COMMAND)"
    set _ka 30
    if {[info exists env(SSH_KEEPALIVE)]} { set _ka $env(SSH_KEEPALIVE) }
    lappend _ssh_opts -o "ServerAliveInterval=$_ka"
}
if {$_proxy} {
    log_info "spawn ssh -p $port $auth_user@$host (via ProxyCommand)"
} else {
    log_info "spawn ssh -p $port $auth_user@$host (direct)"
}
spawn {*}[concat [list ssh] $_ssh_opts [list $auth_user@$host]]

set _auth_tries 0
expect {
    -re {[Pp]ermission [Dd]enied|Host key verification failed} {
        puts stderr "AUTH_DENIED"
        exit 2
    }
    -re {Connection (refused|timed out|reset|closed)|No route to host|Network is unreachable} {
        puts stderr "AUTH_UNREACHABLE"
        exit 2
    }
    -re {yes/no} {
        send "yes\r"
        exp_continue
    }
    -re {[Pp]assword\s*[:：]\s*$} {
        # 单次失败即退出，防止连续错密触发账号锁定（调研 6.1 场景 E）
        if {[incr _auth_tries] > 1} { puts stderr "AUTH_DENIED"; exit 2 }
        log_info "password prompt hit, sending AUTH_PASS"
        log_user 0
        send -- "$env(AUTH_PASS)\r"
        exp_continue
    }
    -re {[%#$>]\s*$} {
        log_user 1
        log_info "auth ok, remote prompt reached"
    }
    timeout { puts stderr "AUTH_TIMEOUT"; exit 2 }
    eof     { puts stderr "AUTH_EOF";     exit 2 }
}

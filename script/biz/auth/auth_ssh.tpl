# ------------------------------------------------------------
# 段1 认证 · ssh —— SSH 密码登录（全脚本唯一 spawn 点）
# REQUIRE_ENV: AUTH_PASS
# REQUIRE_ARGV: host target host address
# REQUIRE_ARGV: port SSH port (e.g. 22)
# REQUIRE_ARGV: auth_user SSH login username
# 前置: 无
# 后置: 已到达远端 shell 提示符（locale 固定由公共帧完成，见 main.sh 段1.5）
# 退出码: 2 认证失败 / 连接不可达 / 超时 / 会话中断
# ------------------------------------------------------------
# 模式说明（调研 11.4 实测坑位）：
#   - 用 [Pp] 字符类而非 (?i)，规避 Expect gate keeper 优化导致大写 P 永不匹配
#   - 提示符/密码提示均锚定行尾 \s*$，避免误匹配命令回显

if {![info exists env(AUTH_PASS)]} { die 1 "missing env AUTH_PASS" }

log_info "spawn ssh -p $port -o ConnectTimeout=10 $auth_user@$host"
spawn ssh -p $port -o ConnectTimeout=10 $auth_user@$host

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

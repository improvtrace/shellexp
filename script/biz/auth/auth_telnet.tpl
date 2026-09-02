# ------------------------------------------------------------
# 段1 认证 · telnet —— Telnet 密码登录（全脚本唯一 spawn 点）
# REQUIRE_ENV: AUTH_PASS
# REQUIRE_ARGV: host target host address
# REQUIRE_ARGV: port telnet port (e.g. 23)
# REQUIRE_ARGV: auth_user login username
# 前置: 无
# 后置: 已到达远端 shell 提示符（locale 固定由公共帧完成，见 main.sh 段1.5）
# 退出码: 2 认证失败 / 连接不可达 / 超时 / 会话中断
# 安全警告: Telnet 明文传输凭据，仅限独立管理网/带外网使用（调研 5.4）
# ------------------------------------------------------------

if {![info exists env(AUTH_PASS)]} { die 1 "missing env AUTH_PASS" }

log_info "spawn telnet $host $port"
spawn telnet $host $port

set _login_tries 0
set _pass_tries 0
expect {
    -re {Connection refused|Unable to connect|No route to host|Network is unreachable|Connection timed out|Connection closed by foreign host} {
        puts stderr "AUTH_UNREACHABLE"
        exit 2
    }
    -re {(Login|Username|login)\s*[:：]\s*$} {
        # 登录名提示反复出现视为认证失败（单次失败即退出，防锁定）
        if {[incr _login_tries] > 1} { puts stderr "AUTH_DENIED"; exit 2 }
        log_info "login prompt hit, sending auth_user"
        send -- "$auth_user\r"
        exp_continue
    }
    -re {[Pp]assword\s*[:：]\s*$} {
        if {[incr _pass_tries] > 1} { puts stderr "AUTH_DENIED"; exit 2 }
        log_info "password prompt hit, sending AUTH_PASS"
        log_user 0
        send -- "$env(AUTH_PASS)\r"
        exp_continue
    }
    -re {Login incorrect|认证失败} {
        puts stderr "AUTH_DENIED"
        exit 2
    }
    -re {[%#$>]\s*$} {
        log_user 1
        log_info "auth ok, remote prompt reached"
    }
    timeout { puts stderr "AUTH_TIMEOUT"; exit 2 }
    eof     { puts stderr "AUTH_EOF";     exit 2 }
}

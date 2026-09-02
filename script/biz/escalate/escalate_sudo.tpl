# ------------------------------------------------------------
# 段2 提权 · sudo —— sudo -S -i 提权为 root（输入的是当前登录用户的密码）
# REQUIRE_ENV: ESCALATE_PASS
# 前置: 已到达远端 shell 提示符（认证段完成）
# 退出码: 7 提权失败 / 超时 / 会话中断
# 注意: NOPASSWD 白名单场景无密码提示，直接命中提示符分支
# ------------------------------------------------------------

if {![info exists env(ESCALATE_PASS)]} { die 1 "missing env ESCALATE_PASS" }

log_info "escalate: sudo -S -i"
send "sudo -S -i\r"

set _sudo_tries 0
expect {
    -re {not in the sudoers|sudo: 1 incorrect|[Ss]orry, try again|认证失败} {
        puts stderr "ESCALATE_DENIED"
        exit 7
    }
    -re {\[sudo\]\s*[Pp]assword|[Pp]assword\s*[:：]\s*$} {
        if {[incr _sudo_tries] > 1} { puts stderr "ESCALATE_DENIED"; exit 7 }
        log_info "sudo password prompt hit"
        log_user 0
        send -- "$env(ESCALATE_PASS)\r"
        exp_continue
    }
    -re {[%#$>]\s*$} {
        log_user 1
        log_info "escalated to root via sudo"
    }
    timeout { puts stderr "ESCALATE_TIMEOUT"; exit 7 }
    eof     { puts stderr "ESCALATE_EOF";     exit 7 }
}

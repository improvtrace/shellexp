# ------------------------------------------------------------
# 段2 提权 · su —— su - 切换目标身份（输入的是目标身份的密码）
# REQUIRE_ENV: ESCALATE_PASS
# REQUIRE_ARGV: escalate_user target user to su into
# 前置: 已到达远端 shell 提示符（认证段完成）
# 退出码: 7 提权失败 / 超时 / 会话中断
# 注意: root 登录时 su 到普通用户无需密码，直接命中提示符分支
# ------------------------------------------------------------

if {![info exists env(ESCALATE_PASS)]} { die 1 "missing env ESCALATE_PASS" }

log_info "escalate: su - $escalate_user"
send "su - $escalate_user\r"

set _su_tries 0
expect {
    -re {su: [Aa]uthentication [Ff]ailure|su: [Ss]orry|[Ii]ncorrect [Pp]assword|认证失败|Unknown id|does not exist|no passwd entry} {
        puts stderr "ESCALATE_DENIED"
        exit 7
    }
    -re {[Pp]assword\s*[:：]\s*$} {
        if {[incr _su_tries] > 1} { puts stderr "ESCALATE_DENIED"; exit 7 }
        log_info "su password prompt hit"
        log_user 0
        send -- "$env(ESCALATE_PASS)\r"
        exp_continue
    }
    -re {[%#$>]\s*$} {
        log_user 1
        log_info "escalated to $escalate_user via su"
    }
    timeout { puts stderr "ESCALATE_TIMEOUT"; exit 7 }
    eof     { puts stderr "ESCALATE_EOF";     exit 7 }
}

# ------------------------------------------------------------
# 段3 业务 · password/passwd —— 交互式 passwd 改密兜底（中英双语提示）
# REQUIRE_ENV: NEW_PASS
# REQUIRE_ARGV: target_user user whose password to change
# 可选环境变量: OLD_PASS —— 非 root 上下文自改密码时需提供当前密码
# 前置: 会话已具备 root 权限（直登 root 或经提权段），或为本人自改
# 退出码: 6 业务失败（含策略拒绝熔断，最多 3 轮，调研 6.2）
# 说明: send 直写 pty、不经远端 shell 解析，新密码无需单引号转义
# ------------------------------------------------------------

if {![info exists env(NEW_PASS)]} { die 1 "missing env NEW_PASS" }

log_info "biz: passwd for $target_user"
send "passwd $target_user\r"

set _retry 0
expect {
    -re {(Current|当前的)\s*[Pp]assword\s*[:：]} {
        if {![info exists env(OLD_PASS)]} {
            puts stderr "BIZ_FAIL: prompted for current password but env OLD_PASS not set"
            exit 6
        }
        log_user 0
        send -- "$env(OLD_PASS)\r"
        exp_continue
    }
    -re {(New|新的|新增|输入新的)\s*[Pp]assword\s*[:：]} {
        log_user 0
        send -- "$env(NEW_PASS)\r"
        exp_continue
    }
    -re {(Retype|重新输入|再次输入|确认).*[Pp]assword\s*[:：]} {
        send -- "$env(NEW_PASS)\r"
        exp_continue
    }
    -re {BAD PASSWORD|未通过|字典|过于简单|too similar|simplistic|dictionary word|is too short} {
        if {[incr _retry] >= 3} {
            puts stderr "BIZ_FAIL: password policy rejected after 3 attempts"
            exit 6
        }
        exp_continue
    }
    -re {updated successfully|密码.*成功} { }
    timeout { log_user 1; puts stderr "BIZ_TIMEOUT"; exit 6 }
    eof     { log_user 1; puts stderr "BIZ_EOF";     exit 6 }
}
log_user 1
log_info "biz: password changed for $target_user"

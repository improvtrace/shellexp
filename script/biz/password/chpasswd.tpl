# ------------------------------------------------------------
# 段3 业务 · password/chpasswd —— 非交互改密（首选路线，调研 6.1 路线 A）
# REQUIRE_ENV: NEW_PASS
# REQUIRE_ARGV: target_user 改密目标用户名
# 前置: 会话已具备 root 权限（直登 root 或经提权段）
# 判定: 以退出码标记 BIZRC_<ts>=rc 判定成败，规避回显/语言/发行版差异（调研 3.3）
# 退出码: 6 业务失败
# ------------------------------------------------------------

if {![info exists env(NEW_PASS)]} { die 1 "missing env NEW_PASS" }

set _tu [quote_single $target_user]
set _np [quote_single $env(NEW_PASS)]
set _marker "BIZRC_[clock clicks]"

log_info "biz: chpasswd for $target_user"
# 命令行内嵌密码：先关回显再 send，防止密码进入屏幕/会话日志（调研 6.5）
log_user 0
send "echo '$_tu:$_np' | chpasswd; echo $_marker=\$?\r"

expect {
    -re "$_marker=(\[0-9\]+)" {
        log_user 1
        set _rc $expect_out(1,string)
        if {$_rc == 0} {
            log_info "biz: password changed for $target_user (rc=0)"
        } else {
            puts stderr "BIZ_FAIL: chpasswd rc=$_rc"
            exit 6
        }
    }
    timeout { log_user 1; puts stderr "BIZ_TIMEOUT"; exit 6 }
    eof     { log_user 1; puts stderr "BIZ_EOF";     exit 6 }
}

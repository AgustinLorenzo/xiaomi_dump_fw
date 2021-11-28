--
-- Use nettb to detect whether there is IP conflict
-- If there is IP conflict
-- 1. Modify configuration files
-- 2. Restart related services
--

local fs    = require("nixio.fs")
local nixio = require("nixio")
local posix = require("posix")
local util  = require("luci.util")
local box   = require("xiaoqiang.module.XQMessageBox")

function log(...)
    posix.openlog("ip-conflict", LOG_NDELAY, LOG_USER)
    for i, v in ipairs({...}) do
        posix.syslog(4, util.serialize_data(v))
    end
    posix.closelog()
end

local pidfile = "/tmp/mi_ip_conflict_pid"

function main()
    local sys = require("xiaoqiang.util.XQSysUtil")
    local conflict = require("xiaoqiang.module.XQIPConflict")
    --local restart = tonumber(arg[1])
    local pid = fs.readfile(pidfile)
    if pid and pid ~= "" then
        local code = os.execute("kill -0 "..tostring(pid).." 2>/dev/null")
        if code == 0 then
            return
        end
    end
    log("cr_ip_conflict start")
    pid = nixio.getpid()
    fs.writefile(pidfile, pid)

    local ip = conflict.ip_conflict_detection()
    if sys.getInitInfo() and ip then
        log("There is IP conflict")
        box.addMessage({["type"] = 4, ["data"]={["ip"] = ip}})
        -- conflict.ip_conflict_resolution()
        -- log("Modify configuration files")
        -- if restart and restart == 1 then
        --     log("Restart related services")
        --     conflict.restart_services()
        -- end
    else
        if not ip then
            box.removeMessage(4)
        end
        log("No IP conflict")
    end
end

main()
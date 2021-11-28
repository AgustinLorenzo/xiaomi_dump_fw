local fs    = require("nixio.fs")
local nixio = require("nixio")
local fun   = require("xiaoqiang.common.XQFunction")

local pidfile = "/tmp/iperf_script_pid"

local opt = arg[1]

function start()
    local pid = fs.readfile(pidfile)
    if pid and pid ~= "" then
        local code = os.execute("kill -0 "..tostring(pid))
        if code == 0 then
            return
        end
    end
    pid = nixio.getpid()
    fs.writefile(pidfile, pid)
    fun.forkExec("iperf -s 2>/dev/null")
    os.execute("sleep 60; killall iperf 2>/dev/null")
end

function stop()
    local pid = fs.readfile(pidfile)
    os.execute("killall iperf; kill -9 "..pid)
end

if opt and opt == "start" then
    start()
elseif opt and opt == "stop" then
    stop()
end


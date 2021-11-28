local fs    = require("nixio.fs")
local nixio = require("nixio")

local pidfile = "/tmp/speed_test_pid"

function speed_test()
    local testmodule = require("xiaoqiang.module.XQNetworkSpeedTest")
    local uspeed, dspeed = testmodule.syncSpeedTest()
    if uspeed and dspeed then
        testmodule.saveSpeedTestResult(uspeed, dspeed)
    else
        testmodule.saveSpeedTestResult(-1, -1)
    end
end

function main()
    local pid = fs.readfile(pidfile)
    if pid and pid ~= "" then
        local code = os.execute("kill -0 "..tostring(pid))
        if code == 0 then
            return
        end
    end
    pid = nixio.getpid()
    fs.writefile(pidfile, pid)
    speed_test()
end

main()
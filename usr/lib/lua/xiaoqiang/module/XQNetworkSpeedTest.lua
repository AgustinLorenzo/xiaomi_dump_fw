module ("xiaoqiang.module.XQNetworkSpeedTest", package.seeall)

local LuciUtil = require("luci.util")
local XQFunction = require("xiaoqiang.common.XQFunction")

-- KB/S
function uploadSpeedTest()
    local speedtest = "/usr/bin/upload_speedtest"
    local speed
    for _, line in ipairs(LuciUtil.execl(speedtest)) do
        if not XQFunction.isStrNil(line) and line:match("^avg tx:") then
            speed = line:match("^avg tx:(%S+)")
            if speed then
                speed = tonumber(string.format("%.2f",speed/8))
            end
            break
        end
    end
    return speed
end

-- KB/S
function downloadSpeedTest()
    local speedtest = "/usr/bin/download_speedtest"
    local speed
    for _, line in ipairs(LuciUtil.execl(speedtest)) do
        if not XQFunction.isStrNil(line) and line:match("^avg rx:") then
            speed = line:match("^avg rx:(%S+)")
            if speed then
                speed = tonumber(string.format("%.2f",speed/8))
            end
            break
        end
    end
    return speed
end

function saveSpeedTestResult(uspeed, dspeed)
    local XQPreference = require("xiaoqiang.XQPreference")
    if uspeed and dspeed and tonumber(uspeed) and tonumber(dspeed) then
        XQPreference.set("UPLOAD_SPEED", tostring(uspeed))
        XQPreference.set("DOWNLOAD_SPEED", tostring(dspeed))
    end
end

function getSpeedTestResult()
    local XQPreference = require("xiaoqiang.XQPreference")
    local uspeed = tonumber(XQPreference.get("UPLOAD_SPEED"))
    local dspeed = tonumber(XQPreference.get("DOWNLOAD_SPEED"))
    if uspeed and dspeed then
        if uspeed > 0 and dspeed > 0  then
            return uspeed, dspeed
        elseif uspeed == 0 or dspeed == 0 then
            return 0, 0
        else
            return nil, nil
        end
    else
        return nil, nil
    end
end

-- use speedtest script, return in 15s
function speedTest()
    local result = {}
    local cmd = "/usr/bin/speedtest"
    for _, line in ipairs(LuciUtil.execl(cmd)) do
        if not XQFunction.isStrNil(line) then
            table.insert(result, tonumber(line:match("rx:(%S+)")))
        end
    end
    local uspeed, dspeed
    if #result > 0 then
        local speed = 0
        for _, value in ipairs(result) do
            speed = speed + tonumber(value)
        end
        dspeed = speed/#result
    end
    if dspeed then
        math.randomseed(tostring(os.time()):reverse():sub(1, 6))
        uspeed = tonumber(string.format("%.2f",dspeed/math.random(8, 11)))
    end
    return uspeed, dspeed
end

function asyncSpeedTest()
    saveSpeedTestResult(0, 0)
    XQFunction.forkExec("lua /usr/sbin/speed_test.lua")
end

function syncSpeedTest()
    local uspeed = uploadSpeedTest()
    local dspeed = downloadSpeedTest()
    return uspeed, dspeed
end
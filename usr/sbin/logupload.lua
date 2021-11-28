#!/usr/bin/lua

local fs    = require("nixio.fs")
local net   = require("xiaoqiang.util.XQNetUtil")
local util  = require("luci.util")
local nixio = require("nixio")
local posix = require("posix")

local pidfile   = "/tmp/log_upload_pid"
local logtmp    = "/tmp/log.zip"
local filepath  = "/data/usr/log/log.zip"

local INTERVAL  = 300

function upload(force, retries)
    if not force or not retries then
        return
    end
    repeat
        -- wake up the system if necessary
        os.execute("killall -s 10 noflushd 2>/dev/null")

        if fs.access(filepath) then
            local suc, res = pcall(net.uploadLogFile, filepath, "B")
            if suc and res then
                fs.remove(filepath)
                break
            end
        else
            if force == 1 then
                os.execute("/sbin/flash_led 3 & 2>/dev/null")
                os.execute("/usr/sbin/log_collection.sh")
                if fs.access(logtmp) then
                    local suc, res = pcall(net.uploadLogFile, logtmp, "B")
                    if not suc or not res then
                        os.execute("rm -rf /data/usr/log/*.gz 2>/dev/null")
                        fs.move(logtmp, filepath)
                    else
                        break
                    end
                end
                os.execute("pkill flash_led")
		os.execute("gpio 1 1")
		os.execute("gpio 2 1")
                os.execute("gpio 3 0")
            else
                break
            end
        end
        retries = retries - 1
        if retries > 0 then
            os.execute("sleep "..tostring(INTERVAL))
        end
    until retries <= 0
end

-- force: (1) run log_collection.sh if log.zip does not exist
function main()
    local force   = 1
    local retries = 1
    local gpio    = 0
    if #arg == 3 then
        force   = tonumber(arg[1])
        retries = tonumber(arg[2])
        gpio    = tonumber(arg[3])
    end
    if #arg == 4 then
        force   = tonumber(arg[1])
        retries = tonumber(arg[2])
        gpio    = tonumber(arg[3])
	filepath = arg[4]
    end
    -- singleton
    local pid = fs.readfile(pidfile)
    if pid and pid ~= "" then
        local code = os.execute("kill -0 "..tostring(pid))
        if code == 0 then
            return 0
        end
    end
    pid = nixio.getpid()
    fs.writefile(pidfile, pid)
    upload(force, retries)
    if gpio == 1 then
		os.execute("gpio 1 1")
		os.execute("gpio 2 1")
		os.execute("gpio 3 0")
    end
end

main()

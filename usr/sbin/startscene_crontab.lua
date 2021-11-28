#!/usr/bin/lua

local w = arg[1];
local t = arg[2];

local LuciFs = require("luci.fs")
local XQLog = require("xiaoqiang.XQLog")

function getCurrentPID()
    local stat = LuciFs.readfile("/proc/self/stat")
    local pid = ""
    if stat then
       _,_,pid = stat:find("^(%d+)%s.+")
    end
    return pid 
end

function writePID()
    local pid = getCurrentPID()
    if pid then 
        LuciFs.writefile("/tmp/startscene_crontab.lua.PID",pid)
    end
end

function isRunning()
    local pid = LuciFs.readfile("/tmp/startscene_crontab.lua.PID")
    if pid then
        return LuciFs.access("/proc/".. pid )
    end
    return false
end

function sendSmartControllerRequest(payload1)
    local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")
    local XQConfigs = require("xiaoqiang.common.XQConfigs")
    local payload = XQCryptoUtil.binaryBase64Enc(payload1)
    local cmd = XQConfigs.THRIFT_TUNNEL_TO_SMARTHOME_CONTROLLER:format(payload)
    local LuciUtil = require("luci.util")
    LuciUtil.exec(cmd)
end

if isRunning() then
    XQLog.log(2,"startscene_crontab.lua is running.. exit..")
else
    writePID()
    if t ~= "" and w ~= "" then
        if tonumber(w) == 7 then
            w = 0
        end
        sendSmartControllerRequest("{\"command\":\"scene_start_by_crontab\",\"time\":\"" .. t .. "\", \"week\": " .. w .. "}");
    end
end

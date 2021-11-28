#!/usr/bin/lua

local action = arg[1];
local sta = arg[2];

function sendSmartControllerRequest(payload1)
    local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")
    local XQConfigs = require("xiaoqiang.common.XQConfigs")
    local payload = XQCryptoUtil.binaryBase64Enc(payload1)
    local cmd = XQConfigs.THRIFT_TUNNEL_TO_SMARTHOME_CONTROLLER:format(payload)
    local LuciUtil = require("luci.util")
    LuciUtil.exec(cmd)
end

function sendMiioRequest(payload1)
    local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")
    local XQConfigs = require("xiaoqiang.common.XQConfigs")
    local payload = XQCryptoUtil.binaryBase64Enc(payload1)
    local cmd = XQConfigs.THRIFT_TUNNEL_TO_MIIO:format(payload)
    local LuciUtil = require("luci.util")
    LuciUtil.exec(cmd)
end

if sta ~= "" then
   if action == "ASSOC" then
        sendSmartControllerRequest("{\"command\":\"scene_start_by_device_status\",\"mac\":\"" .. sta .. "\", \"connected\":true}");
        sendMiioRequest("{\"command\":\"iwevent_connect\",\"mac\":\"" .. sta .. "\"}")
    elseif action == "DISASSOC" then
        sendSmartControllerRequest("{\"command\":\"scene_start_by_device_status\",\"mac\":\"" .. sta .. "\", \"connected\":false}");
        sendMiioRequest("{\"command\":\"iwevent_disconnect\",\"mac\":\"" .. sta .. "\"}")
    end
end

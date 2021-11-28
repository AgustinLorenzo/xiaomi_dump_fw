module ("xiaoqiang.module.XQRouterStatus", package.seeall)

local LuciUtil = require("luci.util")
local XQFunction = require("xiaoqiang.common.XQFunction")
local XQConfigs = require("xiaoqiang.common.XQConfigs")

local function _getUsbStatus()
    local result = {}
    local extdisk = XQFunction.thrift_tunnel_to_datacenter([[{"api":1}]])
    if extdisk and extdisk.code == 0 then
        if extdisk.exist == 1 then
            local usbinfo = XQFunction.thrift_tunnel_to_datacenter([[{"api":62}]])
            if usbinfo and usbinfo.code == 0 then
                result["status"] = usbinfo.status
                result["progress"] = usbinfo.progress
            else
                result["status"] = -1
                result["progress"] = 0
            end
            result["extdisk"] = 1
        else
            result["extdisk"] = 0
            result["status"] = 0
            result["progress"] = 0
        end
    else
        result["status"] = 0
        result["progress"] = 0
        result["extdisk"] = 0
    end
    return result
end

local function _getWanStatus()
    local result = {}
    local XQDeviceUtil = require("xiaoqiang.util.XQDeviceUtil")
    local wan = XQDeviceUtil.getWanLanNetworkStatistics("wan")
    if wan then
        result["speed"] = tonumber(wan.downspeed) or 0
        result["maxspeed"] = tonumber(wan.maxdownloadspeed) or 0
    else
        result["speed"] = 0
        result["maxspeed"] = 0
    end
    return result
end

local function _getDevStatus()
    local result = {}
    local XQDeviceUtil = require("xiaoqiang.util.XQDeviceUtil")
    local online, all, online_without_mash, all_without_mash = XQDeviceUtil.getDeviceCount()
    result["online"] = online
    result["all"] = all
    result["online_without_mash"] = online_without_mash
    result["all_without_mash"] = all_without_mash
    return result
end

local FUNCTIONS = {
    ["usb_status"] = _getUsbStatus,
    ["wan_status"] = _getWanStatus,
    ["dev_status"] = _getDevStatus
}

function getStatus(keystr)
    local status = {}
    if XQFunction.isStrNil(keystr) then
        for key, fun in pairs(FUNCTIONS) do
            status[key] = fun()
        end
    else
        local keys = LuciUtil.split(keystr, ",")
        if keys then
            for _, key in ipairs(keys) do
                local info
                local fun = FUNCTIONS[key]
                if fun then
                    info = fun()
                end
                if info then
                    status[key] = info
                end
            end
        end
    end
    return status
end
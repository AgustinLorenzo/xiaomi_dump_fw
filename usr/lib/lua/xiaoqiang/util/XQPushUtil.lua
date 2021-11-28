module ("xiaoqiang.util.XQPushUtil", package.seeall)

local XQFunction    = require("xiaoqiang.common.XQFunction")

-- 2015.7.31, auth default: false->true (PM:cy)
-- level :1/2/3 low/middle/high
function pushSettings()
    local uci = require("luci.model.uci").cursor()
    local result = {
        ["auth"]    = true,
        ["quiet"]   = false,
        ["level"]   = 2
    }
    local settings = uci:get_all("devicelist", "settings")
    local authfail = uci:get_all("devicelist", "authfail")
    local loginauthfail = uci:get_all("devicelist", "loginauthfail")
    local count = 0
    if authfail then
        for key, value in pairs(authfail) do
            if key and tonumber(value) and not key:match("^%.") then
                count = count + tonumber(value)
            end
        end
    end
    if loginauthfail then
        for key, value in pairs(loginauthfail) do
            if key and tonumber(value) and not key:match("^%.") then
                count = count + tonumber(value)
            end
        end
    end
    result["count"] = count
    if settings then
        if tonumber(settings.auth) == 0 then
            result.auth = false
        else
            result.auth = true
        end
        result.quiet    = tonumber(settings.quiet) == 1 and true or false
        result.level    = tonumber(settings.level) or 2
     end
    return result
end

-- key:auth/quiet value:0/1
-- key:level value:1/2/3
function pushConfig(key, value)
    local uci = require("luci.model.uci").cursor()
    local settings = uci:get_all("devicelist", "settings")
    if settings then
        settings[key] = value
    else
        settings = {}
        settings[key] = value
    end
    uci:section("devicelist", "core", "settings", settings)
    uci:commit("devicelist")
end

function getTimestamp(key)
    local uci = require("luci.model.uci").cursor()
    local timestamp = uci:get("devicelist", "timestamp", key)
    return tonumber(timestamp) or 0
end

function setTimestamp(key, timestamp)
    if not key or not timestamp then
        return
    end
    local uci = require("luci.model.uci").cursor()
    local timestamps = uci:get_all("devicelist", "timestamp")
    if not timestatmps then
        timestamps = {}
    end
    timestamps[key] = timestamp
    uci:section("devicelist", "record", "timestamp", timestamps)
    if not uci:commit("devicelist") then
    	return false
    end
    return true
end

function getAuthenFailedTimesDict()
    local uci = require("luci.model.uci").cursor()
    local authfail = uci:get_all("devicelist", "authfail")
    return authfail or {}
end

function getwifiauthfailedserialtimes(mac)
    if XQFunction.isStrNil(mac) then
        return
    else
        mac = XQFunction.macFormat(mac)
    end
    local uci = require("luci.model.uci").cursor()
    local mackey = mac:gsub(":", "")
    if not uci:get_all("devicelist", "authfailserial") then
        uci:section("devicelist", "record", "authfailserial", {})
        uci:commit("devicelist")
        return 0
    else
        local failed = uci:get("devicelist", "authfailserial", mackey)
        if failed and tonumber(failed) then
            return tonumber(failed)
        else
            return 0
        end
    end
end


--for kindle check every 5min
function setwifiauthfailedserialtimes(mac, times)
    if XQFunction.isStrNil(mac) or not tonumber(times) then
        return
    else
        mac = XQFunction.macFormat(mac)
    end
    local uci = require("luci.model.uci").cursor()
    local mackey = mac:gsub(":", "")
    local authfail = uci:get_all("devicelist", "authfailserial")
    if not authfail then
        authfail = {}
    end
    authfail[mackey] = times
    uci:section("devicelist", "record", "authfailserial", authfail)
    uci:commit("devicelist")
end

function getAuthenFailedTimes(mac)
    if XQFunction.isStrNil(mac) then
        return
    else
        mac = XQFunction.macFormat(mac)
    end
    local uci = require("luci.model.uci").cursor()
    local mackey = mac:gsub(":", "")
    if not uci:get_all("devicelist", "authfail") then
        uci:section("devicelist", "record", "authfail", {})
        uci:commit("devicelist")
        return 0
    else
        local failed = uci:get("devicelist", "authfail", mackey)
        if failed and tonumber(failed) then
            return tonumber(failed)
        else
            return 0
        end
    end
end

function setAuthenFailedTimes(mac, times)
    if XQFunction.isStrNil(mac) or not tonumber(times) then
        return
    else
        mac = XQFunction.macFormat(mac)
    end
    local uci = require("luci.model.uci").cursor()
    local mackey = mac:gsub(":", "")
    local authfail = uci:get_all("devicelist", "authfail")
    if not authfail then
        authfail = {}
    end
    authfail[mackey] = times
    uci:section("devicelist", "record", "authfail", authfail)
    uci:commit("devicelist")
end

function getWifiAuthenFailedFrequencyDict()
    local uci = require("luci.model.uci").cursor()
    local wififrequency = uci:get_all("devicelist", "wififrequency")
    return wififrequency or {}
end

function getWifiAuthenFailedFrequency(mac)
    if XQFunction.isStrNil(mac) then
        return
    else
        mac = XQFunction.macFormat(mac)
    end
    local uci = require("luci.model.uci").cursor()
    local mackey = mac:gsub(":", "")
    if not uci:get_all("devicelist", "wififrequency") then
        uci:section("devicelist", "record", "wififrequency", {})
        uci:commit("devicelist")
        return 0
    else
        local frequency = uci:get("devicelist", "wififrequency", mackey)
        if frequency and tonumber(frequency) then
            return tonumber(frequency)
        else
            return 0
        end
    end
end

function setWifiAuthenFailedFrequency(mac, fre)
    if XQFunction.isStrNil(mac) or not tonumber(fre) then
        return
    else
        mac = XQFunction.macFormat(mac)
    end
    local uci = require("luci.model.uci").cursor()
    local mackey = mac:gsub(":", "")
    local authfail = uci:get_all("devicelist", "wififrequency")
    if not authfail then
        authfail = {}
    end
    authfail[mackey] = fre
    uci:section("devicelist", "record", "wififrequency", authfail)
    uci:commit("devicelist")
end

function getLoginAuthenFailedTimes(mac)
    if XQFunction.isStrNil(mac) then
        return
    else
        mac = XQFunction.macFormat(mac)
    end
    local uci = require("luci.model.uci").cursor()
    local mackey = mac:gsub(":", "")
    if not uci:get_all("devicelist", "loginauthfail") then
        uci:section("devicelist", "record", "loginauthfail", {})
        uci:commit("devicelist")
        return 0
    else
        local failed = uci:get("devicelist", "loginauthfail", mackey)
        if failed and tonumber(failed) then
            return tonumber(failed)
        else
            return 0
        end
    end
end

function setLoginAuthenFailedTimes(mac, times)
    if XQFunction.isStrNil(mac) or not tonumber(times) then
        return
    else
        mac = XQFunction.macFormat(mac)
    end
    local uci = require("luci.model.uci").cursor()
    local mackey = mac:gsub(":", "")
    local authfail = uci:get_all("devicelist", "loginauthfail")
    if not authfail then
        authfail = {}
    end
    authfail[mackey] = times
    uci:section("devicelist", "record", "loginauthfail", authfail)
    uci:commit("devicelist")
end

function getLoginAuthenFailedFrequency(mac)
    if XQFunction.isStrNil(mac) then
        return
    else
        mac = XQFunction.macFormat(mac)
    end
    local uci = require("luci.model.uci").cursor()
    local mackey = mac:gsub(":", "")
    if not uci:get_all("devicelist", "loginfrequency") then
        uci:section("devicelist", "record", "loginfrequency", {})
        uci:commit("devicelist")
        return 0
    else
        local frequency = uci:get("devicelist", "loginfrequency", mackey)
        if frequency and tonumber(frequency) then
            return tonumber(frequency)
        else
            return 0
        end
    end
end

function setLoginAuthenFailedFrequency(mac, fre)
    if XQFunction.isStrNil(mac) or not tonumber(fre) then
        return
    else
        mac = XQFunction.macFormat(mac)
    end
    local uci = require("luci.model.uci").cursor()
    local mackey = mac:gsub(":", "")
    local authfail = uci:get_all("devicelist", "loginfrequency")
    if not authfail then
        authfail = {}
    end
    authfail[mackey] = fre
    uci:section("devicelist", "record", "loginfrequency", authfail)
    uci:commit("devicelist")
end

-- Special device management
function specialNotify(mac)
    if XQFunction.isStrNil(mac) then
        return false, 0
    else
        mac = XQFunction.macFormat(mac)
    end
    local uci = require("luci.model.uci").cursor()
    local mackey = mac:gsub(":", "")
    local record = uci:get("devicelist", "notify", mackey)
    if record and tonumber(record) then
        return true, tonumber(record)
    end
    return false, 0
end

function setSpecialNotify(mac, enable, timestamp)
    if XQFunction.isStrNil(mac) and tonumber(timestamp) then
        return false
    else
        mac = XQFunction.macFormat(mac)
    end
    local uci = require("luci.model.uci").cursor()
    local mackey = mac:gsub(":", "")
    if not uci:get_all("devicelist", "notify") then
        uci:section("devicelist", "record", "notify", {})
        if not uci:commit("devicelist") then
        	return false
        end
    end
    if enable then
        local record = uci:get("devicelist", "notify", mackey)
        if not record then
            uci:set("devicelist", "notify", mackey, 1)
	        if not uci:commit("devicelist") then
	        	return false
	        end
        else
            uci:set("devicelist", "notify", mackey, timestamp)
	        if not uci:commit("devicelist") then
	        	return false
	        end
        end
    else
        uci:delete("devicelist", "notify", mackey)
        if not uci:commit("devicelist") then
        	return false
        end
    end
    return true
end

function notifyDict()
    local dict = {}
    local uci = require("luci.model.uci").cursor()
    local notify = uci:get_all("devicelist", "notify")
    if notify then
        for key, value in pairs(notify) do
            if tonumber(value) then
                dict[key] = 1
            end
        end
    end
    return dict
end

-- Admin device management
function getAdminDevice(mackey)
    local uci = require("luci.model.uci").cursor()
    if mackey then
        return tonumber(uci:get("devicelist", "admin", mackey))
    end
    return nil
end

function getAdminDevices()
    local dict = {}
    local uci = require("luci.model.uci").cursor()
    local admin = uci:get_all("devicelist", "admin")
    if admin then
        for key, value in pairs(admin) do
            if tonumber(value) then
                dict[key] = tonumber(value)
            end
        end
    end
    return dict
end

function setAdminDevice(mackey, timestamp)
    local uci = require("luci.model.uci").cursor()
    if not uci:get_all("devicelist", "admin") then
        uci:section("devicelist", "record", "admin", {})
        uci:commit("devicelist")
    end
    if uci:get("devicelist", "admin", mackey) then
        if tonumber(timestamp) then
            uci:set("devicelist", "admin", mackey, timestamp)
        end
    else
        uci:set("devicelist", "admin", mackey, timestamp or "0")
    end
    uci:commit("devicelist")
end

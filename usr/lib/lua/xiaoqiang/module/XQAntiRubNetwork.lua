module ("xiaoqiang.module.XQAntiRubNetwork", package.seeall)

local Nixio         = require("nixio")
local NixioFs       = require("nixio.fs")
local LuciSys       = require("luci.sys")

local XQFunction    = require("xiaoqiang.common.XQFunction")

local AUTHEN_FAILED_PATH = "/tmp/authenfailed-cache"

local AUTHEN_FAILED_THRESHOLD = {
    ["interval"]    = 60, -- 1 min
    ["blackltd"]    = 30, -- 30 sec
    ["wifi"]        = 30, -- wifi
    ["wifib"]       = 5 , -- wifi blacklisted event
    ["llogin"]      = 5,  -- login: low level
    ["hlogin"]      = 5   -- login: high level
}

--
-- Anti rub network
--
function _sane(file)
    return LuciSys.process.info("uid")
            == NixioFs.stat(file or AUTHEN_FAILED_PATH, "uid")
        and NixioFs.stat(file or AUTHEN_FAILED_PATH, "modestr")
            == (file and "rw-------" or "rwx------")
end

-- Prepare cache storage by creating the cache directory.
function _prepare()
    NixioFs.mkdir(AUTHEN_FAILED_PATH, 700)
    if not _sane() then
        return false
    end
end

function _read(id)
    local blob = NixioFs.readfile(AUTHEN_FAILED_PATH .. "/" .. id)
    return blob
end

-- Read a cache and return its content.
function read(id, expired)
    if not id or #id == 0 then
        return nil
    end

    local expiredtime = expired
    if not expiredtime then
        expiredtime = AUTHEN_FAILED_THRESHOLD.interval
    end

    if not _sane(AUTHEN_FAILED_PATH .. "/" .. id) then
        return nil
    end

    local blob = _read(id)
    local func = loadstring(blob)
    setfenv(func, {})

    local cache = func()
    if type(cache) ~= "table" then
        return nil
    end
    local time = LuciSys.uptime() - cache.atime or 0
    if time > expiredtime and time < expiredtime * 2 then
        cache["expired"] = true
        cache["old"] = false
        kill(id)
    elseif time > expiredtime * 2 then
        cache["expired"] = true
        cache["old"] = true
        kill(id)
    else
        cache["expired"] = false
        cache["old"] = false
    end
    return cache
end

function _write(id, data)
    local tempid = LuciSys.uniqueid(16)
    local tempfile = AUTHEN_FAILED_PATH .. "/" .. tempid
    local cachefile = AUTHEN_FAILED_PATH .. "/" .. id
    local f = Nixio.open(tempfile, "w", 600)
    f:writeall(data)
    f:close()
    NixioFs.rename(tempfile, cachefile)
end

-- Write cache data to a cache file.
function write(id, data)
    if not _sane() then
        _prepare()
    end

    if type(data) ~= "table" then
        return
    end

    _write(id, luci.util.get_bytecode(data))
end

-- Kills a cache
function kill(id)
    if id then
        NixioFs.unlink(AUTHEN_FAILED_PATH .. "/" .. id)
    end
end

-- Remove all expired cache data files
function reap()
    if _sane() then
        local id
        for id in NixioFs.dir(AUTHEN_FAILED_PATH) do
            read(id)
        end
    end
end

--key:login/wifi
function isIgnored(mac, key)
    if XQFunction.isStrNil(mac) or XQFunction.isStrNil(key) then
        return
    else
        mac = XQFunction.macFormat(mac)
    end
    local uci = require("luci.model.uci").cursor()
    local mackey = mac:gsub(":", "")
    if key == "login" then
        if not uci:get_all("devicelist", "login_ignore") then
            uci:section("devicelist", "record", "login_ignore", {})
            uci:commit("devicelist")
            return false
        else
            local ignored = uci:get("devicelist", "login_ignore", mackey)
            if ignored then
                return true
            else
                return false
            end
        end
    elseif key == "wifi" then
        if not uci:get_all("devicelist", "wifi_ignore") then
            uci:section("devicelist", "record", "wifi_ignore", {})
            uci:commit("devicelist")
            return false
        else
            local ignored = uci:get("devicelist", "wifi_ignore", mackey)
            if ignored then
                return true
            else
                return false
            end
        end
    end
end

--key:login/wifi
function ignoreDevice(mac, key)
    if XQFunction.isStrNil(mac) or XQFunction.isStrNil(key) then
        return
    else
        mac = XQFunction.macFormat(mac)
    end
    local uci = require("luci.model.uci").cursor()
    local mackey = mac:gsub(":", "")
    if key == "login" then
        if not uci:get_all("devicelist", "login_ignore") then
            uci:section("devicelist", "record", "login_ignore", {[mackey] = "1"})
            uci:commit("devicelist")
        else
            uci:set("devicelist", "login_ignore", mackey, "1")
            uci:commit("devicelist")
        end
    elseif key == "wifi" then
        if not uci:get_all("devicelist", "wifi_ignore") then
            uci:section("devicelist", "record", "wifi_ignore", {[mackey] = "1"})
            uci:commit("devicelist")
        else
            uci:set("devicelist", "wifi_ignore", mackey, "1")
            uci:commit("devicelist")
        end
    end
end

function setWifiAuthenFailedCache(mac)
    if XQFunction.isStrNil(mac) then
        return false
    end
    local mackey = "WIFI-"..mac:gsub(":", "")
    local data = {
        ["mac"]     = mac,
        ["count"]   = 1,
        ["warning"] = false,
        ["atime"]   = LuciSys.uptime()
    }
    write(mackey, data)
end

function getWifiAuthenFailedCache(mac)
    if XQFunction.isStrNil(mac) then
        return nil
    end
    local mackey = "WIFI-"..mac:gsub(":", "")
    local data = read(mackey)
    if data and not data.expired then
        data.count = data.count + 1
        write(mackey, data)
    end
    if data and data.expired and not data.old then
        if data.count >= AUTHEN_FAILED_THRESHOLD.wifi then
            data["warning"] = true
        end
    end
    return data
end

function wifiAuthenFailedAction(mac)
    local XQPushUtil = require("xiaoqiang.util.XQPushUtil")
    if XQFunction.isStrNil(mac) then
        return nil
    else
        mac = XQFunction.macFormat(mac)
    end
    if isIgnored(mac, "wifi") then
        return nil
    end
    local settings = XQPushUtil.pushSettings()
    local times = XQPushUtil.getAuthenFailedTimes(mac)
    if settings.auth then
        local cache = getWifiAuthenFailedCache(mac)
        if not cache then
            setWifiAuthenFailedCache(mac)
        else
            local rcount = math.floor(cache.count / 6)
            if cache.expired and cache.warning then
                XQPushUtil.setAuthenFailedTimes(mac, times + rcount)
                XQPushUtil.setWifiAuthenFailedFrequency(mac, rcount)
                XQPushUtil.setwifiauthfailedserialtimes(mac, XQPushUtil.getwifiauthfailedserialtimes(mac) + 1)
                return rcount
            elseif cache.expired and not cache.warning then
                XQPushUtil.setAuthenFailedTimes(mac, times + rcount)
                XQPushUtil.setwifiauthfailedserialtimes(mac, 0)
            end
        end
    end
    return nil
end

function setWifiBlacklistedCache(mac)
    if XQFunction.isStrNil(mac) then
        return false
    end
    local mackey = "BLACKLISTED-"..mac:gsub(":", "")
    local data = {
        ["mac"]     = mac,
        ["count"]   = 1,
        ["warning"] = false,
        ["atime"]   = LuciSys.uptime()
    }
    write(mackey, data)
end

function getWifiBlacklistedCache(mac)
    if XQFunction.isStrNil(mac) then
        return nil
    end
    local mackey = "BLACKLISTED-"..mac:gsub(":", "")
    local data = read(mackey, 15)
    if data and not data.expired then
        data.count = data.count + 1
        write(mackey, data)
    end
    if data and data.expired and not data.old then
        if data.count >= AUTHEN_FAILED_THRESHOLD.wifib then
            data["warning"] = true
        end
    end
    return data
end

function wifiBlacklistedAction(mac)
    local XQPushUtil = require("xiaoqiang.util.XQPushUtil")
    if XQFunction.isStrNil(mac) then
        return nil
    else
        mac = XQFunction.macFormat(mac)
    end
    if isIgnored(mac, "wifi") then
        return nil
    end
    local settings = XQPushUtil.pushSettings()
    local times = XQPushUtil.getAuthenFailedTimes(mac)
    if settings.auth then
        local cache = getWifiBlacklistedCache(mac)
        if not cache then
            setWifiBlacklistedCache(mac)
        else
            local rcount = math.floor(cache.count / 4)
            if cache.expired and cache.warning then
                XQPushUtil.setAuthenFailedTimes(mac, times + rcount)
                return rcount
            elseif cache.expired and not cache.warning then
                XQPushUtil.setAuthenFailedTimes(mac, times + rcount)
            end
        end
    end
    return nil
end

function setLoginAuthenFailedCache(mac)
    if XQFunction.isStrNil(mac) then
        return false
    end
    local mackey = "LOGIN-"..mac:gsub(":", "")
    local data = {
        ["mac"]     = mac,
        ["count"]   = 1,
        ["warning"] = false,
        ["atime"]   = LuciSys.uptime()
    }
    write(mackey, data)
end

function getLoginAuthenFailedCache(mac)
    if XQFunction.isStrNil(mac) then
        return nil, nil
    end
    local XQPushUtil = require("xiaoqiang.util.XQPushUtil")
    local level = tonumber(XQPushUtil.pushSettings().level)
    local mackey = "LOGIN-"..mac:gsub(":", "")
    local data = read(mackey)
    if data and not data.expired then
        data.count = data.count + 1
        write(mackey, data)
    end
    if data and data.count >= AUTHEN_FAILED_THRESHOLD.llogin and not data.expired then
        data["warning"] = true
        return data
    end
    if data and data.expired and not data.old then
        if (level == 2 and data.count >= AUTHEN_FAILED_THRESHOLD.llogin)
            or (level == 3 and data.count >= AUTHEN_FAILED_THRESHOLD.hlogin) then
            data["warning"] = true
        end
    end
    return data
end

function LoginAuthenFailedAction(mac)
    local XQPushUtil = require("xiaoqiang.util.XQPushUtil")
    if XQFunction.isStrNil(mac) then
        return nil
    else
        mac = XQFunction.macFormat(mac)
    end
    if isIgnored(mac, "login") then
        return nil
    end
    local settings = XQPushUtil.pushSettings()
    local times = XQPushUtil.getLoginAuthenFailedTimes(mac)
    local cache = getLoginAuthenFailedCache(mac)
    if not cache then
        setLoginAuthenFailedCache(mac)
    else
        if cache.warning then
            XQPushUtil.setLoginAuthenFailedTimes(mac, times + cache.count)
            XQPushUtil.setLoginAuthenFailedFrequency(mac, cache.count)
            return cache.count
        elseif cache.expired and not cache.warning then
            XQPushUtil.setLoginAuthenFailedTimes(mac, times + cache.count)
        end
    end
    return nil
end

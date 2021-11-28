module ("xiaoqiang.common.XQFunction", package.seeall)

local XQConfigs = require("xiaoqiang.common.XQConfigs")

--[[
@param mac: mac address
@return XX:XX:XX:XX:XX:XX
]]--
function macFormat(mac)
    if mac then
        return (_cmdformat(string.upper((string.gsub(mac,"-",":")))))
    else
        return ""
    end
end

function isStrNil(str)
    return (str == nil or str == "")
end

function checkChineseChar(str)
    local res = false
    if str and type(str) == "string" then
        for i=1, #str do
            if string.byte(str, i) > 127 then
                res = true
                break
            end
        end
    end
    return res
end

function isDomain(url)
    if not url then
        return false
    end
    if url:match("^%w[%w%-%.]+%w$") then
        return true
    end
    return false
end

function parseEnter2br(str)
    if (str ~= nil) then
        str = str:gsub("\r\n", "<br>")
        str = str:gsub("\r", "<br>")
        str = str:gsub("\n", "<br>")
    end
    return str
end

function forkExec(command)
    local Nixio = require("nixio")
    local pid = Nixio.fork()
    if pid > 0 then
        return
    elseif pid == 0 then
        Nixio.chdir("/")
        local null = Nixio.open("/dev/null", "w+")
        if null then
            Nixio.dup(null, Nixio.stderr)
            Nixio.dup(null, Nixio.stdout)
            Nixio.dup(null, Nixio.stdin)
            if null:fileno() > 2 then
                null:close()
            end
        end
        Nixio.exec("/bin/sh", "-c", command)
    end
end

function doPrint(content)
    if type(content) == "table" then
        for k,v in pairs(content) do
            if type(v) == "table" then
                print("<"..k..": ")
                doPrint(v)
                print(">")
            else
                print("["..k.." : "..tostring(v).."]")
            end
        end
    else
        print(content)
    end
end

function forkRestartWifi(cmd)
    if cmd then
        forkExec(XQConfigs.FORK_RESTART_WIFI..";"..cmd)
    else
        forkExec(XQConfigs.FORK_RESTART_WIFI)
    end

end

function forkRestartWifiNotify()
    --- Remove mi iot notify logic 20190314
    forkExec(XQConfigs.FORK_RESTART_WIFI_NOTIFY_BUT_MIIO)
end

function forkRestartWifiNotifyButMiio()
    forkExec(XQConfigs.FORK_RESTART_WIFI_NOTIFY_BUT_MIIO)
end

function forkReboot()
    forkExec(XQConfigs.FORK_RESTART_ROUTER)
end

function forkShutdown()
    forkExec(XQConfigs.FORK_SHUTDOWN_ROUTER)
end

function forkResetAll()
    forkExec(XQConfigs.FORK_RESET_ALL)
end

function forkRestartDnsmasq()
    forkExec(XQConfigs.FORK_RESTART_DNSMASQ)
end

function forkFlashRomFile(filePath)
    forkExec("flash.sh "..filePath)
end

function forkShutdownAndRebootWithDelay(m1, m2)
    local min1 = tonumber(m1)
    local min2 = tonumber(m2)
    if min1 and min2 and (min1 ~=0 or min2 ~= 0) then
        local cmd
        if min1 > 0 and min2 > 0 then
            cmd = string.format("sleep %s ; /usr/sbin/uhbn 2 %s", tostring(60*min1), tostring(min2))
        end
        if min1 == 0 and min2 > 0 then
            cmd = string.format("sleep 4 ; /usr/sbin/uhbn 2 %s", tostring(min2))
        end
        if min1 > 0 and min2 == 0 then
            cmd = string.format("sleep %s ; /usr/sbin/uhbn 3", tostring(60*min1))
        end
        forkExec(cmd)
    end
end

function syncRestartMacFilter()
    os.execute(XQConfigs.RESTART_MAC_FILTER)
end

function closeWebInitRDR()
    os.execute("/usr/sbin/sysapi webinitrdr set off")
end

function getTime()
    return os.date("%Y-%m-%d--%X",os.time())
end

function hzFormat(hertz)
    local suff = {"Hz", "KHz", "MHz", "GHz", "THz"}
    for i=1, 5 do
        if hertz > 1024 and i < 5 then
            hertz = hertz / 1024
        else
            return string.format("%.2f %s", hertz, suff[i])
        end
    end
end

function byteFormat(byte)
    local suff = {"B", "KB", "MB", "GB", "TB"}
    for i=1, 5 do
        if byte > 1024 and i < 5 then
            byte = byte / 1024
        else
            return string.format("%.2f %s", byte, suff[i])
        end
    end
end

function utfstrlen(str)
    local len = #str
    local left = len
    local cnt = 0
    local arr = {0, 0xc0, 0xe0, 0xf0, 0xf8, 0xfc}
    while left ~= 0 do
        local tmp = string.byte(str, -left);
        local i = #arr;
        while arr[i] do
            if tmp >= arr[i] then
                left = left - i
                break
            end
            i = i-1
        end
        cnt = cnt + 1
    end
    return cnt;
end

function checkSSID(ssid)
    --local XQLog = require("xiaoqiang.XQLog")


    --if isStrNil(ssid) or string.match(ssid, "`") then
        --XQLog.log(1, "ssid check fail.")
    --    return false
    --end

    --local filter_chars="[`;|$&{}\\]"
    --if string.find(ssid, filter_chars) then
        --XQLog.log(1, "ssid check fail.invalid char")
    --    return false
    --end

    return true
    -- if string.match(ssid,"^%w[%w_.-]*%w$") or string.match(ssid,"^%w$") then
    --     return true
    -- else
    --     return false
    -- end
end

function sysLock()
    return os.execute(XQConfigs.UPGRADE_LOCK)
end

function sysUnlock()
    return os.execute(XQConfigs.UPGRADE_UNLOCK)
end

function sysLockStatus()
    local LuciFs = require("luci.fs")
    local status = LuciFs.access(XQConfigs.UPGRADE_LOCK_FILE)
    if status then
        return 1
    else
        return 0
    end
end

function ledFlashAlert(enable)
    if enable then
        forkExec(XQConfigs.UPDATE_LED_FLASH_ALERT_ENABLE)
    else
        os.execute(XQConfigs.UPDATE_LED_FLASH_ALERT_DISABLE)
    end
end

function getGpioValue(digit)
    local LuciUtil = require("luci.util")
    local gpio = LuciUtil.exec(string.format(XQConfigs.GPIO_VALUE,tostring(digit)))
    if gpio then
        return tonumber(LuciUtil.trim(gpio)) or 0
    end
    return 0
end

function _cmdformat(str)
    if isStrNil(str) then
        return ""
    else
        -- string.gsub, will return a pair of values, the modified string and the number of substitutions made
        local newStr = str:gsub("\\", "\\\\"):gsub("`", "\\`"):gsub("\"", "\\\""):gsub("%$", "\\$")
        return newStr
    end
end

-- execute command with filtered-char`\"$
function execute_safe(str)
    strCMD=_cmdformat(str)
    return os.execute(strCMD)
end

function _strformat(str)
    if isStrNil(str) then
        return ""
    else
        -- string.gsub, will return a pair of values, the modified string and the number of substitutions made
        local newStr = str:gsub("'", ""):gsub("\\", "\\\\"):gsub("`", "\\`"):gsub("\"", "\\\""):gsub("%$", "\\$")
        return newStr
    end
end

function bdataGet(key, default)
    if isStrNil(key) then
        return default
    end
    local LuciUtil = require("luci.util")
    local cmd = string.format("bdata get \"%s\"", _cmdformat(key))
    local value = LuciUtil.exec(cmd)
    if value then
        value = LuciUtil.trim(value)
        return value
    end
    return default
end

function nvramGet(key, default)
    if isStrNil(key) then
        return default
    end
    local LuciUtil = require("luci.util")
    local cmd = string.format("nvram get \"%s\"", _cmdformat(key))
    local value = LuciUtil.exec(cmd)
    if value then
        value = LuciUtil.trim(value)
        return value
    end
    return default
end

function nvramSet(key, value)
    if isStrNil(key) then
        return
    end
    local cmd
    if isStrNil(value) then
        cmd = string.format("nvram unset \"%s\"", _cmdformat(key))
    else
        cmd = string.format("nvram set \"%s\"=\"%s\"", _cmdformat(key), _cmdformat(value))
    end
    os.execute(cmd)
end

function nvramCommit()
    os.execute("nvram commit")
end

function getNetMode()
    local uci = require("luci.model.uci").cursor()
    local netmode = uci:get("xiaoqiang", "common", "NETMODE")
    if isStrNil(netmode) then
        netmode = nil
    end
    return netmode
end

function miscRecovery()
    local uci = require("luci.model.uci").cursor()
    local recovery = uci:get("misc", "hardware", "recovery")
    if isStrNil(recovery) then
        recovery = 0
    end
    return tonumber(recovery)
end

function getNetModeType()
    local recovery = miscRecovery()
    if recovery == 1 then
        return 100
    end
    local netMode = 0
    local mode = getNetMode()
    if mode == "lanapmode" then
        netMode = 2
    elseif mode == "wifiapmode" then
        netMode = 1
    elseif mode == "whc_re" then
        netMode = 3
    end
    return netMode
end

function setNetMode(mode)
    local XQSynchrodata = require("xiaoqiang.util.XQSynchrodata")
    local uci = require("luci.model.uci").cursor()
    if mode then
        if mode == "wifiapmode" then
            XQSynchrodata.syncWorkMode(1)
        elseif mode == "lanapmode" then
            XQSynchrodata.syncWorkMode(2)
        end
        uci:set("xiaoqiang", "common", "NETMODE", mode)
    else
        XQSynchrodata.syncWorkMode(0)
        uci:delete("xiaoqiang", "common", "NETMODE")
    end
    uci:commit("xiaoqiang")
end

function thrift_tunnel_to_datacenter(payload)
    if isStrNil(payload) then
        return nil
    end

    local LuciUtil = require("luci.util")
    local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")
    payload = XQCryptoUtil.binaryBase64Enc(payload)
    local result = LuciUtil.trim(LuciUtil.exec(XQConfigs.THRIFT_TUNNEL_TO_DATACENTER % payload))
    if isStrNil(result) then
        return nil
    else
        local json = require("cjson")
        return json.decode(result)
    end
end

--[[function thrift_to_mqtt_identify_device()
    local LuciUtil = require("luci.util")
    local cmd = XQConfigs.THRIFT_TO_MQTT_IDENTIFY_DEVICE
    local d = LuciUtil.trim(LuciUtil.exec(cmd))
    if isStrNil(d) then
        d = ""
    end
    return d
end

function thrift_to_mqtt_get_sn()
    local LuciUtil = require("luci.util")
    local cmd = XQConfigs.THRIFT_TO_MQTT_GET_SN
    local serialNumber = LuciUtil.trim(LuciUtil.exec(cmd))
    if isStrNil(serialNumber) then
        serialNumber = ""
    end
    return serialNumber
end

function thrift_to_mqtt_get_deviceid()
    local LuciUtil = require("luci.util")
    local cmd = XQConfigs.THRIFT_TO_MQTT_GET_DEVICEID
    local deviceId = LuciUtil.trim(LuciUtil.exec(cmd))
    if isStrNil(deviceId) then
        deviceId = ""
    end
    return deviceId
end]]

function thrift_tunnel_to_smarthome_controller(payload)
    if isStrNil(payload) then
        return nil
    end

    local LuciUtil = require("luci.util")
    local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")
    payload = XQCryptoUtil.binaryBase64Enc(payload)
    local result = LuciUtil.trim(LuciUtil.exec(XQConfigs.THRIFT_TUNNEL_TO_SMARTHOME_CONTROLLER % payload))
    if isStrNil(result) then
        return nil
    else
        local json = require("cjson")
        return json.decode(result)
    end
end

function mattool_identify_device()
    local LuciUtil = require("luci.util")
    local cmd = "matool --method identifyDevice"
    local d = LuciUtil.trim(LuciUtil.exec(cmd))
    if isStrNil(d) then
        d = ""
    end
    return d
end

function mattool_get_deviceid()
    local LuciUtil = require("luci.util")
    local cmd = "matool --method deviceID"
    local deviceId = LuciUtil.trim(LuciUtil.exec(cmd))
    if isStrNil(deviceId) then
        deviceId = ""
    end
    return deviceId
end

function _parse(hex, pre)
    if hex == 0 then
        return 0
    end
    local value = 0
    for i=0, 7 do
        local shift = bit.rshift(128, i)
        local res = bit.band(hex, shift)
        if res == 0 then
            if hex - value == 0 then
                if pre == 0 or pre == 2 then
                    return -1
                elseif pre == 1 then
                    return 2
                end
            else
                return -1
            end
        end
        value = value + shift
    end
    return 1
end

function checkMask(mask)
    if isStrNil(mask) then
        return false
    end
    if mask == "0.0.0.0" or mask == "255.255.255.255" then
        return false
    end
    local LuciUtil = require("luci.util")
    local LuciDatatypes = require("luci.cbi.datatypes")
    if not LuciDatatypes.ipaddr(mask) then
        return false
    end
    local maskarr = LuciUtil.split(mask, ".")
    local pre = 1
    for _,value in ipairs(maskarr) do
        pre = _parse(tonumber(value), pre)
        if pre == -1 then
            return false
        end
    end
    return true
end

-- XSS encode
function encode4HtmlValue(str)
    str = string.gsub( str, '&', '&amp;')
    str = string.gsub( str, '<', '&lt;')
    str = string.gsub( str, '>', '&gt;')
    str = string.gsub( str, '"', '&quot;')
    str = string.gsub( str, "'", '&#039;')
    return str
end

function encode4Js(str)
    str = string.gsub( str, "\\", "\\\\" )
    return str
end

-- get RouterName
function getRouterName()
    local XQSysUtil = require ("xiaoqiang.util.XQSysUtil")
    local routerName = XQSysUtil.getRouterName()
    local routerLocale = XQSysUtil.getRouterLocale()
    if routerLocale ~= "" then
        routerLocale = " (".. encode4HtmlValue(routerLocale) ..")"
    end
    routerName = encode4HtmlValue(routerName) .. routerLocale
    return routerName
end

function get_active_apcli()
    local uci = require("luci.model.uci").cursor()
    local active_apcli = uci:get("xiaoqiang", "common", "active_apcli")

    if isStrNil(active_apcli) then
        active_apcli = nil
    end
    return active_apcli
end

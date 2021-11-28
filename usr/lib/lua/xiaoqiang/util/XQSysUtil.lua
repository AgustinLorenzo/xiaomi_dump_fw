module ("xiaoqiang.util.XQSysUtil", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local XQConfigs = require("xiaoqiang.common.XQConfigs")

function getPrivacy()
    local privacy = require("xiaoqiang.XQPreference").get("PRIVACY")
    if tonumber(privacy) and tonumber(privacy) == 1 then
        return true
    else
        return false
    end
end

function setPrivacy(agree)
    local privacy = agree and "1" or "0"
    local hardware = getHardware()
    require("xiaoqiang.XQPreference").set("PRIVACY", privacy)
    if hardware == "R1D" then
        XQFunction.nvramSet("user_privacy", privacy)
        XQFunction.nvramCommit()
    end
end

function isMiWiFi()
    local perference = require("xiaoqiang.XQPreference")
    local ap_host = perference.get("ap_hostname") or ""
    ap_host = string.lower(ap_host)
    if ap_host:match("^miwifi") then
        return true
    end
    return false
end

function getConfUploadEnable()
    local enable = require("xiaoqiang.XQPreference").get("CONFUPLOAD_ENABLE")
    if enable and tonumber(enable) == 1 then
        return true
    else
        return false
    end
end

function setConfUploadEnable(enable)
    local preference = require("xiaoqiang.XQPreference")
    preference.set("CONFUPLOAD_ENABLE", enable and "1" or "0")
end

function doConfUpload(upload)
    local uci = require("luci.model.uci").cursor()
    local sync = require("xiaoqiang.util.XQSynchrodata")
    local wifi = require("xiaoqiang.util.XQWifiUtil")
    local info = {}
    if getConfUploadEnable() then
        if not upload or not upload.ssid_24G then
            local wifiinfo = wifi.getWifiBasicInfo(1)
            info.ssid_24G = wifiinfo.ssid
            info.wifi_24G_password = wifiinfo.password
        else
            info.ssid_24G = upload.ssid_24G or ""
            info.wifi_24G_password = upload.wifi_24G_password or ""
        end
        if not upload or not upload.pppoe_name then
            local proto = uci:get("network", "wan", "proto")
            if proto and proto == "pppoe" then
                local pppoename = uci:get("network", "wan", "username") or ""
                local pppoepwd = uci:get("network", "wan", "password") or ""
                info.pppoe_name = pppoename
                info.pppoe_password = pppoepwd
            end
        else
            info.pppoe_name = upload.pppoe_name or ""
            info.pppoe_password = upload.pppoe_password or ""
        end
        sync.uploadConf(info)
    end
end

function getVendorInfo()
    local info = {
        ["name"]        = "",
        ["hardware"]    = "",
        ["color"]       = "",
        ["version"]     = "",
        ["ip"]          = ""
    }
    local perference = require("xiaoqiang.XQPreference")
    local vendorinfo = perference.get("vendorinfo")
    if XQFunction.isStrNil(vendorinfo) then
        return info
    end
    local luciutil = require("luci.util")
    local ainfo = luciutil.split(vendorinfo, "-")
    info.name       = perference.get("ap_hostname") or ""
    info.hardware   = ainfo[2] or ""
    info.version    = ainfo[3] or ""
    info.color      = ainfo[4] or ""
    if XQFunction.isStrNil(info.color) then
        if not XQFunction.isStrNil(info.hardware) then
            if string.upper(info.hardware) == "R1D" then
                info.color = "100"
            else
                info.color = "101"
            end
        end
    end
    if XQFunction.getNetModeType() == 0 then
        local ubus = require("ubus").connect()
        local wan = ubus:call("network.interface.wan", "status", {})
        if wan and wan.route and wan.route[1] and wan.route[1].nexthop then
            info.ip = wan.route[1].nexthop
        end
    else
        local uci = require("luci.model.uci").cursor()
        info.ip = uci:get("network", "lan", "gateway") or ""
    end
    return info
end

function getInitInfo()
    local initted = require("xiaoqiang.XQPreference").get(XQConfigs.PREF_IS_INITED)
    if initted then
        return true
    else
        return false
    end
end

function setInited()
    require("xiaoqiang.XQPreference").set(XQConfigs.PREF_IS_INITED, "YES")
    local LuciUtil = require("luci.util")
    LuciUtil.exec("/usr/sbin/sysapi webinitrdr set off")
    LuciUtil.exec("[ -f /usr/sbin/wan_check.sh ] && /usr/sbin/wan_check.sh reset")
    XQFunction.forkExec("/etc/init.d/xunlei restart")
    --set wps state
    local hardware = getHardware()
    if hardware then
        if hardware == "R1800" or hardware == "R4C" or hardware == "R3600" then
            XQFunction.forkExec("/usr/sbin/set_wps_state 2")
        end
    end
    return true
end

function setSPwd()
    local LuciUtil = require("luci.util")
    local genpwd = LuciUtil.exec("mkxqimage -I")
    if genpwd then
        local LuciSys = require("luci.sys")
        genpwd = LuciUtil.trim(genpwd)
        LuciSys.user.setpasswd("root", genpwd)
    end
end

function getChangeLog()
    local LuciFs  = require("luci.fs")
    local LuciUtil = require("luci.util")
    if LuciFs.access(XQConfigs.XQ_CHANGELOG_FILEPATH) then
        return LuciUtil.exec("cat "..XQConfigs.XQ_CHANGELOG_FILEPATH)
    end
    return ""
end

function getMiscHardwareInfo()
    local uci = require("luci.model.uci").cursor()
    local result = {}
    result["bbs"] = tostring(uci:get("misc", "hardware", "bbs"))
    result["cpufreq"] = tostring(uci:get("misc", "hardware", "cpufreq"))
    result["verify"] = tostring(uci:get("misc", "hardware", "verify"))
    result["gpio"] = tonumber(uci:get("misc", "hardware", "gpio")) == 1 and 1 or 0
    result["recovery"] = tonumber(uci:get("misc", "hardware", "recovery")) == 1 and 1 or 0
    result["flashpermission"] = tonumber(uci:get("misc", "hardware", "flash_per")) == 1 and 1 or 0
    result["memsize"] = uci:get("misc", "hardware", "memsize")
    return result
end

function getPassportBindInfo()
    local XQPreference = require("xiaoqiang.XQPreference")
    local initted = XQPreference.get(XQConfigs.PREF_IS_PASSPORT_BOUND)
    local bindUUID = XQPreference.get(XQConfigs.PREF_PASSPORT_BOUND_UUID, "")
    if not XQFunction.isStrNil(initted) and initted == "YES" and not XQFunction.isStrNil(bindUUID) then
        return bindUUID
    else
        return false
    end
end

function setPassportBound(bind,uuid)
    local XQPreference = require("xiaoqiang.XQPreference")
    local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
    if bind then
        if not XQFunction.isStrNil(uuid) then
            XQPreference.set(XQConfigs.PREF_PASSPORT_BOUND_UUID,uuid)
        end
        XQPreference.set(XQConfigs.PREF_IS_PASSPORT_BOUND, "YES")
        XQPreference.set(XQConfigs.PREF_TIMESTAMP, "0")
    else
        if not XQFunction.isStrNil(uuid) then
            XQPreference.set(XQConfigs.PREF_PASSPORT_BOUND_UUID,"")
        end
        XQPreference.set(XQConfigs.PREF_IS_PASSPORT_BOUND, "NO")
        XQPreference.set(XQConfigs.PREF_BOUND_USERINFO, "")
    end
    return true
end

function getSysUptime()
    local LuciUtil = require("luci.util")
    local catUptime = "cat /proc/uptime"
    local data = LuciUtil.exec(catUptime)
    if data == nil then
        return 0
    else
        local t1,t2 = data:match("^(%S+) (%S+)")
        return LuciUtil.trim(t1)
    end
end

function getConfigInfo()
    local LuciUtil = require("luci.util")
    return LuciUtil.exec("cat /etc/config/*")
end

function getRouterName()
    local XQPreference = require("xiaoqiang.XQPreference")
    local name = XQPreference.get(XQConfigs.PREF_ROUTER_NAME, "")
    if XQFunction.isStrNil(name) then
        local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
        local wifistatus = XQWifiUtil.getWifiStatus(1)
        name = wifistatus.ssid or ""
    end
    return name
end

function setRouterName(routerName)
    if routerName then
        local XQSync = require("xiaoqiang.util.XQSynchrodata")
        XQSync.syncRouterName(routerName)
        require("xiaoqiang.XQPreference").set(XQConfigs.PREF_ROUTER_NAME, routerName)
        setRouterNamePending('1')
        return true
    else
        return false
    end
end

--
-- 家/单位/其它
--
function getRouterLocale()
    local XQPreference = require("xiaoqiang.XQPreference")
    return XQPreference.get("ROUTER_LOCALE") or ""
end

--
-- 家/单位/其它
--
function setRouterLocale(locale)
    local XQPreference = require("xiaoqiang.XQPreference")
    if locale then
        local XQSync = require("xiaoqiang.util.XQSynchrodata")
        XQSync.syncRouterLocale(locale)
        XQPreference.set("ROUTER_LOCALE", locale)
    end
end

function getRouterNamePending()
    return require("xiaoqiang.XQPreference").get(XQConfigs.PREF_ROUTER_NAME_PENDING, '0')
end

function setRouterNamePending(pending)
    return require("xiaoqiang.XQPreference").set(XQConfigs.PREF_ROUTER_NAME_PENDING, pending)
end

function getBindUUID()
    return require("xiaoqiang.XQPreference").get(XQConfigs.PREF_PASSPORT_BOUND_UUID, "")
end

-- function setBindUUID(uuid)
--     return require("xiaoqiang.XQPreference").set(XQConfigs.PREF_PASSPORT_BOUND_UUID, uuid)
-- end

-- function setBindUserInfo(userInfo)
--     local LuciJson = require("json")
--     local XQPreference = require("xiaoqiang.XQPreference")
--     local XQConfigs = require("xiaoqiang.common.XQConfigs")
--     local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")
--     if userInfo and type(userInfo) == "table" then
--         local userInfoStr = LuciJson.encode(userInfo)
--         XQPreference.set(XQConfigs.PREF_BOUND_USERINFO,XQCryptoUtil.binaryBase64Enc(userInfoStr))
--     end
-- end

-- function getBindUserInfo()
--     local LuciJson = require("json")
--     local XQPreference = require("xiaoqiang.XQPreference")
--     local XQConfigs = require("xiaoqiang.common.XQConfigs")
--     local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")
--     local infoStr = XQPreference.get(XQConfigs.PREF_BOUND_USERINFO,nil)
--     if infoStr and infoStr ~= "" then
--         infoStr = XQCryptoUtil.binaryBase64Dec(infoStr)
--         if infoStr then
--             return LuciJson.decode(infoStr)
--         end
--     else
--         return nil
--     end
-- end

function getSN()
    local LuciUtil = require("luci.util")
    local sn = LuciUtil.exec(XQConfigs.GET_NVRAM_SN)
    if XQFunction.isStrNil(sn) then
        return nil
    else
        sn = LuciUtil.trim(sn)
    end
    return sn
end

function getRomVersion()
    local LuciUtil = require("luci.util")
    local romVersion = LuciUtil.exec(XQConfigs.XQ_ROM_VERSION)
    if XQFunction.isStrNil(romVersion) then
        romVersion = ""
    end
    return LuciUtil.trim(romVersion)
end

function getChannel()
    local LuciUtil = require("luci.util")
    local channel = LuciUtil.exec(XQConfigs.XQ_CHANNEL)
    if XQFunction.isStrNil(channel) then
        channel = ""
    end
    return LuciUtil.trim(channel)
end

-- From GPIO
function getHardwareVersion()
    local h = XQFunction.getGpioValue(14)
    local m = XQFunction.getGpioValue(13)
    local l = XQFunction.getGpioValue(12)
    local offset = h * 4 + m * 2 + l
    local char = string.char(65+offset)
    return "Ver."..char
end

function getHardwareGPIO()
    local LuciUtil = require("luci.util")
    local hardware = LuciUtil.exec(XQConfigs.XQ_HARDWARE)
    if XQFunction.isStrNil(hardware) then
        hardware = ""
    else
        hardware = LuciUtil.trim(hardware)
    end
    local misc = getMiscHardwareInfo()
    if misc.gpio == 1 then
        return getHardwareVersion()
    end
    return hardware
end

function getHardware()
    local LuciUtil = require("luci.util")
    local hardware = LuciUtil.exec(XQConfigs.XQ_HARDWARE)
    if XQFunction.isStrNil(hardware) then
        hardware = ""
    else
        hardware = LuciUtil.trim(hardware)
    end
    return hardware
end

function getCFEVersion()
    local LuciUtil = require("luci.util")
    local cfe = LuciUtil.exec(XQConfigs.XQ_CFE_VERSION)
    if XQFunction.isStrNil(cfe) then
        cfe = ""
    end
    return LuciUtil.trim(cfe)
end

function getKernelVersion()
    local LuciUtil = require("luci.util")
    local kernel = LuciUtil.exec(XQConfigs.XQ_KERNEL_VERSION)
    if XQFunction.isStrNil(kernel) then
        kernel = ""
    end
    return LuciUtil.trim(kernel)
end

function getRamFsVersion()
    local LuciUtil = require("luci.util")
    local ramFs = LuciUtil.exec(XQConfigs.XQ_RAMFS_VERSION)
    if XQFunction.isStrNil(ramFs) then
        ramFs = ""
    end
    return LuciUtil.trim(ramFs)
end

function getSqaFsVersion()
    local LuciUtil = require("luci.util")
    local sqaFs = LuciUtil.exec(XQConfigs.XQ_SQAFS_VERSION)
    if XQFunction.isStrNil(sqaFs) then
        sqaFs = ""
    end
    return LuciUtil.trim(sqaFs)
end

function getRootFsVersion()
    local LuciUtil = require("luci.util")
    local rootFs = LuciUtil.exec(XQConfigs.XQ_ROOTFS_VERSION)
    if XQFunction.isStrNil(rootFs) then
        rootFs = ""
    end
    return LuciUtil.trim(rootFs)
end

function getISPCode()
    local LuciUtil = require("luci.util")
    local ispCode = LuciUtil.exec(XQConfigs.XQ_ISP_CODE)
    if XQFunction.isStrNil(ispCode) then
        ispCode = ""
    end
    return LuciUtil.trim(ispCode)
end

function getLangList()
    local LuciUtil = require("luci.util")
    local LuciConfig = require("luci.config")
    local langs = {}
    for k, v in LuciUtil.kspairs(LuciConfig.languages) do
        if type(v)=="string" and k:sub(1, 1) ~= "." then
            local lang = {}
            lang['lang'] = k
            lang['name'] = v
            table.insert(langs,lang)
        end
    end
    return langs
end

function getLang()
    local LuciConfig = require("luci.config")
    return LuciConfig.main.lang
end

function setLang(lang)
    local LuciUtil = require("luci.util")
    local LuciUci = require("luci.model.uci")
    local LuciConfig = require("luci.config")
    for k, v in LuciUtil.kspairs(LuciConfig.languages) do
        if type(v) == "string" and k:sub(1, 1) ~= "." then
            if lang == k or lang == "auto" then
                local cursor = LuciUci.cursor()
                if lang=="auto" then
                    cursor:set("luci", "main" , "lang" , "auto")
                else
                    cursor:set("luci", "main" , "lang" , k)
                end
                cursor:commit("luci")
                cursor:save("luci")
                return true
            end
        end
    end
    return false
end

function setSysPasswordDefault()
    local LuciSys = require("luci.sys")
    local XQSecureUtil = require("xiaoqiang.util.XQSecureUtil")
    XQSecureUtil.savePlaintextPwd("admin", "admin")
end

function checkSysPassword(oldPassword)
    local LuciSys = require("luci.sys")
    return LuciSys.user.checkpasswd("root", oldPassword)
end

function setSysPassword(newPassword)
    local LuciSys = require("luci.sys")
    local XQSecureUtil = require("xiaoqiang.util.XQSecureUtil")
    check = LuciSys.user.setpasswd("root", newPassword)
    XQSecureUtil.savePlaintextPwd("admin", newPassword)
    if check == 0 then
        return true
    else
        local LuciUtil = require("luci.util")
        LuciUtil.exec("rm /etc/passwd+")
    end
    return false
end

function cutImage(filePath)
    if not filePath then
        return false
    end
    local code = os.execute(XQConfigs.XQ_CUT_IMAGE..filePath)
    if 0 == code or 127 == code then
        return true
    else
        return false
    end
end

function verifyImage(filePath)
    if not filePath then
        return false
    end
    local misc = getMiscHardwareInfo()
    if 0 == os.execute(misc.verify.."'"..filePath.."'") then
        return true
    else
        return false
    end
end

function getSysInfo()
    local LuciSys = require("luci.sys")
    local LuciUtil = require("luci.util")
    local misc = getMiscHardwareInfo()
    local sysInfo = {}
    local processor = LuciUtil.execl("cat /proc/cpuinfo | grep processor")
    local platform, model, memtotal, memcached, membuffers, memfree, bogomips = LuciSys.sysinfo()
    if #processor > 0 then
        sysInfo["core"] = #processor
    else
        sysInfo["core"] = 1
    end
    local function memhelper(mem)
        local mem = tonumber(mem)
        if mem then
            local mod = mem % 64
            if mod >= 32 then
                return mem + 64 - mod
            else
                return mem - mod
            end
        else
            return 0
        end
    end
    if misc.cpufreq then
        sysInfo["hz"] = misc.cpufreq
    else
        sysInfo["hz"] = XQFunction.hzFormat(tonumber(bogomips)*500000)
    end
    if misc.memsize then
        sysInfo["memTotal"] = misc.memsize
    else
        sysInfo["memTotal"] = string.format("%d M",memhelper(memtotal/1024))
    end
    sysInfo["system"] = platform
    sysInfo["memFree"] = string.format("%0.2f M",memfree/1024)
    return sysInfo
end

function setMacFilter(mac,lan,wan,admin,pridisk)
    local LuciDatatypes = require("luci.cbi.datatypes")
    if not XQFunction.isStrNil(mac) and LuciDatatypes.macaddr(mac) then
        local cmd = "/usr/sbin/sysapi macfilter set mac="..mac
        if wan then
            cmd = cmd.." wan="..(wan == "1" and "yes" or "no")
        end
        if lan then
            cmd = cmd.." lan="..(lan == "1" and "yes" or "no")
            -- user disk access permission decided by datacenter
            local payload = {
                ["api"] = 75,
                ["isAdd"] = lan == "1" and true or false,
                ["isLogin"] = false,
                ["mac"] = mac
            }
            local LuciJson = require("json")
            XQFunction.thrift_tunnel_to_datacenter(LuciJson.encode(payload))
        end
        if admin then
            cmd = cmd.." admin="..(admin == "1" and "yes" or "no")
        end
        if pridisk then
            cmd = cmd.." pridisk="..(pridisk == "1" and "yes" or "no")
        end
        if os.execute(cmd..";".."/usr/sbin/sysapi macfilter commit") == 0 then
            return true
        end
    end
    return false
end

function getDiskSpace()
    local LuciUtil = require("luci.util")
    local disk = LuciUtil.exec(XQConfigs.DISK_SPACE)
    if disk and tonumber(LuciUtil.trim(disk)) then
        disk = tonumber(LuciUtil.trim(disk))
        return XQFunction.byteFormat(disk*1024)
    else
        return "Cannot find userdisk"
    end
end

function getAvailableMemery()
    local LuciUtil = require("luci.util")
    local memery = LuciUtil.exec(XQConfigs.AVAILABLE_MEMERY)
    if memery and tonumber(LuciUtil.trim(memery)) then
        return tonumber(LuciUtil.trim(memery))
    else
        return false
    end
end

function getAvailableDisk(cmd)
    local LuciUtil = require("luci.util")
    local disk = LuciUtil.exec(cmd or XQConfigs.AVAILABLE_DISK)
    if disk and tonumber(LuciUtil.trim(disk)) then
        return tonumber(LuciUtil.trim(disk))
    else
        return false
    end
end

function getAvailableSpace(path)
    if path and path:match("/userdisk/data") then
        return getAvailableDisk([[df -k | grep \ /userdisk/data$ | awk '{print $4}' | sed -n '1p']])
    elseif path and path:match("/userdisk") then
        return getAvailableDisk()
    end
    return getAvailableMemery()
end

function checkDiskSpace(byte)
    local disk = getAvailableDisk()
    if disk then
        if disk - byte/1024 > 10240 then
            return true
        end
    end
    return false
end

function checkTmpSpace(byte)
    local tmp = getAvailableMemery()
    if tmp then
        if tmp - byte/1024 > 10240 then
            return true
        end
    end
    return false
end

function checkSpace(path, byte)
    if path and byte then
        local available = getAvailableSpace(path)
        if available then
            if getHardware() == "R3" then
                if available > 10240 then
                    return true
                end
            else
                if available - byte/1024 > 10240 then
                    return true
                end
            end
        end
    end
    return false
end

function getUploadDir()
    return "/tmp/"
end

function getUploadRomFilePath()
    return XQConfigs.CROM_CACHE_FILEPATH
end

function updateUpgradeStatus(status)
    local status = tostring(status)
    os.execute("echo "..status.." > "..XQConfigs.UPGRADE_LOCK_FILE)
end

function getUpgradeStatus()
    local LuciUtil = require("luci.util")
    local status = tonumber(LuciUtil.exec(XQConfigs.UPGRADE_STATUS))
    if status then
        return status
    else
        return 0
    end
end

function getFlashProgress()
    local LuciUtil = require("luci.util")
    local progress = tonumber(LuciUtil.exec("cat /tmp/state/upgrade_progress 2>/dev/null"))
    if progress then
        return progress
    else
        return 0
    end
end

function checkBeenUpgraded()
    local LuciUtil = require("luci.util")
    local otaFlag = tonumber(LuciUtil.trim(LuciUtil.exec("nvram get flag_ota_reboot")))
    if otaFlag == 1 then
        return true
    else
        return false
    end
end

--[[
    0 : 没有flash
    1 : 正在执行flash
    2 : flash成功 需要重启
    3 : flash失败
]]--
function getFlashStatus()
    local LuciFs = require("luci.fs")
    if checkBeenUpgraded() then
        return 2
    end
    local check = os.execute(XQConfigs.FLASH_EXECUTION_CHECK)
    if check ~= 0 then
        return 1
    end
    if not LuciFs.access(XQConfigs.FLASH_PID_TMP) then
        return 0
    else
        return 3
    end
end

function checkExecStatus(checkCmd)
    local LuciUtil = require("luci.util")
    local check = LuciUtil.exec(checkCmd)
    if check then
        check = tonumber(LuciUtil.trim(check))
        if check > 0 then
            return 1
        end
    end
    return 0
end

--[[
    0 : 没有upgrade
    1 : 检查升级
    2 : 检查tmp 磁盘是否有空间下载
    3 : 下载升级包
    4 : 检测升级包
    5 : 刷写升级包
    6 : 没有检测到更新
    7 : 没有磁盘空间
    8 : 下载失败
    9 : 升级包校验失败
    10 : 刷写失败
    11 : 升级成功
    12 : 手动升级在刷写升级包
]]--
function checkUpgradeStatus()
    local LuciFs = require("luci.fs")
    if checkBeenUpgraded() then
        return 11
    end
    local status = getUpgradeStatus()
    if checkExecStatus(XQConfigs.CRONTAB_ROM_CHECK) == 1 then
        if status == 0 then
            return 1
        else
            return status
        end
    end
    local checkFlash = os.execute(XQConfigs.FLASH_EXECUTION_CHECK)
    if checkFlash ~= 0 then
        if checkExecStatus(XQConfigs.CROM_FLASH_CHECK) == 1 then
            return 12
        else
            return 5
        end
    end
    local flashStatus = getFlashStatus()
    local execute = LuciFs.access(XQConfigs.CRONTAB_PID_TMP)
    if execute then
        if status == 0 then
            if flashStatus == 2 then
                return 11
            elseif flashStatus == 3 then
                return 10
            end
        end
        return status
    else
        if flashStatus == 2 then
            return 11
        elseif flashStatus == 3 then
            return 10
        end
    end
    return 0
end

function isUpgrading()
    local status = checkUpgradeStatus()
    if status == 1 or status == 2 or status == 3 or status == 4 or status == 5 or status == 12 then
        return true
    else
        return false
    end
end

function cancelUpgrade()
    local LuciUtil = require("luci.util")
    local XQPreference = require("xiaoqiang.XQPreference")
    local XQDownloadUtil = require("xiaoqiang.util.XQDownloadUtil")
    local checkFlash = os.execute(XQConfigs.FLASH_EXECUTION_CHECK)
    if checkFlash ~= 0 then
        return false
    end
    local pid = LuciUtil.exec(XQConfigs.UPGRADE_PID)
    local luapid = LuciUtil.exec(XQConfigs.UPGRADE_LUA_PID)
    if not XQFunction.isStrNil(pid) then
        pid = LuciUtil.trim(pid)
        os.execute("kill "..pid)
        if not XQFunction.isStrNil(luapid) then
            os.execute("kill "..LuciUtil.trim(luapid))
        end
        XQDownloadUtil.cancelDownload(XQPreference.get(XQConfigs.PREF_ROM_DOWNLOAD_ID, ""))
        XQFunction.sysUnlock()
        return true
    else
        return false
    end
end

--[[
    Temp < 50, 属于正常
    50 < Temp < 64, 风扇可能工作不正常
    Temp > 64, 不正常风扇或温度传感器坏了
]]--
function getCpuTemperature()
    local LuciUtil = require("luci.util")
    local temperature = LuciUtil.exec(XQConfigs.CPU_TEMPERATURE)
    if not XQFunction.isStrNil(temperature) then
        temperature = temperature:match('Temperature: (%S+)')
        if temperature then
            temperature = tonumber(LuciUtil.trim(temperature))
            return temperature
        end
    end
    return 0
end

--[[
    simple : 0/1/2 (正常模式,时间长上传log/简单模式,时间短,不上传log/简单模式,时间短,上传log)
]]--
function getNetworkDetectInfo(simple,target)
    local LuciUtil = require("luci.util")
    local LuciJson = require("json")
    local XQSecureUtil = require("xiaoqiang.util.XQSecureUtil")
    local network = {}
    local targetUrl = (target == nil or not XQSecureUtil.cmdSafeCheck(target)) and "http://www.baidu.com" or target
    if targetUrl and targetUrl:match("http://") == nil and targetUrl:match("https://") == nil then
        targetUrl = "http://"..targetUrl
    end
    local result
    if tonumber(simple) == 1 then
        result = LuciUtil.exec(XQConfigs.SIMPLE_NETWORK_NOLOG_DETECT.."'"..targetUrl.."'")
    elseif tonumber(simple) == 2 then
        result = LuciUtil.exec(XQConfigs.SIMPLE_NETWORK_DETECT.."'"..targetUrl.."'")
    else
        result = LuciUtil.exec(XQConfigs.FULL_NETWORK_DETECT.."'"..targetUrl.."'")
    end
    if result then
        result = LuciJson.decode(LuciUtil.trim(result))
        if result and type(result) == "table" then
            local checkInfo = result.CHECKINFO
            if checkInfo and type(checkInfo) == "table" then
                network["wanLink"] = checkInfo.wanlink == "up" and 1 or 0
                network["wanType"] = checkInfo.wanprotocal or ""
                network["pingLost"] = checkInfo.ping:match("(%S+)%%")
                network["gw"] = checkInfo.gw:match("(%S+)%%")
                network["dns"] = checkInfo.dns == "ok" and 1 or 0
                network["tracer"] = checkInfo.tracer == "ok" and 1 or 0
                network["memory"] = tonumber(checkInfo.memory)*100
                network["cpu"] = tonumber(checkInfo.cpu)
                network["disk"] = checkInfo.disk
                network["tcp"] = checkInfo.tcp
                network["http"] = checkInfo.http
                network["ip"] = checkInfo.ip
                return network
            end
        end
    end
    return nil
end

function checkSystemStatus()
    local LuciUtil = require("luci.util")
    local LuciSys = require("luci.sys")
    local status = {}
    local system, model, memtotal, memcached, membuffers, memfree, bogomips = LuciSys.sysinfo()
    status["cpu"] = tonumber(LuciUtil.trim(LuciUtil.exec(XQConfigs.CPU_LOAD_AVG))) or 0
    status["mem"] = tonumber(string.format("%0.2f", 1 - (memcached + membuffers + memfree) / memtotal)) or 0
    status["link"] = string.upper(LuciUtil.trim(LuciUtil.exec(XQConfigs.WAN_LINK))) == "UP"
    status["wan"] = true --tonumber(LuciUtil.trim(LuciUtil.exec(XQConfigs.WAN_UP))) > 0
    status["tmp"] = getCpuTemperature()
    return status
end

function getFlashPermission()
    local LuciUtil = require("luci.util")
    local permission = LuciUtil.exec(XQConfigs.GET_FLASH_PERMISSION)
    if XQFunction.isStrNil(permission) then
        return false
    else
        permission = tonumber(LuciUtil.trim(permission))
        if permission and permission == 1 then
            return true
        end
    end
    return false
end

function setFlashPermission(permission)
    local LuciUtil = require("luci.util")
    if permission then
        LuciUtil.exec(XQConfigs.SET_FLASH_PERMISSION.."1")
    else
        LuciUtil.exec(XQConfigs.SET_FLASH_PERMISSION.."0")
    end
end

--[[
    lan: samba
    wan: internet
    admin: root
    return 0/1 (whitelist/blacklist)
]]--
function getMacfilterMode(filter)
    local LuciUtil = require("luci.util")
    local getMode = XQConfigs.GET_LAN_MODE
    if filter == "wan" then
        getMode = XQConfigs.GET_WAN_MODE
    elseif filter == "admin" then
        getMode = XQConfigs.GET_ADMIN_MODE
    end
    local macMode = LuciUtil.exec(getMode)
    if macMode then
        macMode = LuciUtil.trim(macMode)
        if macMode == "whitelist" then
            return 0
        else
            return 1
        end
    end
    return false
end

--[[
    filter : lan/wan/admin
    mode : 0/1 (whitelist/blacklist)
]]--
function setMacfilterMode(filter,mode)
    local LuciUtil = require("luci.util")
    local setMode
    if filter == "lan" then
        if tonumber(mode) == 0 then
            setMode = XQConfigs.SET_LAN_WHITELIST
        else
            setMode = XQConfigs.SET_LAN_BLACKLIST
        end
    elseif filter == "wan" then
        if tonumber(mode) == 0 then
            setMode = XQConfigs.SET_WAN_WHITELIST
        else
            setMode = XQConfigs.SET_WAN_BLACKLIST
        end
    elseif filter == "admin" then
        if tonumber(mode) == 0 then
            setMode = XQConfigs.SET_ADMIN_WHITELIST
        else
            setMode = XQConfigs.SET_ADMIN_BLACKLIST
        end
    end
    if setMode and os.execute(setMode) == 0 then
        return true
    else
        return false
    end
end

function getDetectionTimestamp()
    local XQPreference = require("xiaoqiang.XQPreference")
    return tonumber(XQPreference.get(XQConfigs.PREF_TIMESTAMP, "0"))
end

function setDetectionTimestamp()
    local XQPreference = require("xiaoqiang.XQPreference")
    XQPreference.set(XQConfigs.PREF_TIMESTAMP, tostring(os.time()))
end

function getWifiLog()
    os.execute(XQConfigs.WIFI_LOG_COLLECTION)
end

function getNvramConfigs()
    local configs = {}
    configs["wifi_ssid"] = XQFunction.nvramGet("nv_wifi_ssid", "")
    configs["wifi_enc"] = XQFunction.nvramGet("nv_wifi_enc", "")
    configs["wifi_pwd"] = XQFunction.nvramGet("nv_wifi_pwd", "")
    configs["rom_ver"] = XQFunction.nvramGet("nv_rom_ver", "")
    configs["rom_channel"] = XQFunction.nvramGet("nv_rom_channel", "")
    configs["hardware"] = XQFunction.nvramGet("nv_hardware", "")
    configs["uboot"] = XQFunction.nvramGet("nv_uboot", "")
    configs["linux"] = XQFunction.nvramGet("nv_linux", "")
    configs["ramfs"] = XQFunction.nvramGet("nv_ramfs", "")
    configs["sqafs"] = XQFunction.nvramGet("nv_sqafs", "")
    configs["rootfs"] = XQFunction.nvramGet("nv_rootfs", "")
    configs["sys_pwd"] = XQFunction.nvramGet("nv_sys_pwd", "")
    configs["wan_type"] = XQFunction.nvramGet("nv_wan_type", "")
    configs["pppoe_name"] = XQFunction.nvramGet("nv_pppoe_name", "")
    configs["pppoe_pwd"] = XQFunction.nvramGet("nv_pppoe_pwd", "")
    return configs
end

function noflushdStatus()
    return os.execute("/etc/init.d/noflushd status")
end

function noflushdSwitch(on)
    if on then
        return os.execute("/etc/init.d/noflushd on") == 0
    else
        return os.execute("killall -s 10 noflushd ; /etc/init.d/noflushd off") == 0
    end
end

function getModulesList()
    local uci = require("luci.model.uci").cursor()
    local result = {}
    local modules = uci:get_all("module", "common")
    for key, value in pairs(modules) do
        if key and value and not key:match("%.") then
            result[key] = value
        end
    end
    if _G.next(result) == nil then
        return nil
    else
        return result
    end
end

function bdataInfo()
    local LuciUtil = require("luci.util")
	local bdata = {}
	local str = LuciUtil.exec("bdata show")


    while true do
        local i  = string.find(str,"\n")

        if nil == i then
            break
        end

        local subStr = string.sub(str,1,i - 1)

		local j = string.find(subStr,"=")
		if j then
			k = string.sub(subStr,1,j - 1)
			v = string.sub(subStr,j + 1,#subStr)
			if v then
				bdata[k] = v
			end
		end


		str = string.sub(str,i + 1,#str)
    end

	return bdata
end

function facInfo()
    local LuciUtil = require("luci.util")
    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
    local fac = {}
    local ssid1, ssid2 = XQWifiUtil.getWifissid()
    fac["wl0_ssid"] = ssid2
    fac["wl1_ssid"] = ssid1
    fac["version"] = getRomVersion()
    fac["init"] = getInitInfo()
    fac["ssh"] = tonumber(XQFunction.nvramGet("ssh_en", 0)) == 1 and true or false
    fac["uart"] = tonumber(XQFunction.nvramGet("uart_en", 0)) == 1 and true or false
    fac["telnet"] = tonumber(XQFunction.nvramGet("telnet_en", 0)) == 1 and true or false
    fac["facmode"] = tonumber(LuciUtil.exec("cat /proc/xiaoqiang/ft_mode 2>/dev/null")) == 1 and true or false
    local start = tonumber(LuciUtil.exec("fdisk -lu | grep /dev/sda4 | awk {'print $2'}"))
    if start then
        start = math.mod(start ,8) == 0 and true or false
    else
        start = false
    end
    fac["4kblock"] = start
    return fac
end

function _(text)
    return text
end

NETTB = {
    ["1"] = _("路由器没有检测到WAN口网线接入"),
    ["2"] = _("DHCP服务没有响应"),
    ["3"] = _("宽带拨号服务无响应"),
    ["4"] = _("上级网络IP与路由器局域网IP有冲突"),
    ["5"] = _("网关不可达"),
    ["6"] = _("DNS服务器无法服务，可以尝试自定义DNS解决（114.114.114.114, 114.114.115.115  国外8.8.8.8  8.8.4.4)"),
    ["7"] = _("自定义的DNS无法服务，请关闭自动以DNS或者重新设置"),
    ["8"] = _("无线中继，无法中继上级"),
    ["9"] = _("有线中继，无法中继上级"),
    ["10"] = _("静态IP，连接时连接断开"),
    ["31"] = _("PPPoE服务器不允许一个账号同时登录"),
    ["32"] = _("PPPoE上网是用户名或者密码错误 691"),
    ["33"] = _("PPPoE上网是用户名或者密码错误 678")
}

function nettb()
    local LuciJson = require("json")
    local LuciUtil = require("luci.util")
    local XQLanWanUtil = require("xiaoqiang.util.XQLanWanUtil")
    local nettb = {
        ["code"] = 0,
        ["reason"] = ""
    }
    local result = LuciUtil.exec("/usr/sbin/nettb")
    if not XQFunction.isStrNil(result) then
        result = LuciUtil.trim(result)
        result = LuciJson.decode(result)
        if result.code then
            nettb.code = tonumber(result.code)
            if nettb.code == 32 then
                nettb.code = XQLanWanUtil._pppoeError(691) or 33
            elseif nettb.code == 33 then
                nettb.code = XQLanWanUtil._pppoeError(678) or 35
            end
            nettb.reason = NETTB[tostring(result.code)]
        end
    end
    return nettb
end

-- 黑色    100
-- 白色    101
-- 橘色    102
-- 绿色    103
-- 蓝色    104
-- 粉色    105
function getColor()
    local LuciUtil = require("luci.util")
    local color = LuciUtil.exec("nvram get color")
    if not XQFunction.isStrNil(color) then
        color = LuciUtil.trim(color)
        color = tonumber(color)
        if not color then
            color = 100
        end
    else
        local hardware = getHardware()
        if hardware and hardware == "R2D" then
            color = 101
        else
            color = 100
        end
    end
    return color
end

-- Get router bind info from server
function getBindinfo()
    local XQLog = require("xiaoqiang.XQLog")
    local LuciJson = require("json")
    local LuciUtil = require("luci.util")
    local cmd = "matool --method api_call --params \"/device/minet_get_bindinfo\""
    -- {"code":0,"data":{"bind":1,"admin":499744955}}
    -- {"code":0,"data":{"bind":0}}
    local ret = LuciUtil.exec(cmd)
    if ret then
        XQLog.log(6,"ret " .. ret)
        local json_ret = LuciJson.decode(ret)
        local code = json_ret["code"]
        XQLog.log(6,"code: " .. code)
        if code ~= nil and code == 0 then
            local bind = json_ret["data"]["bind"]
            XQLog.log(6,"bind: " .. bind)
            --XQLog.log(6,"admin: " .. json_ret["data"]["admin"]
            return bind
        else
            XQLog.log(6,"bind return 2")
            return 2
        end
    else
        -- get failed
        return 2
    end
end

function getRouterInfo()
    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
    local XQLanWanUtil = require("xiaoqiang.util.XQLanWanUtil")
    local json = require("cjson")
    local wifi = XQWifiUtil.getWifiStatus(1) or {}
    local bssid1, bssid2 = XQWifiUtil.getWifiBssid()
    local info = {
        ["hardware"] = getHardware(),
        ["channel"] = getChannel(),
        ["color"] = getColor(),
        ["locale"] = getRouterLocale(),
        ["ssid"] = wifi.ssid or "",
        ["bssid1"] = bssid1 or "",
        ["bssid2"] = bssid2 or "",
        ["ip"] = XQLanWanUtil.getLanIp()
    }
    return json.encode(info)
end

function getRouterInfo4Trafficd()
    local uci = require("luci.model.uci").cursor()
    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
    local LuciUtil = require("luci.util")
    local XQLanWanUtil = require("xiaoqiang.util.XQLanWanUtil")
    local json = require("cjson")
    local wifi = LuciUtil.exec("uci -q get wireless.@wifi-iface[0].ssid")
    local bssid1, bssid2 = XQWifiUtil.getWifiBssid()
    wifi = string.sub(wifi,0,string.len(wifi)-1)
    local info = {
        ["hardware"] = getHardware(),
        ["channel"] = getChannel(),
        ["color"] = getColor(),
        ["locale"] = getRouterLocale(),
        ["ssid"] = wifi or "",
        ["bssid1"] = bssid1 or "",
        ["bssid2"] = bssid2 or "",
        ["ip"] = XQLanWanUtil.getLanIp(),
        --add for tbus client auto bind
        ["sn"] = getSN(),
        --["bind"] = getBindinfo()
        ["bind_status"] = (tonumber(uci:get("bind", "info", "status")) or 0),
        ["bind_record"] = (tonumber(uci:get("bind", "info", "record")) or 0)
    }
    return json.encode(info)
end

function backupSysLog()
    local XQConfigs = require("xiaoqiang.common.XQConfigs")
    local uci = require("luci.model.uci").cursor()
    local fs = require("nixio.fs")
    local lucisys = require("luci.sys")
    local backuppath = "/tmp/syslogbackup/"
    local lanip = uci:get("network", "lan", "ipaddr") or "192.168.31.1"
    function sane()
        return lucisys.process.info("uid")
                == fs.stat(backuppath, "uid")
            and fs.stat(backuppath, "modestr")
                == "rwx------"
    end
    function prepare()
        fs.mkdir(backuppath, 700)
    end
    if not sane() then
        prepare()
    else
        os.execute("rm "..backuppath.."*.tar.gz")
    end
    os.execute("/usr/sbin/log_collection.sh >/dev/null 2>/dev/null")
    if fs.access(XQConfigs.LOG_ZIP_FILEPATH) then
        local filename = os.date("%Y-%m-%d--%X",os.time())..".tar.gz"
        os.execute("cp "..XQConfigs.LOG_ZIP_FILEPATH.." "..backuppath..filename)
        os.execute("rm "..XQConfigs.LOG_ZIP_FILEPATH)
        return lanip.."/backup/log/"..filename
    end
    return nil
end

function getCachedDirInfo()
    local json = require("json")
    local fb = io.open("/tmp/dir_info", "r")
    if fb then
        local content = fb:read("*a")
        fb:close()
        local suc, info = pcall(json.decode, content)
        if suc and info then
            return info
        else
            return nil
        end
    else
        return nil
    end
end

function getDirectoryInfo(dpath)
    local LuciUtil = require("luci.util")
    local result = {
        ["total"] = "",
        ["info"] = {}
    }
    local dpath = dpath or "/userdisk/data/"
    if not dpath:match("/$") then
        dpath = dpath.."/"
    end
    local info = LuciUtil.execl("du -h -d 1 "..dpath)
    local count = #info
    for index, line in ipairs(info) do
        if line then
            local size, path = line:match("(%S+)%s+(%S+)")
            if path and index ~= count then
                local item = {
                    ["name"] = path:gsub(dpath, ""),
                    ["size"] = size,
                    ["path"] = path,
                    ["type"] = "folder"
                }
                table.insert(result.info, item)
            elseif path and index == count then
                result.total = size
            end
        end
    end
    local fileinfo = LuciUtil.execl("ls -lh "..dpath)
    for _, line in ipairs(fileinfo) do
        if line then
            local mod, size = line:match("(%S+)%s+%S+%s+%S+%s+%S+%s+(%S+)%s+")
            local filename = line:match("%s(%S+)$")
            if mod and not mod:match("^d") then
                local item = {
                    ["name"] = filename,
                    ["size"] = size,
                    ["path"] = dpath..filename,
                    ["type"] = "file"
                }
                table.insert(result.info, item)
            end
        end
    end
    return result
end

function backupFiles(files, target)
    if files and type(files) == "table" then
        local target = target or "/tmp/usb/"
        for _, item in ipairs(files) do
            if item["type"] and item["path"] then
                if item["type"] == "folder" then
                    local cp = "cp -r '"..item.path.."' "..target
                    os.execute("echo 1 '"..item.path.."' > /tmp/backup_files_status")
                elseif item["type"] == "file" then
                    local cp = "cp '"..item.path.."' "..target
                    os.execute("echo 1 '"..item.path.."' > /tmp/backup_files_status")
                end
                os.execute(cp)
            end
        end
    end
    os.execute("echo 2 > /tmp/backup_files_status")
end

-- 1 拷贝中
-- 2 拷贝完成
-- 3 拷贝失败
function backupStatus()
    local LuciUtil = require("luci.util")
    local result = {
        ["status"] = 0,
        ["description"] = ""
    }
    local status = LuciUtil.exec("cat /tmp/backup_files_status 2>/dev/null")
    if not XQFunction.isStrNil(status) then
        if status:match("^2") then
            result.status = 2
        elseif status:match("^1") then
            result.status = 1
            result.description = status:gsub("1 ", "")
        elseif status:match("^3") then
            result.status = 3
        end
    end
    return result
end

function cancelBackup()
    local LuciUtil = require("luci.util")
    local pid = LuciUtil.exec("cat /tmp/backup_files_pid 2>/dev/null")
    if not XQFunction.isStrNil(pid) then
        os.execute("kill -9 "..pid)
    end
end

function getPluginIdList()
    local fs = require("nixio.fs")
    local itr = fs.dir("/userdisk/appdata/app_infos")
    local ids = {}
    if itr then
        for filename in itr do
            local id = filename:match("(%d+)")
            if id then
                table.insert(ids, id)
            end
        end
    end
    return table.concat(ids, ",")
end

function usbMode()
    local LuciUtil = require("luci.util")
    local usbpath = LuciUtil.exec("cat /tmp/usbDeployRootPath.conf 2>/dev/null")
    if XQFunction.isStrNil(usbpath) then
        return nil
    else
        return LuciUtil.trim(usbpath)
    end
end

-- @return true/false 降级/非降级
function checkRomVersion(filepath)
    local LuciUtil = require("luci.util")
    local info = LuciUtil.execl("cd /tmp; mkxqimage -V '"..filepath.."'".." 2>/dev/null")
    local version
    local cversion = getRomVersion()
    if info and type(info) == "table" then
        for _, line in ipairs(info) do
            if not XQFunction.isStrNil(line) then
                line = line:match("%s+option%sROM%s+'(%S+)'")
                if line then
                    version = line
                    break
                end
            end
        end
    end
    if version and cversion then
        version = LuciUtil.split(version, ".")
        cversion = LuciUtil.split(cversion, ".")
        if #version == #cversion then
            for index, value in ipairs(cversion) do
                if tonumber(value) > tonumber(version[index]) then
                    return true
                elseif tonumber(value) < tonumber(version[index]) then
                    return false
                end
            end
            return false
        end
    end
    return true
end

function getHwnatStatus()
    local uci = require("luci.model.uci").cursor()
    local fstart = uci:get("hwnat", "switch", "force_start")
    return tonumber(fstart) or 0
end

function hwnatSwitch(on)
    local uci = require("luci.model.uci").cursor()
    uci:set("hwnat", "switch", "force_start", on and 1 or 0)
    uci:commit("hwnat")
    if on then
        os.execute("/etc/init.d/hwnat start >/dev/null 2>/dev/null")
    else
        os.execute("/etc/init.d/hwnat stop >/dev/null 2>/dev/null")
    end
end

function httpStatus()
    local uci = require("luci.model.uci").cursor()
    local status = uci:get("http_status_stat", "settings", "enabled") or 0
    return tonumber(status)
end

function httpSwitch(on)
    local cmd = "/etc/init.d/http_status_stat "..(on and "on" or "off").." >/dev/null 2>/dev/null"
    return os.execute(cmd) == 0
end

function ustackSwitch(on)
    local cmd = "/etc/init.d/ustack "..(on and "on" or "off").." >/dev/null 2>/dev/null"
    return os.execute(cmd) == 0
end

function getSysStatus()
    local ubus = require("ubus")
    local status = {
        ["cpuload"] = 0,
        ["fanspeed"] = 1,
        ["temperature"] = 40
    }
    local conn = ubus.connect()
    if conn then
        local ustatus = conn:call("rmonitor", "status", {})
        if ustatus then
            status.cpuload = tonumber(ustatus.cpuload)
            status.fanspeed = tonumber(ustatus.fanspeed)
            status.temperature = tonumber(ustatus.temperature)
        end
        conn:close()
    end
    return status
end

-- open: true/false
-- mac:  mac address
-- opt:  0/1 (add/remove)
function webAccessControl(open, mac, opt)
    local datatypes = require("luci.cbi.datatypes")
    local mode = getMacfilterMode("admin")
    if open then
        if mac and datatypes.macaddr(mac) then
            local admin = opt == 0 and "yes" or "no"
            local cmd = "/usr/sbin/sysapi macfilter set mac="..string.lower(mac).." admin="..admin
            os.execute(cmd)
            if mode == 1 then
                os.execute("/usr/sbin/sysapi macfilter set adminmode=whitelist")
            end
        end
    else
        os.execute("/usr/sbin/sysapi macfilter set adminmode=close")
    end
end

function webAccessInfo()
    local LuciUtil = require("luci.util")
    local mode = getMacfilterMode("admin")
    local info = {
        ["open"] = mode == 0
    }
    if not info.open then
        return info
    end
    local alist
    local data = LuciUtil.execi("/usr/sbin/sysapi macfilter get")
    if data then
        for line in data do
            line = line..";"
            local mac = line:match('mac=(%S-);')
            local admin = line:match('admin=(%S-);')
            if mac and admin and admin == "yes" then
                if not alist then
                    alist = {}
                end
                table.insert(alist, XQFunction.macFormat(mac))
            end
        end
        info["list"] = alist
    end
    return info
end

--[[
CST+12(IDL-国际换日线)
CST+11 ( MIT - 中途岛标准时间)
CST+10（HST - 夏威夷－阿留申标准时间）
CST+9:30 (MSIT - 马克萨斯群岛标准时间)
CST+9（AKST - 阿拉斯加标准时间）
CST+8（PSTA - 太平洋标准时间A）
CST+7（MST - 北美山区标准时间）
CST+6（CST - 北美中部标准时间）
CST+5（EST - 北美东部标准时间）
CST+4:30 ( RVT - 委内瑞拉标准时间）
CST+4（AST - 大西洋标准时间）
CST+3:30（NST - 纽芬兰岛标准时间）
CST+3 ( SAT - 南美标准时间 )
CST+2 ( BRT - 巴西时间)
CST+1 ( CVT - 佛得角标准时间 )
CST（WET - 欧洲西部时区，GMT - 格林威治标准时间）
CST-1（CET - 欧洲中部时区）
CST-2（EET - 欧洲东部时区）
CST-3（MSK - 莫斯科时区）
CST-3:30 ( IRT - 伊朗标准时间)
CST-4 ( META - 中东时区A )
CST-4:30 ( AFT- 阿富汗标准时间 )
CST-5 ( METB - 中东时区B )
CST-5:30 ( IDT - 印度标准时间 )
CST-5:45 ( NPT - 尼泊尔标准时间 )
CST-6 ( BHT - 孟加拉标准时间 )
CST-6:30 ( MRT - 缅甸标准时间 )
CST-7 ( MST - 中南半岛标准时间 )
CST-8（EAT - 东亚标准时间）
CST-8:30（朝鲜标准时间）
CST-9（FET- 远东标准时间）
CST-9:30（ACST - 澳大利亚中部标准时间）
CST-10（AEST - 澳大利亚东部标准时间）
CST-10:30 ( FAST - 澳大利亚远东标准时间）
CST-11 ( VTT - 瓦努阿图标准时间 )
CST-11:30 ( NFT - 诺福克岛标准时间 )
CST-12（PSTB - 太平洋标准时间B）
CST-12:45 ( CIT - 查塔姆群岛标准时间 )
CST-13（PSTC - 太平洋标准时间C）
CST-14（PSTD - 太平洋标准时间D）
]]--

CST12 = {
    "CST+12"
}

CST11 = {
    "SST+11SDT,M9.5.0/0,M4.1.0/0",
    "CST+11"
}

CST10 = {
    "CST+10"
}

CST9_30 = {
    "CST+9:30"
}

CST9 = {
    "AKST+9AKDT,M3.2.0/2,M11.1.0/2"
}

CST8 = {
    "PST+8PDT,M3.2.0/2,M11.1.0/2",
    "PST+8PDT,M3.2.0/2,M11.1.0/2"
}

CST7 = {
    "MST+7MDT,M4.1.0/2,M10.5.0/2",
    "MST+7MDT,M3.2.0/2,M11.1.0/2",
    "CST+7"
}

CST6 = {
    "CST+6CDT,M4.1.0/2,M10.5.0/2",
    "CST+6",
    "CST+6CDT,M3.2.0/2,M11.1.0/2",
    "CST+6"
}

CST5 = {
    "CST+5",
    "EST+5EDT,M3.2.0/2,M11.1.0/2",
    "EST+5EDT,M3.2.0/2,M11.1.0/2"
}

CST4_30 = {
    "CST+4:30"
}

CST4 = {
    "AST+4ADT,M3.2.0/2,M11.1.0/2",
    "AMST+4AMT,M11.1.0/0,M2.3.0/0",
    "CST+4",
    "CLT+4CLST,M8.2.0/0,M5.2.0/0",
    "PYST+4PYT,M10.1.0/0,M3.4.0/0"
}

CST3_30 = {
    "NST+3:30NDT,M3.2.0/2,M11.1.0/2"
}

CST3 = {
    "BRT+3BRT,M11.1.0/0,M2.3.0/0",
    "CST+3",
    "CST+3",
    "CST+3",
    "CST+3"
}

CST2 = {
    "CST+2",
    "ZST+2ZDT,M3.5.0/2,M9.5.0/2"
}

CST1 = {
    "CST+1",
    "AZOT+1AZOST,M3.5.0/0,M10.5.0/1"
}

CST = {
    "GMT+0IST,M3.5.0/1,M10.5.0/2",
    "CST",
    "CST",
    "CST"
}

CST_1 = {
    "CET-1CEST,M3.5.0/2,M10.5.0/3",
    "CET-1CEST,M3.5.0/2,M10.5.0/3",
    "CET-1CEST,M3.5.0/2,M10.5.0/3",
    "CET-1CEST,M3.5.0/2,M10.5.0/3",
    "CST-1",
    "CST-1"
}

CST_2 = {
    "EET-2EEST,M3.5.5/0,M10.5.5/1",
    "EET-2EEST,M3.5.0/0,M10.5.0/0",
    "EET-2EEST,M3.5.5/0,M10.5.5/0",
    "CST-2",
    "EET-2EEST,M3.5.0/3,M10.5.0/4",
    "CST-2",
    "CST-2",
    "EET-2EEST,M3.5.0/3,M10.5.0/4",
    "CST-2",
    "CST-2"
}

CST_3 = {
    "CST-3",
    "CST-3",
    "CST-3",
    "CST-3"
}

CST_3_30 = {
    "CST-3:30"
}

CST_4 = {
    "CST-4",
    "CST-4",
    "CST-4",
    "CST-4",
    "CST-4",
    "CST-4"
}

CST_4_30 = {
    "CST-4:30"
}

CST_5 = {
    "CST-5",
    "CST-5"
}

CST_5_30 = {
    "CST-5:30",
    "CST-5:30"
}

CST_5_45 = {
    "CST-5:45"
}

CST_6 = {
    "CST-6",
    "CST-6",
    "CST-6"
}

CST_6_30 = {
    "CST-6:30"
}

CST_7 = {
    "CST-7",
    "CST-7"
}

CST_8 = {
    "CST-8",
    "CST-8",
    "CST-8",
    "CST-8",
    "CST-8",
    "CST-8"
}

CST_8_30 = {
    "CST-8:30"
}

CST_9 = {
    "CST-9",
    "CST-9",
    "CST-9"
}

CST_9_30 = {
    "ACST-9:30ACDT,M10.1.0/2,M4.1.0/3",
    "CST-9:3"
}

CST_10 = {
    "CST-10",
    "CST-10",
    "AEST-10AEDT,M10.1.0/2,M4.1.0/3",
    "AEST-10AEDT,M10.1.0/2,M4.1.0/3",
    "CST-10"
}

CST_10_30 = {
    "CST-10:30"
}

CST_11 = {
    "CST-11",
    "CST-11"
}

CST_11_30 = {
    "CST-11:30"
}

CST_12 = {
    "NZST-12NZDT,M9.5.0/2,M4.1.0/3",
    "FST-12FDT,M11.1.0/2,M1.2.0/3",
    "CST-12",
    "CST-12"
}

CST_12_45 = {
    "CST-12:45"
}

CST_13 = {
    "CST-13"
}

CST_14 = {
    "CST-14"
}

TIME_ZONE = {
    ["CST+12"] = CST12,
    ["CST+11"] = CST11,
    ["CST+10"] = CST10,
    ["CST+9:30"] = CST9_30,
    ["CST+9"] = CST9,
    ["CST+8"] = CST8,
    ["CST+7"] = CST7,
    ["CST+6"] = CST6,
    ["CST+5"] = CST5,
    ["CST+4:30"] = CST4_30,
    ["CST+4"] = CST4,
    ["CST+3:30"] = CST3_30,
    ["CST+3"] = CST3,
    ["CST+2"] = CST2,
    ["CST+1"] = CST1,
    ["CST"] = CST,
    ["CST-1"] = CST_1,
    ["CST-2"] = CST_2,
    ["CST-3"] = CST_3,
    ["CST-3:30"] = CST_3_30,
    ["CST-4"] = CST_4,
    ["CST-4:30"] = CST_4_30,
    ["CST-5"] = CST_5,
    ["CST-5:30"] = CST_5_30,
    ["CST-5:45"] = CST_5_45,
    ["CST-6"] = CST_6,
    ["CST-6:30"] = CST_6_30,
    ["CST-7"] = CST_7,
    ["CST-8"] = CST_8,
    ["CST-8:30"] = CST_8_30,
    ["CST-9"] = CST_9,
    ["CST-9:30"] = CST_9_30,
    ["CST-10"] = CST_10,
    ["CST-10:30"] = CST_10_30,
    ["CST-11"] = CST_11,
    ["CST-11:30"] = CST_11_30,
    ["CST-12"] = CST_12,
    ["CST-12:45"] = CST_12_45,
    ["CST-13"] = CST_13,
    ["CST-14"] = CST_14
}

function getSysTime()
    local uci = require("luci.model.uci").cursor()
    local info = {
        ["timezone"] = "CST-8",
        ["index"] = 0,
        ["year"] = 0,
        ["month"] = 0,
        ["day"] = 0,
        ["hour"] = 0,
        ["min"] = 0,
        ["sec"] = 0
    }
    local date = os.date("*t", os.time())
    info.year = date.year
    info.month = date.month
    info.day = date.day
    info.hour = date.hour
    info.min = date.min
    info.sec = date.sec
    uci:foreach("system", "system",
        function(s)
            if not XQFunction.isStrNil(s.timezone) then
                info.timezone = s.timezone
                info.index = tonumber(s.timezoneindex or 0) or 0
            end
        end
    )
    return info
end

function setSysTime(time, tzone, index)
    if not XQFunction.isStrNil(tzone) and TIME_ZONE[tzone] then
        local fs = require("nixio.fs")
        local uci = require("luci.model.uci").cursor()
        uci:foreach("system", "system",
            function(s)
                if not XQFunction.isStrNil(s.timezone) then
                    uci:set("system", s[".name"], "timezone", tzone)
                    uci:set("system", s[".name"], "timezoneindex", index)
                end
            end
        )
        uci:commit("system")
        fs.writefile("/tmp/TZ", TIME_ZONE[tzone][index + 1].."\n")

        -- add case for R3600 sync timezone from CAP to RE
        local XQSysUtil = require("xiaoqiang.util.XQSysUtil")
        local XQLog = require("xiaoqiang.XQLog")
        -- add mesh role for R3600, read xiaoqiang.common.NETMODE=whc_re
        local hardware = XQSysUtil.getHardware()
        if hardware then
            if hardware == "R3600" then
                local uci = require("luci.model.uci").cursor()
                local mode = uci:get("xiaoqiang", "common", "NETMODE") or ""
                if mode:match("^whc_cap") then
                    -- format time info
                    local info = {
                        ["cmd"] = "sync_time",
                        ["timezone"] = tostring(tzone),
                        ["index"] = tostring(index),
                        ["tz_value"] = tostring(TIME_ZONE[tzone][index + 1]),
                    }

                    -- for tbus transfer, encode twice
                    local json = require("luci.json")
                    local j_info = json.encode(info)
                    local j_msg = json.encode(j_info)
                    XQLog.log(6,"R3600 CAP call RE sync timezone msg:" ..j_msg)
                    os.execute("/sbin/whc_to_re_common_api.sh action \'" .. j_msg .. "\'")
                end
            end
        end
        -- add end
    end
    if not XQFunction.isStrNil(time) and time:match("^%d+%-%d+%-%d+ %d+:%d+:%d+$") then
        XQFunction.forkExec("echo 'ok,xiaoqiang' > /tmp/ntp.status; sleep 3; date -s \""..time.."\"")
    end
end

-- 开关蓝灯
function setBlueLed(onoff)
    local logger = require("xiaoqiang.XQLog")
    local uci = require("luci.model.uci").cursor()
    local cmd = "gpio 3 "..(onoff and "0" or "1")
    uci:set("xiaoqiang", "common", "BLUE_LED", onoff and "1" or "0")
    uci:commit("xiaoqiang")
    local hardware = getHardware()
    --logger.log(4, "hardware=" .. hardware)
    --logger.log(4, string.format("@@@@@routerLed onoff = %s", tostring(onoff)))
    if hardware == "R2100" or hardware == "R2200" then
        if onoff == false then
            cmd = "xqled sys blue && xqled sys_off; xqled func blue && xqled func_off"
        else
            cmd = "xqled sys_ok; [ -f /usr/sbin/wan_check.sh ] && /usr/sbin/wan_check.sh reset "
        end
    end

    if hardware == "R3600" then
        if onoff == false then
            cmd = "xqled sys_off; xqled func_off; xqled ant_off"
        else
            cmd = "xqled sys_ok; [ -f /usr/sbin/wan_check.sh ] && /usr/sbin/wan_check.sh reset; [ -f /etc/init.d/scan ] && /etc/init.d/scan led_reset"
        end
    end

    logger.log(4, "XQSysUtil setBlueLed cmd=" .. cmd)

    os.execute(cmd)
end

function getBlueLed()
    local uci = require("luci.model.uci").cursor()
    local onoff = uci:get("xiaoqiang", "common", "BLUE_LED") or "1"
    return tonumber(onoff)
end

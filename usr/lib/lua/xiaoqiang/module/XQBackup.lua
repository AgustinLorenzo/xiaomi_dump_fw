module ("xiaoqiang.module.XQBackup", package.seeall)

local DESFILE    = "/tmp/cfg_backup.des"
local MBUFILE    = "/tmp/cfg_backup.mbu"
local TARMBUFILE = "/tmp/cfgbackup.tar.gz"

-- backup functions
local function _mi_basic_info()
    local uci = require("luci.model.uci").cursor()
    local info = {
        ["name"] = "",
        ["location"] = "",
        ["password"] = ""
    }
    info.name = uci:get("xiaoqiang", "common", "ROUTER_NAME") or ""
    info.location = uci:get("xiaoqiang", "common", "ROUTER_LOCALE") or ""
    info.password = uci:get("account", "common", "admin") or "b3a4190199d9ee7fe73ef9a4942a69fece39a771"
    return info
end

local function _mi_wifi_info()
    local wifi = require("xiaoqiang.util.XQWifiUtil")
    local info = {
        ["24g"] = {},
        ["5g"] = {}
    }
    info["24g"] = wifi.getWifiBasicInfo(1)
    info["5g"] = wifi.getWifiBasicInfo(2)
    return info
end

local function _mi_network_info()
    local uci = require("luci.model.uci").cursor()
    local info = uci:get_all("network", "wan") or {["proto"] = "dhcp", ["ifname"] = "eth0.2"}
    return info
end

local function _mi_lan_info()
    local uci = require("luci.model.uci").cursor()
    local info = {
        ["network"] = {},
        ["dhcp"] = {}
    }
    info["network"] = uci:get_all("network", "lan")
    info["dhcp"] = uci:get_all("dhcp", "lan")
    return info
end

local function _mi_arn_info()
    local wifi = require("xiaoqiang.util.XQWifiUtil")
    local XQPushUtil = require("xiaoqiang.util.XQPushUtil")
    local settings = XQPushUtil.pushSettings()
    local info = {
        ["enable"] = settings.auth and 1 or 0,
        ["mode"] = 0
    }
    info["mode"] = wifi.getWiFiMacfilterModel()
    info["list"] = wifi.getCurrentMacfilterList()
    return info
end

local function _mi_access_info()
    local device = require("xiaoqiang.util.XQDeviceUtil")
    local datatypes = require("luci.cbi.datatypes")
    local macs = {}
    local dbmacs = device.getDeviceMacsFromDB()
    for i, mac in ipairs(dbmacs) do
        if i > 50 then
            break
        end
        if datatypes.macaddr(mac) then
            table.insert(macs, mac)
        end
    end
    return device.getDevicesPermissions(macs)
end

-- restore functions
local function _mi_basic_info_restore(info)
    local uci = require("luci.model.uci").cursor()
    if info then
        if info["name"] then
            uci:set("xiaoqiang", "common", "ROUTER_NAME", info.name)
        end
        if info["location"] then
            uci:set("xiaoqiang", "common", "ROUTER_LOCALE", info.location)
        end
        uci:commit("xiaoqiang")
        if info["password"] then
            uci:set("account", "common", "admin", info.password)
            uci:commit("account")
        end
    end
end

local function _mi_wifi_info_restore(info)
    local wifi = require("xiaoqiang.util.XQWifiUtil")
    if info then
        local w1 = info["24g"]
        local w2 = info["5g"]
        if w1 then
            local on1 = tonumber(w1.on) == 0 and 1 or 0
            wifi.setWifiBasicInfo(1, w1.ssid, w1.password, w1.encryption, w1.channel, w1.txpwr, w1.hidden, on1, w1.bandwidth, w1.bsd, w1.txbf)
        end
        if w2 then
            local on2 = tonumber(w2.on) == 0 and 1 or 0
            wifi.setWifiBasicInfo(2, w2.ssid, w2.password, w2.encryption, w2.channel, w2.txpwr, w2.hidden, on2, w2.bandwidth, w2.bsd, w2.txbf)
        end
    end
end

local function _mi_network_info_restore(info)
    local uci = require("luci.model.uci").cursor()
    if info then
        uci:delete("network", "wan")
        uci:section("network", "interface", "wan", info)
        uci:commit("network")
    end
end

local function _mi_lan_info_restore(info)
    local uci = require("luci.model.uci").cursor()
    if info then
        local network = info["network"]
        local dhcp = info["dhcp"]
        if network then
            uci:delete("network", "lan")
            uci:section("network", "interface", "lan", network)
            uci:commit("network")
        end
        if dhcp then
            uci:delete("dhcp", "lan")
            uci:section("dhcp", "dhcp", "lan", dhcp)
            uci:commit("dhcp")
        end
    end
end

local function _mi_arn_info_restore(info)
    local wifi = require("xiaoqiang.util.XQWifiUtil")
    local XQPushUtil = require("xiaoqiang.util.XQPushUtil")
	
    if info then
        local new_mode = info["mode"]
        local new_mlist = info["list"]
        local new_enable = info["enable"]
        local cur_mlist = wifi.getCurrentMacfilterList()
        local cur_mode = wifi.getWiFiMacfilterModel()

        --remove current setting
        if cur_mlist then
            wifi.editWiFiMacfilterList(cur_mode - 1, cur_mlist, 1)
        end
		
        --restore      
        XQPushUtil.pushConfig("auth", new_enable)
        wifi.setWiFiMacfilterModel(new_enable, new_mode - 1)	
        if new_mlist then
            wifi.editWiFiMacfilterList(new_mode - 1, new_mlist, 0)
        end
    end
end

local function _mi_access_info_restore(info)
    local sys = require("xiaoqiang.util.XQSysUtil")
    local datatypes = require("luci.cbi.datatypes")
    if info then
	--remove current setting
		
	--set new setting
	if type(info) == "table" then
	    for mac, value in pairs(info) do
		if datatypes.macaddr(mac) then
	  	    sys.setMacFilter(mac, tostring(value.lan), tostring(value.wan), tostring(value.admin), tostring(value.pridisk))
		end
	    end
	end
    end
end

local MESSAGES = {
    ["mi_basic_info"]   = _("路由器名和管理密码"),
    ["mi_wifi_info"]    = _("wifi设置(wifi名称和密码等)"),
    ["mi_network_info"] = _("上网设置(拨号方式和宽带帐号密码等)"),
    ["mi_lan_info"]     = _("DHCP服务和局域网IP设置"),
    ["mi_arn_info"]     = _("无线访问黑白名单"),
    ["mi_access_info"]  = _("设备访问权限")
}

local BACKUP_FUNCTIONS = {
    ["mi_basic_info"]   = _mi_basic_info,
    ["mi_wifi_info"]    = _mi_wifi_info,
    ["mi_network_info"] = _mi_network_info,
    ["mi_lan_info"]     = _mi_lan_info,
    ["mi_arn_info"]     = _mi_arn_info,
    ["mi_access_info"]  = _mi_access_info
}

local RESTORE_FUNCTIONS = {
    ["mi_basic_info"]   = _mi_basic_info_restore,
    ["mi_wifi_info"]    = _mi_wifi_info_restore,
    ["mi_network_info"] = _mi_network_info_restore,
    ["mi_lan_info"]     = _mi_lan_info_restore,
    ["mi_arn_info"]     = _mi_arn_info_restore,
    ["mi_access_info"]  = _mi_access_info_restore
}

function save_info(keys, info)
    local uci       = require("luci.model.uci").cursor()
    local json      = require("json")
    local aes       = require("aeslua")
    local fs        = require("nixio.fs")
    local lucisys   = require("luci.sys")
    local backuppath = "/tmp/syslogbackup/"
    local key = uci:get("cfgbackup", "encryption", "key")
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
        os.execute("rm "..backuppath.."*.tar.gz >/dev/null 2>/dev/null")
    end
    local jstr = json.encode(info)
    local dstr = json.encode(keys)
    local data = aes.encrypt(key, jstr)
    local filename = os.date("%Y-%m-%d--%X",os.time())..".tar.gz"
    fs.writefile(MBUFILE, data)
    fs.writefile(DESFILE, dstr)
    os.execute("cd /tmp; tar -czf "..backuppath..filename.." cfg_backup.des cfg_backup.mbu >/dev/null 2>/dev/null")
    os.execute("rm "..MBUFILE.." >/dev/null 2>/dev/null")
    os.execute("rm "..DESFILE.." >/dev/null 2>/dev/null")
    local url = lanip.."/backup/log/"..filename
    return url
end

function defaultKeys()
    local uci = require("luci.model.uci").cursor()
    local info = {}
    local items = uci:get_list("cfgbackup", "backup", "item")
    if items then
        for _, key in ipairs(items) do
            if MESSAGES[key] then
                info[key] = MESSAGES[key]
            end
        end
    end
    return info
end

function backup(keys)
    local uci = require("luci.model.uci").cursor()
    local items
    if not keys then
        items = uci:get_list("cfgbackup", "backup", "item")
    else
        items = keys
    end
    local info = {}
    if items then
        for _, item in ipairs(items) do
            local func = BACKUP_FUNCTIONS[item]
            if func then
                info[item] = func()
            end
        end
        return save_info(items, info)
    end
    return nil
end

-- 0:succeed
-- 1:file does not exist
-- 2:no description file
-- 3:no mbu file
function extract(filepath)
    local fs = require("nixio.fs")
    local tarpath = filepath
    if not tarpath then
        tarpath = TARMBUFILE
    end
    if not fs.access(tarpath) then
        return 1
    end
    -- if contain symlinks return
    local ln = os.execute("tar -tzvf ".. tarpath .. " | grep ^l >/dev/null 2>&1")
    if ln == 0 then
        os.execute("rm -rf ".. tarpath)
        return 2
    end
    -- check if only DES and MBU file in tar.gz
    local fcheck=os.execute("tar -tzvf " .. tarpath .. " |grep -v .des|grep -v .mbu >/dev/null 2>&1")
    if fcheck == 0 then
        os.execute("rm -rf ".. tarpath)
        return 22
    end

    os.execute("cd /tmp; tar -xzf "..tarpath.." >/dev/null 2>&1")
    os.execute("rm "..tarpath.." >/dev/null 2>&1")
    if not fs.access(DESFILE) then
        return 2
    end
    if not fs.access(MBUFILE) then
        return 3
    end
    return 0
end

function getdes()
    local fs    = require("nixio.fs")
    local json  = require("json")
    local uci   = require("luci.model.uci").cursor()
    if not fs.access(DESFILE) then
        return nil
    end
    local data  = fs.readfile(DESFILE)
    local succ, info = pcall(json.decode, data)
    if succ and info then
        local des = {
            ["keys"] = {},
            ["unknown"] = {}
        }
        local items = uci:get_list("cfgbackup", "backup", "item")
        local dict = {}
        for _, key in ipairs(items) do
            dict[key] = true
        end
        for _, key in ipairs(info) do
            if dict[key] then
                des.keys[key] = MESSAGES[key]
            else
                table.insert(des.unknown, key)
            end
        end
        return des
    else
        return nil
    end
end

-- 0:succeed
-- 1:file does not exist
-- 2:decryption error
function restore(filepath, keys)
    local json  = require("json")
    local fs    = require("nixio.fs")
    local aes   = require("aeslua")
    local uci   = require("luci.model.uci").cursor()
    local mbufile = filepath
    if not mbufile then
        mbufile = MBUFILE
    end
    if not fs.access(mbufile) then
        return 1
    end
    local key   = uci:get("cfgbackup", "encryption", "key")
    local data  = fs.readfile(mbufile)
    os.execute("rm "..mbufile.." >/dev/null 2>/dev/null")
    local dstr  = aes.decrypt(key, data)
    if not dstr then
        return 2
    end
    local succ, infos = pcall(json.decode, dstr)
    if not succ then
        return 2
    end
    local items
    if not keys then
        items = uci:get_list("cfgbackup", "backup", "item")
    else
        items = keys
    end
    if items then
        for _, item in ipairs(items) do
            local func = RESTORE_FUNCTIONS[item]
            local info = infos[item]
            if func and info then
                func(info)
            end
        end
    end
    return 0
end

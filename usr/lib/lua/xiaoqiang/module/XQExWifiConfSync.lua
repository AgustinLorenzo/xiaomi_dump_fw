module ("xiaoqiang.module.XQExWifiConfSync", package.seeall)

local LuciHttp     = require("luci.http")
local XQLog        = require("xiaoqiang.XQLog")
local XQFunction   = require("xiaoqiang.common.XQFunction")
local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")

local work_directory  = "/tmp/extendwifi/"
local rom_config_path = "/etc/config/"
local rom_config_xqdb = "/etc/xqDb"
local rom_config_zip  = "config.tar.gz"
local debug_level     = 6


local ExWIFI_ERROR_CODE = {
    ["ERROR_INTERNAL"]     = 1639,
    ["ERROR_PEER_INFO"]    = 1640,
    ["ERROR_CONFIG_TRANS"] = 1641,
    ["ERROR_INVALID_MODE"] = 1642
}

-- temporary function
local function _peer_info()
    local util = require("xiaoqiang.module.XQExtendWifi")

    -- get token
    -- local remote   = "192.168.28.1"
    -- local mac      = "00:0C:43:28:80:C5"
    -- local password = "12345678"
    -- local token    = init.account_login(remote, mac, password)
    local token = util.get_token()
    if not token then
        XQLog.log(debug_level, "get token failed!")
        return nil
    end

    -- get mode
    --[[
    local mode = util.get_act()
    if (mode == "1") then
        mode = "active"
    elseif (mode == "2") then
        mode = "passive"
    else
        XQLog.log(debug_level, "get work mode failed!")
        return nil
    end
    --]]

    -- get remote
    local remote = util.get_peer_ip()
    if not remote then
        XQLog.log(debug_level, "get remote address failed!")
        return nil
    end

    return remote, token
end

local function _create_work_directory(work_directory)
    local fs = require("nixio.fs")
    os.execute("rm -rf " .. work_directory)
    return fs.mkdir(work_directory, 0600)
end

local function _clear_work_directory(work_directory)
    os.execute("rm -rf " .. work_directory)
end

-- post config file to peer
local function _init_active(remote, token)
    local sync_util  = require("xiaoqiang.module.XQExWifiConfSyncUtil")
    local config_zip = work_directory .. rom_config_zip
    local res, ssid_24g, passwd_24g, ssid_5g, passwd_5g

    -- : peer is un-initialized
    -- : peer already initialized
    XQLog.log(debug_level, "work in active mode")

    if (not remote) or (not token) then
        XQLog.log(debug_level, "invalid input parameter!")
        return ExWIFI_ERROR_CODE.ERROR_PEER_INFO
    end

    res = _create_work_directory(work_directory)
    if not res then
        XQLog.log(debug_level, "work directory create failed, " .. work_directory)
        return ExWIFI_ERROR_CODE.ERROR_INTERNAL
    end

    os.execute("tar -zcvf " .. config_zip .. " " .. rom_config_path .. " " .. rom_config_xqdb .. " >/dev/null 2>&1")

    res, ssid_24g, passwd_24g, ssid_5g, passwd_5g = sync_util.config_post(remote, token, config_zip)
    --res: peer execute result

    _clear_work_directory(work_directory)

    return res, ssid_24g, passwd_24g, ssid_5g, passwd_5g
end

-- get config file from peer
local function _init_passive(remote, token)
    local sync_util  = require("xiaoqiang.module.XQExWifiConfSyncUtil")
    local sync_uci   = require("xiaoqiang.module.XQExWifiConfSyncUci")
    local config_zip = work_directory .. rom_config_zip
    local res

    XQLog.log(debug_level, "work in passive mode")

    if (not remote) or (not token) then
        XQLog.log(debug_level, "invalid input parameter!")
        return ExWIFI_ERROR_CODE.ERROR_PEER_INFO
    end

    res = _create_work_directory(work_directory)
    if not res then
        XQLog.log(debug_level, "work directory create failed, " .. work_directory)
        return ExWIFI_ERROR_CODE.ERROR_INTERNAL
    end

    -- get config
    res = sync_util.config_get(remote, token, config_zip)
    if (res ~= 0) then
        XQLog.log(debug_level, "config file fetch failed!")
        _clear_work_directory(work_directory)
        return res
    end
    -- zip file is really there ?

    os.execute("tar -C " .. work_directory .. " -zxvf " .. config_zip .. " >/dev/null 2>&1")

    -- config synchronize
    -- if already initialized. skip some step
    res = sync_uci.config_merge()

    _clear_work_directory(work_directory)

    -- get wifi-hotspot info for App show
    local ssid_24g, passwd_24g, ssid_5g, passwd_5g = sync_uci.hotspot_info()

    return res, ssid_24g, passwd_24g, ssid_5g, passwd_5g
end

-- turn off local hotspot, tell peer reboot
local function _fini_active(remote, token)
    local sync_util = require("xiaoqiang.module.XQExWifiConfSyncUtil")

    local res = sync_util.config_finish(remote, token, nil, "yes")
    if res == 0 then
        -- turn off local hotspot when peer seems ok
        extendwifi_hotspot_shutdown()
    end
end

-- turn off peer hotspot, reboot
local function _fini_passive(remote, token)
    local sync_util = require("xiaoqiang.module.XQExWifiConfSyncUtil")

    local res = sync_util.config_finish(remote, token, "off", nil)

    -- do reboot even through peer has met some problem
    extendwifi_reboot()
end

-- reference to XQWifiUtil.apcli_set_inactive(ifname)
local function _apcli_shutdown(apcli_ifname)
    local sync_uci  = require("xiaoqiang.module.XQExWifiConfSyncUci")
    local wifi_util = require("xiaoqiang.util.XQWifiUtil")

    XQLog.log(debug_level, "enter _apcli_shutdown")

    if not apcli_ifname then
        return
    end
    XQLog.log(debug_level, "apcli_ifname: " .. apcli_ifname)

    local hardware  = sync_uci.hardware_info()
    if hardware then
       if hardware:match("^r1800") or hardware:match("^r4c$") or hardware:match("^r3600") then
           XQLog.log(debug_level, "hardware " .. hardware .. " match r1800 or r4c or r3600")
           local command0 = "killall -9 wpa_supplicant"
           local command1 = "ifconfig " .. apcli_ifname .. " down"
           local command2 = "wlanconfig " .. apcli_ifname .. " destroy"
           local dev = wifi_util.apcli_get_device(apcli_ifname)
           --local command3 = "ifconfig " .. dev:name() .. " down up"
           local command3 = "ifconfig " .. dev:name() .. " down"
           XQFunction.forkExec("sleep 2; " .. command0 .. "; " .. command1 .. "; " .. command2 .. "; " .. command3 .. ";")
       elseif hardware:match("^r1d") or hardware:match("^r2d") then
           XQLog.log(debug_level, "hardware " .. hardware .. " match r1d or r2d")
           local command0 = "wl -i " .. apcli_ifname .. " bss down"
           XQFunction.forkExec("sleep 2; " .. command0 .. ";")
       else
           XQLog.log(debug_level, "hardware " .. hardware)
           local command0 = "iwpriv " .. apcli_ifname .. " set ApCliEnable=0"
           local command1 = "iwpriv " .. apcli_ifname .." set ApCliAutoConnect=0"
           local command2 = "ifconfig " .. apcli_ifname .. " down"
           XQFunction.forkExec("sleep 2; " .. command0 .. "; " .. command1 .. "; " .. command2 .. ";")
       end
    end
end

-- Luci entry: work in passive mode
function extendwifi_config_pull()
    local config_zip = work_directory .. rom_config_zip
    local block

    XQLog.log(debug_level, "enter extendwifi_config_pull")

    res = _create_work_directory(work_directory)
    if not res then
        XQLog.log(debug_level, "work directory create failed, " .. work_directory)
        return nil
    end

    os.execute("tar -zcvf " .. config_zip .. " " .. rom_config_path .. " " .. rom_config_xqdb .. " >/dev/null 2>&1")

    local handle = io.open(config_zip, "r")
    if not handle then
        XQLog.log(debug_level, "config file open failed!")
        _clear_work_directory(work_directory)
        return nil
    end

    local md5sum = XQCryptoUtil.md5File(config_zip)
    if not md5sum then
        XQLog.log(debug_level, "config file calculate md5sum failed!")
        io.close(handle)
        _clear_work_directory(work_directory)
        return nil
    end

    LuciHttp.header('Content-Checksum', md5sum)
    LuciHttp.header('Content-Disposition', 'attachment; filename="%s"' %{rom_config_zip})
    LuciHttp.prepare_content("application/otect-stream")
    while true do
        block = handle:read(nixio.const.buffersize)
        if (not block) or (#block==0) then
            break
        else
            LuciHttp.write(block)
        end
    end
    handle:close()
    LuciHttp.close()

    _clear_work_directory(work_directory)

    return 0
end

-- Luci entry: work in active mode
function extendwifi_config_push()
    -- empty
end

function extendwifi_config_merge()
    local sync_uci = require("xiaoqiang.module.XQExWifiConfSyncUci")

    XQLog.log(debug_level, "enter extendwifi_config_merge")

    local res = sync_uci.config_merge()

    -- get local hotspot info for App show
    local ssid_24g, passwd_24g, ssid_5g, passwd_5g = sync_uci.hotspot_info()

    return res, ssid_24g, passwd_24g, ssid_5g, passwd_5g
end

-- wrapper, ensure that actions are consistent in both mode(active or passive)
function extendwifi_hotspot_shutdown()
    local util      = require("xiaoqiang.module.XQExtendWifi")
    local wifi_util = require("xiaoqiang.util.XQWifiUtil")

    XQLog.log(debug_level, "enter extendwifi_hotspot_shutdown")

    -- apcli0 apclii0
    local ifnames = wifi_util.apcli_get_ifnames()
    for _, ifname in ipairs(ifnames) do
        _apcli_shutdown(ifname)
    end

    -- wl0 wl1 wl3
    XQFunction.forkExec("(sleep 2; ifconfig wl0 down; ifconfig wl1 down; ifconfig wl3 down;)")

    -- ip addr
    if util.get_self_ifname() then
        XQFunction.forkExec("sleep 2; ip addr del 169.254.31.2/30 dev "..util.get_self_ifname())
        XQLog.log(debug_level, "enter extendwifi_hotspot_shutdown run cmd:ip addr del 169.254.31.2/30 dev "..util.get_self_ifname())
    else
        XQFunction.forkExec("sleep 2; ip addr del 169.254.31.1/30 dev br-lan")
        XQLog.log(debug_level, "enter extendwifi_hotspot_shutdown run cmd:ip addr del 169.254.31.1/30 dev br-lan")
    end

    return 0
end

-- wrapper, ensure that actions are consistent in both mode(active or passive)
function extendwifi_reboot()
    XQSysUtil = require("xiaoqiang.util.XQSysUtil")

    XQLog.log(debug_level, "enter extendwifi_reboot")

    XQSysUtil.setSPwd()

    local hardware = XQSysUtil.getHardware() --reference to XQSysUtil.setInited()
    if hardware then
        if hardware == "R1800" or hardware == "R4C" or hardware == "R3600" then
            XQFunction.forkExec("(sleep 1; /usr/sbin/set_wps_state 2;)")
        end
    end

    XQFunction.forkExec("(sleep 2; /usr/sbin/sysapi webinitrdr set off; reboot;)")

    return 0
end

local INIT_FUNC = {
    ["active"]  = _init_active,
    ["passive"] = _init_passive
}

local FINI_FUNC = {
    ["active"]  = _fini_active,
    ["passive"] = _fini_passive
}

-- Luci entry: App entry
function extendwifi_config_sync(mode, finish)
    local res, ssid_24g, passwd_24g, ssid_5g, passwd_5g
    local func

    XQLog.log(debug_level, "enter extendwifi_config_sync")

    -- param check
    if not mode then
        XQLog.log(debug_level, "invalid input parameter!")
        return ExWIFI_ERROR_CODE.ERROR_INVALID_MODE
    end

    if (mode == "1") then
        mode = "active"
    elseif (mode == "2") then
        mode = "passive"
    else
        XQLog.log(debug_level, "unknown work mode " .. mode)
        return ExWIFI_ERROR_CODE.ERROR_INVALID_MODE
    end

    -- get peer info
    local remote, token = _peer_info()
    if (not remote) or (not token) then
        XQLog.log(debug_level, "get peer info failed!")
        return ExWIFI_ERROR_CODE.ERROR_PEER_INFO
    end

    XQLog.log(debug_level, "peer info, remote: " .. remote .. " mode: " .. mode)

    if not finish then
        XQLog.log(debug_level, "config sync start!")
        func = INIT_FUNC[mode]
        if func then
            res, ssid_24g, passwd_24g, ssid_5g, passwd_5g = func(remote, token)
        end
        if not res then
            res = ExWIFI_ERROR_CODE.ERROR_INTERNAL
        end
        return res, ssid_24g, passwd_24g, ssid_5g, passwd_5g
    else
        XQLog.log(debug_level, "config sync finish!")
        func = FINI_FUNC[mode]
        if func then
            -- don't care the result
            func(remote, token)
        end
    end
end


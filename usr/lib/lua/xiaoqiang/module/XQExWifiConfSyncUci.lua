module ("xiaoqiang.module.XQExWifiConfSyncUci", package.seeall)

local XQLog            = require("xiaoqiang.XQLog")
local XQFunction 	   = require("xiaoqiang.common.XQFunction")
local uci_from         = require("luci.model.uci").cursor("/tmp/extendwifi/etc/config/")
local uci_to           = require("luci.model.uci").cursor()
local work_directory   = "/tmp/extendwifi/"
local rom_config_path  = "/etc/config/"
local wan_speed_compat = 0
local wifishare_used   = 1
local debug_level      = 6

local UCI = require("luci.model.uci").cursor()
local HARDWARE = UCI:get("misc", "hardware", "model") or ""
if HARDWARE then
    HARDWARE = string.lower(HARDWARE)
end

local function _is_table_empty(table)
    if (not table) or (next(table) == nil) then
        return nil
    end
    return 0
end

local function _is_wan_speed_compat()
    local wan_speed_misc_remote = uci_from:get("misc", "hardware", "wanspeed")
    local wan_speed_misc_local  = uci_to:get("misc", "hardware", "wanspeed")

    if not wan_speed_misc_remote then
        wan_speed_misc_remote = "100"
    end

    if not wan_speed_misc_local then
        wan_speed_misc_local = "100"
    end

    if (wan_speed_misc_remote == wan_speed_misc_local) then
        return 1
    end

    return 0
end

local function _is_wifishare_used()
    local wifishare_disabled = uci_from:get("wifishare", "global", "disabled")

    if wifishare_disabled and (wifishare_disabled == "0") then
        return 1
    end

    return 0
end

-- "myrouter"      ->  "myrouter(1)"
-- "myrouter(6)"   ->  "myrouter(7)"
-- "myrouter(xyz)" ->  "myrouter(xyz)(1)"
local function _router_name_repl(name)
    local regexp = "%((%d+)%)$"

    if not name then
        return "(1)"
    end

    local s, e, sub = string.find(name, regexp)
    if not s or not e or not sub then
        return name .. "(1)"
    end

    local num = tonumber(sub)
    num = num + 1
    return string.gsub(name, regexp, "(" .. num .. ")")
end

local function _merge_finish()
    XQLog.log(debug_level, "merge finish")

    uci_to:commit("account")
    uci_to:commit("xiaoqiang")
    uci_to:commit("network")
    uci_to:commit("dhcp")
    uci_to:commit("firewall")
    --uci_to:commit("hwnat")
    --uci_to:commit("wifishare")
    uci_to:commit("macfilter")
    uci_to:commit("system")

    os.execute("nvram commit")
end

-- /etc/config/xiaoqiang & initialize
local function _xiaoqiang_config()
    XQLog.log(debug_level, "xiaoqiang config")

    local name       = uci_from:get("xiaoqiang", "common", "ROUTER_NAME")
    local pending    = uci_from:get("xiaoqiang", "common", "ROUTER_NAME_PENDING")
    local locale     = uci_from:get("xiaoqiang", "common", "ROUTER_LOCALE")
    --local initted    = uci_from:get("xiaoqiang", "common", "INITTED")
    local privacy    = uci_from:get("xiaoqiang", "common", "PRIVACY")
    local netmode    = uci_from:get("xiaoqiang", "common", "NETMODE")
    local bandwidth  = uci_from:get("xiaoqiang", "common", "BANDWIDTH")
    local bandwidth2 = uci_from:get("xiaoqiang", "common", "BANDWIDTH2")
    local manual     = uci_from:get("xiaoqiang", "common", "MANUAL")
    local password   = XQFunction._strformat(uci_from:get("account",   "common", "admin"))

    local new_name = _router_name_repl(name)
    if not new_name then
        new_name = name
    end
    if new_name then
        uci_to:set("xiaoqiang", "common", "ROUTER_NAME", new_name)
    end
    if pending then
        uci_to:set("xiaoqiang", "common", "ROUTER_NAME_PENDING", pending)
    end
    if locale then
        uci_to:set("xiaoqiang", "common", "ROUTER_LOCALE", locale)
    end
    --uci_to:set("xiaoqiang", "common", "INITTED", initted)
    if privacy then
        uci_to:set("xiaoqiang", "common", "PRIVACY", privacy)
    end
    if netmode then
        uci_to:set("xiaoqiang", "common", "NETMODE", netmode)
    end
    if (wan_speed_compat == 1) then
        if bandwidth then
            uci_to:set("xiaoqiang", "common", "BANDWIDTH", bandwidth)
        end
        if bandwidth2 then
            uci_to:set("xiaoqiang", "common", "BANDWIDTH2", bandwidth2)
        end
        if manual then
            uci_to:set("xiaoqiang", "common", "MANUAL", manual)
        end
    end
    uci_to:set("account",   "common", "admin", password)

    --uci_to:commit("xiaoqiang")
    --uci_to:commit("account")

    os.execute("nvram set Router_unconfigured=0 > /dev/null 2>&1")
    XQFunction.execute_safe("nvram set nv_sys_pwd='" .. password .. "'> /dev/null 2>&1")
    --os.execute("nvram commit")
end

local function _network_lan_config()
    XQLog.log(debug_level, "network lan config")

    local lan_proto  = uci_from:get("network", "lan", "proto")
    local lan_ipaddr = uci_from:get("network", "lan", "ipaddr")
    local lan_mask   = uci_from:get("network", "lan", "netmask")

    uci_to:set("network", "lan", "proto",   lan_proto)
    uci_to:set("network", "lan", "ipaddr",  lan_ipaddr)
    uci_to:set("network", "lan", "netmask", lan_mask)

    --uci_to:commit("network")
end

local function _network_wan_config()
    XQLog.log(debug_level, "network wan config")

    local wan_proto    = XQFunction._strformat(uci_from:get("network", "wan", "proto"))
	local wan_mtu 
    -- pppoe
	if wan_proto == "pppoe" then
        wan_mtu = uci_from:get("network", "wan", "mru")
	else
		wan_mtu = uci_from:get("network", "wan", "mtu")
	end
    local wan_special  = uci_from:get("network", "wan", "special")
    local wan_service  = uci_from:get("network", "wan", "service")
    local wan_username = uci_from:get("network", "wan", "username")
    local wan_password = uci_from:get("network", "wan", "password")
    -- set wan(上网设置)
    local wan_dns      = uci_from:get_list("network", "wan", "dns")
    local wan_peerdns  = uci_from:get("network", "wan", "peerdns")
    -- set wan(上网设置: static ip)
    local wan_ipaddr   = XQFunction._strformat(uci_from:get("network", "wan", "ipaddr"))
    local wan_netmask  = XQFunction._strformat(uci_from:get("network", "wan", "netmask"))
    local wan_gateway  = XQFunction._strformat(uci_from:get("network", "wan", "gateway"))
    -- mac address clone
    local wan_macaddr  = uci_from:get("network", "wan", "macaddr")
    --
    local wan_speed    = XQFunction._strformat(uci_from:get("xiaoqiang", "common", "WAN_SPEED"))

    uci_to:set("network", "wan",   "proto",   wan_proto)
    if _is_table_empty(wan_dns) ~= nil then
        uci_to:set_list("network", "wan", "dns", wan_dns)
        local index = 1
        --for i in string.gmatch(wan_dns, "%S+") do
        for _, dns in pairs(wan_dns) do
            local dns = XQFunction._strformat(dns)
            XQFunction.execute_safe("nvram set nv_wan_dns" .. index .. "='" .. dns .. "'> /dev/null 2>&1")
            index = index + 1
        end
    end
    if wan_peerdns then
        uci_to:set("network", "wan", "peerdns", wan_peerdns)
    end
    if wan_ipaddr then
        uci_to:set("network", "wan", "ipaddr", wan_ipaddr)
        XQFunction.execute_safe("nvram set nv_wan_ip='" .. wan_ipaddr .. "'> /dev/null 2>&1")
    end
    if wan_netmask then
        uci_to:set("network", "wan", "netmask", wan_netmask)
        XQFunction.execute_safe("nvram set nv_wan_netmask='" .. wan_netmask .. "'> /dev/null 2>&1")
    end
    if wan_gateway then
        uci_to:set("network", "wan", "gateway", wan_gateway)
        XQFunction.execute_safe("nvram set nv_wan_gateway='" .. wan_gateway .. "'> /dev/null 2>&1")
    end
    if wan_mtu then
		if wan_proto == "pppoe" then
			uci_to:set("network", "wan", "mru", wan_mtu)
		else
        uci_to:set("network", "wan", "mtu", wan_mtu)
    end
    end
    if wan_special then
        uci_to:set("network", "wan", "special", wan_special)
    end
    if wan_service then
        uci_to:set("network", "wan", "service", wan_service)
    end
    if wan_username then
        uci_to:set("network", "wan", "username", wan_username)
    end
    if wan_password then
        uci_to:set("network", "wan", "password", wan_password)
    end
    if wan_macaddr then
        uci_to:set("network", "wan", "macaddr", wan_macaddr)
    end
    if wan_speed and (wan_speed ~= 0) then
        local wan_speed_misc = uci_to:get("misc", "hardware", "wanspeed")
        if not wan_speed_misc then
            wan_speed_misc = "100"
        end
        if (wan_speed == "10") and (wan_speed_misc == "1000") then
            --use default
        elseif (wan_speed == "1000") and (wan_speed_misc == "100") then
            --use default
        else
            uci_to:set("xiaoqiang", "common", "WAN_SPEED", wan_speed)
            XQFunction.execute_safe("phyhelper swan '" .. wan_speed .. "'> /dev/null 2>&1")
        end
    end

    --uci_to:commit("network")
    --uci_to:commit("xiaoqiang")

    XQFunction.execute_safe("nvram set nv_wan_type='" .. wan_proto .. "'> /dev/null 2>&1")
    --os.execute("nvram commit")
end

local function _network_config()
    XQLog.log(debug_level, "network config")

    _network_lan_config()
    _network_wan_config()
end

local function _dhcp_config()
    XQLog.log(debug_level, "dhcp config")

    --dhcp config also existed under lanap/wifiap mode (although maybe no use)
    local dhcp_start  = uci_from:get("dhcp", "lan", "start")
    local dhcp_limit  = uci_from:get("dhcp", "lan", "limit")
    local dhcp_lease  = uci_from:get("dhcp", "lan", "leasetime")
    local dhcp_ignore = uci_from:get("dhcp", "lan", "ignore")

    uci_to:set("dhcp", "lan", "start",     dhcp_start)
    uci_to:set("dhcp", "lan", "limit",     dhcp_limit)
    uci_to:set("dhcp", "lan", "leasetime", dhcp_lease)
    if dhcp_ignore then
        uci_to:set("dhcp", "lan", "ignore", dhcp_ignore)
    end

    --uci_to:commit("dhcp")
end

local function _network_guest_config()
    XQLog.log(debug_level, "network guest config")

    local network_guest = uci_from:get_all("network", "guest")

    if _is_table_empty(network_guest) ~= nil then
        uci_to:section("network", "interface", "guest", network_guest)
    end

    --uci_to:commit("network")
end

local function _dhcp_guest_config()
    XQLog.log(debug_level, "dhcp guest config")

    local dhcp_guest = uci_from:get_all("dhcp", "guest")

    if _is_table_empty(dhcp_guest) ~= nil then
        uci_to:section("dhcp", "dhcp", "guest", dhcp_guest)
    end
end

local function _firewall_guest_config()
    XQLog.log(debug_level, "firewall guest config")

    local guest_forward = uci_from:get_all("firewall", "guest_forward")
    local guest_zone    = uci_from:get_all("firewall", "guest_zone")
    local guest_dns     = uci_from:get_all("firewall", "guest_dns")
    local guest_dhcp    = uci_from:get_all("firewall", "guest_dhcp")
    --local wifishare     = uci_from:get_all("firewall", "wifishare")

    if _is_table_empty(guest_forward) ~= nil then
        uci_to:section("firewall", "forwarding", "guest_forward", guest_forward)
    end

    if _is_table_empty(guest_zone) ~= nil then
        uci_to:section("firewall", "zone", "guest_zone", guest_zone)
    end

    if _is_table_empty(guest_dns) ~= nil then
        uci_to:section("firewall", "rule", "guest_dns", guest_dns)
    end

    if _is_table_empty(guest_dhcp) ~= nil then
        uci_to:section("firewall", "rule", "guest_dhcp", guest_dhcp)
    end

    --if _is_table_empty(wifishare) ~= nil then
    --    uci_to:section("firewall", "include", "wifishare", wifishare)
    --end
end

local function _wifishare_config()
    XQLog.log(debug_level, "wifishare config")

    -- hwnat switch
    local hwnat_switch = uci_from:get("hwnat", "switch", "wifishare")
    local hwnat        = uci_to:get_all("hwnat", "switch")

    if (_is_table_empty(hwnat) ~= nil) then
        if hwnat_switch then
            uci_to:set("hwnat", "switch", "wifishare", hwnat_switch)
        else
            uci_to:set("hwnat", "switch", "wifishare", "0")
        end
    end

    -- wifishare
    local wifishare = uci_from:get_all("wifishare", "global")
    if _is_table_empty(wifishare) ~= nil then
        uci_to:delete_all("wifishare", "global")
        uci_to:section("wifishare", "global", "global", wifishare)
    end
end

local function _guest_config()
    XQLog.log(debug_level, "guest config")

    if (wifishare_used == 1) then
        XQLog.log(debug_level, "wifishare used, dont't do guest config!")
        return
    end

    _network_guest_config()
    _dhcp_guest_config()
    _firewall_guest_config()
    --_wifishare_config()
end

local function _macfilter_config()
    XQLog.log(debug_level, "macfilter config")

    local mode_admin = uci_from:get("macfilter", "mode", "admin")
    if (mode_admin ~= "whitelist") then
        -- macfilter maybe not used, do nothing
        return
    end
    uci_to:set("macfilter", "mode", "admin", mode_admin)

    uci_from:foreach(
        "macfilter", "mac",
        function(s)
            uci_to:section("macfilter", "mac", nil, s)
        end
    )

    --uci_to:commit("macfilter")
end

local function _timezone_config()
    XQLog.log(debug_level, "timezone config")

    local timezone, timezone_index
    uci_from:foreach(
        "system", "system",
        function(s)
            timezone       = s['timezone']
            timezone_index = s['timezoneindex']
        end
    )
    uci_to:foreach(
        "system", "system",
        function(s)
            if timezone then
                uci_to:set("system", s['.name'], "timezone", timezone)
            end
            if timezone_index then
                uci_to:set("system", s['.name'], "timezoneindex", timezone_index)
            end
        end
    )

    --uci_to:commit("system")
end

local function _qos_config()
    XQLog.log(debug_level, "qos config")

    if (wan_speed_compat ~= 1) then
        XQLog.log(debug_level, "wan speed not compat, don't do qos config!")
        return
    end

    local qos_file         = work_directory .. rom_config_path .. "miqos"
    local qos_default_file = work_directory .. rom_config_path .. "miqos_default"

    os.execute("cp -f " .. qos_file .. " " .. rom_config_path ..  " >/dev/null 2>&1")
    os.execute("cp -f " .. qos_default_file .. " " .. rom_config_path ..  " >/dev/null 2>&1")
end

local function _wireless_guest_disable()
    XQLog.log(debug_level, "wireless guest disable")

    local guest_2g_name = uci_to:get("misc", "wireless", "iface_guest_2g_name")

    if not guest_2g_name then
        guest_2g_name = "guest_2G"
    end

    local wireless_guest_2G = uci_to:get_all("wireless", guest_2g_name)
    if _is_table_empty(wireless_guest_2G) ~= nil then
        uci_to:delete("wireless", guest_2g_name)
        uci_to:commit("wireless")
    end
end

function config_merge()
    local wifiutil = require("xiaoqiang.util.XQWifiUtil")

    wan_speed_compat = _is_wan_speed_compat()
    wifishare_used   = _is_wifishare_used()

    _xiaoqiang_config()
    _network_config()
    _dhcp_config()
    if HARDWARE:match("^r3600") then
    else
        _guest_config()
    end
    _macfilter_config()
    _timezone_config()
    _qos_config()
    wifiutil.extendwifi_tranlate_wireless_config()
    if HARDWARE:match("^r3600") then
    else
        if (wifishare_used == 1) then --ugly job, but have to do
            _wireless_guest_disable()
        end
    end
    _merge_finish()

    return 0
end

function hotspot_info()
    local ssid_24g, passwd_24g, ssid_5g, passwd_5g

    XQLog.log(debug_level, "get hotspot info")

    local ifname_24g = uci_to:get("misc", "wireless", "ifname_2G")
    local ifname_5g  = uci_to:get("misc", "wireless", "ifname_5G")

    uci_to:foreach(
        "wireless", "wifi-iface",
        function(s)
            if (s['ifname'] == ifname_24g) then
                ssid_24g   = s['ssid']
                passwd_24g = s['key']
            end
            if (s['ifname'] == ifname_5g) then
                ssid_5g   = s['ssid']
                passwd_5g = s['key']
            end
        end
    )

    if ssid_24g then
        XQLog.log(debug_level, "ssid_24g: " .. ssid_24g)
    end
    if passwd_24g then
        XQLog.log(debug_level, "passwd_24g: " .. passwd_24g)
    end
    if ssid_5g then
        XQLog.log(debug_level, "ssid_5g: " .. ssid_5g)
    end
    if passwd_5g then
        XQLog.log(debug_level, "passwd_5g: " .. passwd_5g)
    end

    return ssid_24g, passwd_24g, ssid_5g, passwd_5g
end

function hardware_info()
    local hardware = uci_to:get("misc", "hardware", "model")

    if hardware then
        hardware = string.lower(hardware)
        return hardware
    end
    return nil
end


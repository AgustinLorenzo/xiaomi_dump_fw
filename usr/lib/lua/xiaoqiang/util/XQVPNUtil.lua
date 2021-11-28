module ("xiaoqiang.util.XQVPNUtil", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local XQConfigs = require("xiaoqiang.common.XQConfigs")
local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")

local Network = require("luci.model.network")
local Firewall = require("luci.model.firewall")
local uci = require("luci.model.uci").cursor()

-- @param proto pptp/l2tp
-- @param auto  0/1
function setVpn(interface, server, username, password, proto, id, auto)
    if XQFunction.isStrNil(interface) or XQFunction.isStrNil(server) or XQFunction.isStrNil(username) or XQFunction.isStrNil(password) or XQFunction.isStrNil(proto) or XQFunction.isStrNil(auto) then
        return false
    end
    local vpnid = id
    if XQFunction.isStrNil(vpnid) then
        vpnid = XQCryptoUtil.md5Str(server .. username .. proto)
    end

	local uci = require("luci.model.uci").cursor()
	local trafficall = uci:get("network", "vpn", "trafficall")
	if trafficall and string.lower(trafficall) == "yes" then
		trafficall = 'yes'
	else
		trafficall = 'no'
	end
	
    local protocal = string.lower(proto)
    local network = Network.init()
    network:del_network(interface .. '6')
    network:del_network(interface)

    local vpnNetwork = network:add_network(interface, {
        proto = protocal,
        server = server,
        username = username,
        password = password,
        auth = 'auto',
        id = vpnid,
        auto = auto,
		trafficall = trafficall
    })
    -- add ipv6 support
    -- local ipv6flag= uci:get("ipv6", "settings", "enabled")
    local ipv6flag= '0'
    local vpn6Network= false
    if ipv6flag == '1' then
        vpn6Network = network:add_network(interface .. '6', {
            proto = 'dhcpv6',
            ifname='@' .. interface
        })
    else
        vpn6Network = true
    end

    if vpnNetwork and vpn6Network then
        network:save("network")
        network:commit("network")
        local firewall = Firewall.init()
        local zoneWan = firewall:get_zone("wan")
        zoneWan:add_network(interface)
        firewall:save("firewall")
        firewall:commit("firewall")
		
		-- restart nss for r3600
		local HARDWARE = uci:get("misc", "hardware", "model") or ""
		if HARDWARE then
			HARDWARE = string.lower(HARDWARE)
		end
		if HARDWARE:match("^r3600") then
			os.execute("/etc/init.d/qca-nss-ecm restart")
		end	
        return true
    end
    return false
end

-- del vpn config in /etc/config/network
function _delNetworkVpn(id)
    local oldVpn = getVPNInfo("vpn")
    local oldId = oldVpn["id"]
	
    if oldId == id then
        local network = Network.init()
        network:del_network("vpn6")
        network:del_network("vpn")
        network:save("network")
        network:commit("network")
		
		-- restart nss for r3600
		local HARDWARE = uci:get("misc", "hardware", "model") or ""
		if HARDWARE then
			HARDWARE = string.lower(HARDWARE)
		end	
		if HARDWARE:match("^r3600") then
			os.execute("/etc/init.d/qca-nss-ecm restart")
		end	
    end
end

-- edit vpn config in /etc/config/network
function _editNetworkVpn(server, username, password, proto, id)
    local oldVpn = getVPNInfo("vpn")
    local oldId = oldVpn["id"]
    if oldId == id then
        local interface = "vpn"
        local protocal = string.lower(proto)
        local newId = XQCryptoUtil.md5Str(server .. username .. proto)
        uci:set("network", interface, "proto", protocal)
        uci:set("network", interface, "server", server)
        uci:set("network", interface, "username", username)
        uci:set("network", interface, "password", password)
        uci:set("network", interface, "id", newId)
        uci:commit("network")
    end
end

-- set vpn auto start in /etc/config/network
function setVpnAuto(auto)
    auto = tonumber(auto)
    local interface = "vpn"
    local autoinit = (auto and auto == 0) and "0" or "1"
    uci:set("network", interface, "auto", autoinit)
    uci:commit("network")
    return true
end

-- get vpn info in /etc/config/network
function getVPNInfo(interface)
    local network = Network.init()
    local info = {
        proto = "",
        server = "",
        username = "",
        password = "",
        auto = "0",
        id = ""
    }
    if XQFunction.isStrNil(interface) then
        return info
    end
    local vpn = network:get_network(interface)
    if vpn then
        info.proto = vpn:get_option_value("proto")
        info.server = vpn:get_option_value("server")
        info.username = vpn:get_option_value("username")
        info.password = vpn:get_option_value("password")
        info.auto = vpn:get_option_value("auto")
        info.id = vpn:get_option_value("id")
    end
    return info
end

-- enabled a vpn config
function vpnSwitch(enable, id)
	local XQFunction = require("xiaoqiang.common.XQFunction")
    if XQFunction.isStrNil(id) then
        return false
    end
    if enable then
        local oldVpn = getVPNInfo("vpn")
        local oldId = oldVpn["id"]
        local autoinit = oldVpn["auto"]
        if XQFunction.isStrNil(autoinit) then
            autoinit = "0"
        end
        if oldId ~= id then
            local options = uci:get_all("vpnlist", id)
            if options then
                setVpn("vpn", options.server, options.username, options.password, options.proto, id, autoinit)
            end
        end
        os.execute(XQConfigs.RM_VPNSTATUS_FILE)
        os.execute(XQConfigs.VPN_DISABLE)
		XQFunction.forkExec(XQConfigs.VPN_ENABLE)
		return 1
    else
        os.execute(XQConfigs.RM_VPNSTATUS_FILE)
		XQFunction.forkExec(XQConfigs.VPN_DISABLE)
        return 1
    end
end

-- get vpn status
function vpnStatus()
    local LuciUtil = require("luci.util")
    local status = LuciUtil.exec(XQConfigs.VPN_STATUS)
    if not XQFunction.isStrNil(status) then
        status = LuciUtil.trim(status)
        if XQFunction.isStrNil(status) then
            return nil
        end
        local json = require("json")
        status = json.decode(status)
        if status then
            return status
        end
    end
    return nil
end

-- add vpn item in /etc/config/vpnlist
function addVPN(oname, server, username, password, proto)
    if XQFunction.isStrNil(oname) or XQFunction.isStrNil(server) or XQFunction.isStrNil(username) or XQFunction.isStrNil(password) or XQFunction.isStrNil(proto) then
        return false
    end
    local id = XQCryptoUtil.md5Str(server .. username .. proto)
    local protocal = string.lower(proto)
    local options = {
        ["oname"] = oname,
        ["server"] = server,
        ["username"] = username,
        ["password"] = password,
        ["proto"] = protocal,
        ["id"] = id
    }
    uci:section("vpnlist", "vpn", id, options)
    uci:commit("vpnlist")
    return true
end

-- edit a vpn config in /etc/config/vpnlist and /etc/config/network
function editVPN(oldId, oname, server, username, password, proto)
    if XQFunction.isStrNil(oldId) then
        return false
    end
    uci:delete("vpnlist", oldId)
    _editNetworkVpn(server, username, password, proto, oldId)
    return addVPN(oname, server, username, password, proto)
end

-- del a vpn config in /etc/config/vpnlist and /etc/config/network
function delVPN(id)
    if XQFunction.isStrNil(id) then
        return false
    end
    uci:delete("vpnlist", id)
    uci:commit("vpnlist")
    _delNetworkVpn(id)
    return true
end

-- get vpnlist in /etc/config/vpnlist
function getVPNList()
    local result = {}
    uci:foreach("vpnlist", "vpn",
        function(s)
            local item = {
                ["oname"] = s.oname,
                ["server"] = s.server,
                ["username"] = s.username,
                ["password"] = s.password,
                ["proto"] = s.proto,
                ["id"] = s.id
            }
            table.insert(result, item)
            -- result[s.id] = item
        end
    )
    return result
end

--
-- smart VPN
--
-- local DEFAULT_URL = {
--     ".youtube.com",
--     ".facebook.com",
--     ".twitter.com",
--     ".instagram.com"
-- }
local DEFAULT_PROXY_FILE = "/etc/smartvpn/proxy.txt"

function getProxyList()
    local fs = require("nixio.fs")
    local datatypes = require("luci.cbi.datatypes")
    local info = {}
    if fs.access(DEFAULT_PROXY_FILE) then
        local proxy = io.open(DEFAULT_PROXY_FILE, "r")
        if proxy then
            for line in proxy:lines() do
                if not XQFunction.isStrNil(line) then
                    if line:match("^%.") then
                        line = line:gsub("^%.", "")
                        table.insert(info, line)
                    else
                        if datatypes.ipaddr(line) then
                            table.insert(info, line)
                        end
                    end
                end
            end
        end
    end
    if #info > 0 then
        return info
    else
        return nil
    end
end

function updateProxyList(data)
    if data and type(data) == "string" and data == "default" then
        data = nil
    end
    if data and type(data) == "table" then
        local f = io.open(DEFAULT_PROXY_FILE, "w")
        for _, line in ipairs(data) do
            if not XQFunction.isStrNil(line) then
                f:write(line.."\n")
            end
        end
        f:close()
    end
end

function getDeviceList()
    local uci = require("luci.model.uci").cursor()
    local info = {}
    local device = uci:get_all("smartvpn", "device")
    if device then
        info = uci:get_list("smartvpn", "device", "mac")
    else
        info = nil
    end
    return info
end

-- status: 0/1 off/on
-- mode: 0/1/2 未设置/域名/mac地址
function getSmartVPNInfo()
    local uci = require("luci.model.uci").cursor()
    local info = {
        ["status"] = 0,
        ["switch"] = 0,
        ["mode"] = 1
    }
    local vpn = uci:get_all("smartvpn", "vpn")
    local device = uci:get_all("smartvpn", "device")
    if vpn then
        if vpn.status == "on" then
            info.status = 1
        elseif vpn.status == "off" then
            info.status = 0
        end
        if vpn.switch and tonumber(vpn.switch) == 1 then
            info.switch = 1
        end
        if device and device.disabled and tonumber(device.disabled) == 0 then
            info.mode = 2
        elseif vpn.disabled and tonumber(vpn.disabled) == 0 then
            info.mode = 1
        else
            info.mode = 0
        end
    end
    return info
end

-- enable:0/1 off/on
-- mode:1/2 域名/mac地址
function setSmartVPN(enable, mode)
    local fs = require("nixio.fs")
    local uci = require("luci.model.uci").cursor()
    if mode then
        if mode == 1 then
            if not fs.access(DEFAULT_PROXY_FILE) and enable == 1 then
                updateProxyList("default")
            end
            uci:set("smartvpn", "vpn", "disabled", "0")
            uci:set_list("smartvpn", "vpn", "domain_file", {DEFAULT_PROXY_FILE})
            if uci:get_all("smartvpn", "device") then
                uci:set("smartvpn", "device", "disabled", "1")
            end
        elseif mode == 2 then
            uci:set("smartvpn", "vpn", "disabled", "1")
            if uci:get_all("smartvpn", "device") then
                uci:set("smartvpn", "device", "disabled", "0")
            else
                uci:section("smartvpn", "record", "device", {["disabled"] = "0"})
            end
        end
    end
    if enable then
        if enable == 0 then
            uci:set("smartvpn", "vpn", "switch", "0")
            uci:set("smartvpn", "vpn", "disabled", "1")
            uci:set("smartvpn", "device", "disabled", "1")
        elseif enable == 1 then
            uci:set("smartvpn", "vpn", "switch", "1")
        end
    end
    uci:commit("smartvpn")
    if enable then
        os.execute("/usr/sbin/smartvpn.sh flush >/dev/null 2>/dev/null")
        local trafficall = uci:get("network", "vpn", "trafficall")
        if enable == 1 and trafficall and string.lower(trafficall) == "yes" then
            mivpnSwitch(false)
        end
    end
end

-- enable:0/1 off/on
function setMiVPN(enable)
	if enable then
		if enable == 0 then
			os.execute("/usr/sbin/mivpn.sh off >/dev/null 2>/dev/null")
		end
	end	
end

-- t1: table
-- t2: table
-- opt: +/- (t1 + t2)/(t1 - t2)
function merge(t1, t2, opt)
    if not t1 and not t2 then
        return nil
    end
    if opt == "+" then
        if t1 then
            if not t2 then
                return t1
            end
            local d = {}
            for _, v in ipairs(t1) do
                d[v] = true
            end
            for _, v in ipairs(t2) do
                if not d[v] then
                    table.insert(t1, v)
                end
            end
            return t1
        else
            if not t2 then
                return nil
            else
                return t2
            end
        end
    elseif opt == "-" then
        if t1 then
            if not t2 then
                return t1
            end
            local s = {}
            local d = {}
            for _, v in ipairs(t2) do
                d[v] = true
            end
            for _, v in ipairs(t1) do
                if not d[v] then
                    table.insert(s, v)
                end
            end
            return s
        end
    end
    return nil
end

function urlFormat(url)
    local datatypes = require("luci.cbi.datatypes")
    if url then
        url = url:gsub("http://", "")
        url = url:gsub("^www", "")
        if not datatypes.ipaddr(url) then
            if not url:match("^%.") then
                url = "."..url
            end
        end
        return url
    end
    return nil
end

-- opt: 0/1 增加/删除
function editUrl(opt, urls)
    if not urls or type(urls) ~= "table" then
        return false
    end
    for i, url in ipairs(urls) do
        if XQFunction.isStrNil(url) then
            return false
        else
            urls[i] = urlFormat(url)
        end
    end
    local ulist = getProxyList()
    if ulist then
        for i, url in ipairs(ulist) do
            if not XQFunction.isStrNil(url) then
                ulist[i] = urlFormat(url)
            end
        end
        if opt == 0 then
            ulist = merge(ulist, urls, "+")
        elseif opt == 1 then
            ulist = merge(ulist, urls, "-")
        end
        updateProxyList(ulist)
    else
        if opt == 0 then
            updateProxyList(urls)
        end
    end
    return true
end

-- opt: 0/1 增加/删除
function editMac(opt, macs)
    local datatypes  = require("luci.cbi.datatypes")
    if not macs or type(macs) ~= "table" then
        return false
    end
    for i, mac in ipairs(macs) do
        if XQFunction.isStrNil(mac) or not datatypes.macaddr(mac) then
            return false
        else
            macs[i] = XQFunction.macFormat(mac)
        end
    end
    local uci = require("luci.model.uci").cursor()
    local device = uci:get_all("smartvpn", "device")
    if device then
        if device.mac and type(device.mac) == "table" then
            if opt == 0 then
                device.mac = merge(device.mac, macs, "+")
            elseif opt == 1 then
                device.mac = merge(device.mac, macs, "-")
            end
        else
            if opt == 0 then
                device["mac"] = macs
            end
        end
        if #device.mac > 0 then
            uci:section("smartvpn", "record", "device", device)
        else
            uci:delete("smartvpn", "device", "mac")
        end
    else
        if opt == 0 then
            uci:section("smartvpn", "record", "device", {["disabled"] = 0, ["mac"] = macs})
        end
    end
    uci:commit("smartvpn")
    return true
end

function mivpnInfo()
    local uci = require("luci.model.uci").cursor()
    local tra = uci:get("network", "vpn", "trafficall")
    if tra and string.lower(tra) == "yes" then
        return 1
    else
        return 0
    end
end

function mivpnSwitch(open)
    local uci = require("luci.model.uci").cursor()
    local vpn = uci:get_all("network", "vpn")
    local switch = uci:get("smartvpn", "vpn", "switch")
    if open and switch and tonumber(switch) == 1 then
        setSmartVPN(0, 1)
    end

    if vpn then
        uci:set("network", "vpn", "trafficall", open and "yes" or "no")
        uci:commit("network")
		
		if not open then 
			setMiVPN(0)
		end
		
        return true
    else
        return false
    end
end

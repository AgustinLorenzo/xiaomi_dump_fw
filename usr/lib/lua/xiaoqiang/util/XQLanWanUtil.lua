module ("xiaoqiang.util.XQLanWanUtil", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local XQConfigs = require("xiaoqiang.common.XQConfigs")

function getDefaultMacAddress()
    local LuciUtil = require("luci.util")
    local mac = LuciUtil.exec(XQConfigs.GET_DEFAULT_MACADDRESS)
    if XQFunction.isStrNil(mac) then
        mac = nil
        return 'null'
    else
        mac = LuciUtil.trim(mac):match("(%S-),")
        return string.upper(mac)
    end
end

function getDefaultWanMacAddress()
    local LuciUtil = require("luci.util")
    local mac = LuciUtil.exec(XQConfigs.GET_DEFAULT_WAN_MACADDRESS)
    if XQFunction.isStrNil(mac) then
        mac = nil
        return 'null'
    else
        mac = LuciUtil.trim(mac)
        return string.upper(mac)
    end
end

function getLanLinkList()
    local LuciUtil = require("luci.util")
    local uci = require("luci.model.uci").cursor()
    local lports = uci:get("misc", "sw_reg", "sw_lan_ports") 
    local lanLink = {}
    local cmd = "/sbin/ethstatus"
    for i, line in ipairs(LuciUtil.execl(cmd)) do
        local port,link = line:match('port (%d):(%S+)')
        if link then
			if string.match(lports, port) ~= nil then
				lanLink[i] = link == 'up' and 1 or 0
			end
        end
    end
    return lanLink
end

function getWanLink()
    local LuciUtil = require("luci.util")
    local uci = require("luci.model.uci").cursor()
    local wport = uci:get("misc", "sw_reg", "sw_wan_port") or 4
    local cmd = "/sbin/ethstatus"
    for _, line in ipairs(LuciUtil.execl(cmd)) do
        local port,link = line:match('port (%d):(%S+)')
        if link and link == 'up' and tonumber(port) == tonumber(wport) then
            return true
        end
    end
    return false
end

function getLanIp()
    local uci = require("luci.model.uci").cursor()
    local lan = uci:get_all("network", "lan")
    return lan.ipaddr
end

--[[
@return WANLINKSTAT=UP/DOWN
@return LOCALDNSSTAT=UP/DOWN
@return VPNLINKSTAT=UP/DOWN
]]--
function getWanMonitorStat()
    local NixioFs = require("nixio.fs")
    local content = NixioFs.readfile(XQConfigs.WAN_MONITOR_STAT_FILEPATH)
    local status = {}
    if content ~= nil then
        for line in string.gmatch(content, "[^\n]+") do
            key,value = line:match('(%S+)=(%S+)')
            status[key] = value
        end
    end
    return status
end

function getAutoWanType()
    --local XQLog = require("xiaoqiang.XQLog")
    local LuciUtil = require("luci.util")
    local uci = require("luci.model.uci").cursor()
    local HARDWARE = uci:get("misc", "hardware", "model") or ""
    if HARDWARE then
        HARDWARE = string.lower(HARDWARE)
    end
    local INIT_FLAG = uci:get("xiaoqiang", "common", "INITTED") or ""

    --XQLog.log(6,"HARDWARE " .. HARDWARE)
    if HARDWARE:match("^d01") and INIT_FLAG ~= "YES" then
        local result = LuciUtil.execi("/usr/sbin/autowancheck 6")
        local link,pppoe,dhcp
        if result then
            for line in result do
                if line:match("^LINK=(%S+)") ~= nil then
                    link = line:match("^LINK=(%S+)")
                elseif line:match("^PPPOE=(%S+)") ~= nil then
                    pppoe = line:match("^PPPOE=(%S+)")
                elseif line:match("^DHCP=(%S+)") ~= nil then
                    dhcp = line:match("^DHCP=(%S+)")
                end
            end
        end
        if pppoe == "YES" then
            return 1
        elseif dhcp == "YES" then
            return 2
        elseif link ~= "YES" then
            return 99
        else
            return 0
        end
    else
        local result = LuciUtil.execi("/usr/sbin/wanlinkprobe 4 WAN pppoe dhcp")
        local link,pppoe,dhcp
        if result then
            for line in result do
                if line:match("^LINK=(%S+)") ~= nil then
                    link = line:match("^LINK=(%S+)")
                elseif line:match("^PPPOE=(%S+)") ~= nil then
                    pppoe = line:match("^PPPOE=(%S+)")
                elseif line:match("^DHCP=(%S+)") ~= nil then
                    dhcp = line:match("^DHCP=(%S+)")
                end
            end
        end
        if pppoe == "YES" then
            return 1
        elseif dhcp == "YES" then
            return 2
        elseif link ~= "YES" then
            return 99
        else
            return 0
        end
    end
end

function ubusWanStatus()
    local ubus = require("ubus").connect()
    local wan = ubus:call("network.interface.wan", "status", {})
    local result = {}
    if wan["ipv4-address"] and #wan["ipv4-address"] > 0 then
        result["ipv4"] = wan["ipv4-address"][1]
    else
        result["ipv4"] = {
            ["mask"] = 0,
            ["address"] = ""
        }
    end
    result["dns"] = wan["dns-server"] or {}
    result["proto"] = string.lower(wan.proto or "dhcp")
    result["up"] = wan.up
    result["uptime"] = wan.uptime or 0
    result["pending"] = wan.pending
    result["autostart"] = wan.autostart
    return result
end

function _pppoeStatusCheck()
    local LuciJson = require("json")
    local LuciUtil = require("luci.util")
    local cmd = "lua /usr/sbin/pppoe.lua status"
    local status = LuciUtil.exec(cmd)
    if status then
        status = LuciUtil.trim(status)
        if XQFunction.isStrNil(status) then
            return false
        end
        status = LuciJson.decode(status)
        return status
    else
        return false
    end
end

--- type
--- 1:认证失败（用户密码异常导致）
--- 2:无法连接服务器
--- 3:其他异常（协议不匹配等）
function _pppoeErrorCodeHelper(code)
    local errorA = {
        ["507"] = 1,["691"] = 1,["509"] = 1,["514"] = 1,["520"] = 1,
        ["646"] = 1,["647"] = 1,["648"] = 1,["649"] = 1,["691"] = 1,
        ["646"] = 1,["678"] = 1
    }
    local errorB = {
        ["516"] = 1,["650"] = 1,["601"] = 1,["510"] = 1,["530"] = 1,
        ["531"] = 1
    }
    local errorC = {
        ["501"] = 1,["502"] = 1,["503"] = 1,["504"] = 1,["505"] = 1,
        ["506"] = 1,["507"] = 1,["508"] = 1,["511"] = 1,["512"] = 1,
        ["515"] = 1,["517"] = 1,["518"] = 1,["519"] = 1
    }
    local errcode = tostring(code)
    if errcode then
        if errorA[errcode] then
            return 1
        end
        if errorB[errcode] then
            return 2
        end
        if errorC[errcode] then
            return 3
        end
        return 1
    end
end

--
-- 691 & last_succeed = 0 return 33
-- 691 & last_succeed = 1 return 34
-- 678 & last_succeed = 0 return 35
-- 678 & last_succeed = 1 return 36
--
function _pppoeError(code)
    local uci = require("luci.model.uci").cursor()
    local crypto = require("xiaoqiang.util.XQCryptoUtil")
    local name = uci:get("network", "wan", "username")
    local password = uci:get("network", "wan", "password")
    local last_succeed = 0
    if name and password then
        local key = crypto.md5Str(name..password)
        local value = uci:get_all("xiaoqiang", key)
        if value and value.status and tonumber(value.status) then
            last_succeed = tonumber(value.status)
        else
            last_succeed = 0
        end
        if code == 691 then
            if last_succeed == 0 then
                return 33
            else
                return 34
            end
        elseif code == 678 then
            if last_succeed == 0 then
                return 35
            else
                return 36
            end
        end
    end
    return nil
end

--- status
--- 0:未拨号
--- 1:正在拨号
--- 2:拨号成功
--- 3:正在拨号 但返现拨号错误信息
--- 4:关闭拨号
function getPPPoEStatus()
    local result = {}
    local status = ubusWanStatus()
    if status then
        local LuciNetwork = require("luci.model.network").init()
        local network = LuciNetwork:get_network("wan")
        local LuciUtil = require("luci.util")
        if status.proto == "pppoe" then	
			local link = getWanLink()
			if not link then
				LuciUtil.exec("sleep 3")
				link = getWanLink()				
			end
			if not link then
				result["status"] = 3
				result["errcode"] = 678
				result["errtype"] = 2
				result["perror"] = 35
			else	
				if status.up then
					result["status"] = 2
				else
					local check = _pppoeStatusCheck()
					if check then
						if check.process == "down" then
							result["status"] = 4
						elseif check.process == "up" then
							result["status"] = 2
						elseif check.process == "connecting" then
							if check.code == nil or check.code == 0 then
								result["status"] = 1
							else
								result["status"] = 3
								result["errcode"] = check.msg or ""
								result["errtype"] = _pppoeErrorCodeHelper(tostring(check.code))
								result["perror"] = _pppoeError(check.msg)
							end
						end
					else
						result["status"] = 0
					end
				end
			end	
            local configdns = network:get_option_value("dns")
            if not XQFunction.isStrNil(configdns) then
                result["cdns"] = luci.util.split(configdns," ")
            end
            result["pppoename"] = network:get_option_value("username")
            result["password"] = network:get_option_value("password")
            result["peerdns"] = network:get_option_value("peerdns")
        else
            result["status"] = 0
        end
        local device = network:get_interface()
        local ipaddress = device:ipaddrs()
        local ipv4 = {
            ["address"] = "",
            ["mask"] = ""
        }
        if ipaddress and #ipaddress > 0 then
            ipv4["address"] = ipaddress[1]:host():string()
            ipv4["mask"] = ipaddress[1]:mask():string()
        end
        result["ip"] = ipv4
        result["dns"] = status.dns
        result["proto"] = status.proto
        result["gw"] = network:gwaddr() or ""
        return result
    else
        return false
    end
end

function pppoeStop()
    os.execute("lua /usr/sbin/pppoe.lua down")
end

function pppoeStart()
    XQFunction.forkExec("lua /usr/sbin/pppoe.lua up")
end

--[[
@param interface : lan/wan
]]--
function getLanWanInfo(interface)
    local json = require("cjson")
    if interface ~= "lan" and interface ~= "wan" then
        return false
    end
    local LuciUtil = require("luci.util")
    local LuciNetwork = require("luci.model.network").init()
    local uci  = luci.model.uci.cursor()
    local info = {}
    local network = LuciNetwork:get_network(interface)
    if network then
        local device = network:get_interface()
        local ipAddrs = device:ipaddrs()
        local ip6_enable = uci:get("ipv6", "settings", "enabled")
        local wanType = uci:get("ipv6", "settings", "mode") or "none"
        -- disable ipv6 if wanType is none
        if wanType == "none" then
            ip6_enable = "0"
        end
        if interface == "wan" then
			info["details"] = getWanDetails()
            local mtuvalue
			if info.details and info.details.wanType == "pppoe" then
				mtuvalue = info.details.mru
			else
				mtuvalue = network:get_option_value("mtu")
			end
            if XQFunction.isStrNil(mtuvalue) then
                mtuvalue = "1480"
            end
            info["mtu"] = tostring(mtuvalue)
			
			if info.details and info.details.wanType == "pppoe" then
				local special = network:get_option_value("special")
				if special and special == "1" then
					info["special"] = 1
				else
					info["special"] = 0
				end
			end			
            
            if ip6_enable == "1" then
                info["ipv6_info"] = getIp6Details()
				if info["ipv6_info"] == nil then
					info["ipv6_info"] = {}
				end
                info["ipv6_info"]["wanType"] = wanType
            else
                info["ipv6_info"] = {}
                info["ipv6_info"]["wanType"] = wanType
            end
            -- 是否插了网线
            info["link"] = getWanLink() and 1 or 0
            -- 是否展示ipv6功能
            info["ipv6_show"] = tonumber(uci:get("ipv6", "settings", "ipv6_show") or "0")
        end
        if device and #ipAddrs > 0 then
            local ipAddress = {}
            for _,ip in ipairs(ipAddrs) do
                ipAddress[#ipAddress+1] = {}
                ipAddress[#ipAddress]["ip"] = ip:host():string()
                ipAddress[#ipAddress]["mask"] = ip:mask():string()
            end
            info["ipv4"] = ipAddress
        end
        info["gateWay"] = network:gwaddr()
        if network:dnsaddrs() then
            info["dnsAddrs"] = network:dnsaddrs()[1] or ""
            info["dnsAddrs1"] = network:dnsaddrs()[2] or ""
        else
            info["dnsAddrs"] = ""
            info["dnsAddrs1"] = ""
        end
        if device and device:mac() ~= "00:00:00:00:00:00" then
            info["mac"] = device:mac()
        end
        if info["mac"] == nil then
            info["mac"] = getWanMac()
        end
        if network:uptime() > 0 then
            info["uptime"] = network:uptime()
        else
            info["uptime"] = 0
        end
        local status = network:status()
        if status=="down" then
            info["status"] = 0
        elseif status=="up" then
            info["status"] = 1
            if info.details and info.details.wanType == "pppoe" then
                wanMonitor = getWanMonitorStat()
                if wanMonitor.WANLINKSTAT ~= "UP" then
                    info["status"] = 0
                end
            end
        elseif status=="connection" then
            info["status"] = 2
        end
    else
        info = false
    end
    return info
end

function getWan6Info()
    local LuciNetwork = require("luci.model.network").init()
    local uci  = luci.model.uci.cursor()
    local info = {}
    local network = LuciNetwork:get_network("wan")
    if network then
        local ip6_enable = uci:get("ipv6", "settings", "enabled")
        local wanType = uci:get("ipv6", "settings", "mode") or "none"
        -- disable ipv6 if wanType is none
        if wanType == "none" then
            ip6_enable = "0"
        end
        info["details"] = getWanDetails()
        if ip6_enable == "1" then
            info["ipv6_info"] = getIp6Details()
	    if info["ipv6_info"] == nil then
		info["ipv6_info"] = {}
	    end
            info["ipv6_info"]["wanType"] = wanType
        else
            info["ipv6_info"] = {}
            info["ipv6_info"]["wanType"] = wanType
        end
        -- 是否展示ipv6功能
        info["ipv6_show"] = tonumber(uci:get("ipv6", "settings", "ipv6_show"))
        info["gateWay"] = network:gwaddr()
        if network:dnsaddrs() then
            info["dnsAddrs"] = network:dnsaddrs()[1] or ""
            info["dnsAddrs1"] = network:dnsaddrs()[2] or ""
        else
            info["dnsAddrs"] = ""
            info["dnsAddrs1"] = ""
        end
     else
        info = false
    end
    return info
end

function getDefaultGWDev(deviceinfo)
    local LuciUtil = require("luci.util")
    local json = require("cjson")
    local dev_info ={}
    if deviceinfo == nil then
    	local trafficd_hw = LuciUtil.exec("ubus call trafficd hw")
    	dev_info = json.decode(trafficd_hw)
	else
		dev_info = deviceinfo
	end

	local def_gw_ifname
	local def_gw_ip = LuciUtil.exec("route -n | awk '{if($1 == \"0.0.0.0\") print $2}' | head -1")
	def_gw_ip = string.gsub(def_gw_ip,"\n","")
	for k,v in pairs(dev_info) do
		--print(k..":"..json.encode(v))
		if v.ip_list ~= nil then
			for _,ip_v in pairs(v.ip_list) do
				--print(string.format("ip_v:%s,def_gw_ip:%s",ip_v.ip,def_gw_ip))
				if ip_v.ip == def_gw_ip then
					--print("get default ifname:"..ip_v.ifname)
					def_gw_ifname = ip_v.ifname
					break
				end
			end
		end
	end

	return def_gw_ifname
end



function getWanEth()
    local LuciNetwork = require("luci.model.network").init()
    local wanNetwork = LuciNetwork:get_network("wan")
    return wanNetwork:get_option_value("ifname")
end

function getWanMac()
    local LuciUtil = require("luci.util")
    local ifconfig = LuciUtil.exec("ifconfig " .. getWanEth())
    if not XQFunction.isStrNil(ifconfig) then
        return ifconfig:match('HWaddr (%S+)') or ""
    else
        return nil
    end
end

--[[
@param interface : lan/wan
]]--
function getLanWanIp(interface)
    if interface ~= "lan" and interface ~= "wan" then
        return false
    end
    local LuciNetwork = require("luci.model.network").init()
    local ipv4 = {}
    local network = LuciNetwork:get_network(interface)
    if network then
        local device = network:get_interface()
        local ipAddrs = device:ipaddrs()
        if device and #ipAddrs > 0 then
            for _,ip in ipairs(ipAddrs) do
                ipv4[#ipv4+1] = {}
                ipv4[#ipv4]["ip"] = ip:host():string()
                ipv4[#ipv4]["mask"] = ip:mask():string()
            end
        end
    end
    return ipv4
end

function checkLanIp(ip)
    local LuciIp = require("luci.ip")
    local ipNl = LuciIp.iptonl(ip)
    if (ipNl >= LuciIp.iptonl("10.0.0.0") and ipNl <= LuciIp.iptonl("10.255.255.255"))
        or (ipNl >= LuciIp.iptonl("172.16.0.0") and ipNl <= LuciIp.iptonl("172.31.255.255"))
        or (ipNl >= LuciIp.iptonl("192.168.0.0") and ipNl <= LuciIp.iptonl("192.168.255.255")) then
        return 0
    else
        return 1527
    end
end

function setLanIp(ip,mask)
    local XQEvent = require("xiaoqiang.XQEvent")
    local LuciNetwork = require("luci.model.network").init()
    local network = LuciNetwork:get_network("lan")
    network:set("ipaddr",ip)
    network:set("netmask",mask)
    LuciNetwork:commit("network")
    LuciNetwork:save("network")
    XQEvent.lanIPChange(ip)
    return true
end

function getIPv6Addrs()
    local LuciIp = require("luci.ip")
    local LuciUtil = require("luci.util")
    local cmd = "ifconfig|grep inet6"
    local ipv6List = LuciUtil.execi(cmd)
    local result = {}
    for line in ipv6List do
        line = luci.util.trim(line)
        local ipv6,mask,ipType = line:match('inet6 addr: ([^%s]+)/([^%s]+)%s+Scope:([^%s]+)')
        if ipv6 then
            ipv6 = LuciIp.IPv6(ipv6,"ffff:ffff:ffff:ffff::")
            ipv6 = ipv6:host():string()
            result[ipv6] = {}
            result[ipv6]['ip'] = ipv6
            result[ipv6]['mask'] = mask
            result[ipv6]['type'] = ipType
        end
    end
    return result
end

function getLanIPv6Addrs()
    local LuciUtil = require("luci.util")
    local cmd = "ip addr show dev br-lan | grep inet6 | grep -v fe80 | grep -v deprecated"
    local ipv6List = LuciUtil.execi(cmd)
    local result = {}
    for line in ipv6List do
        line = luci.util.trim(line)
        local ipv6 = line:match('inet6 ([^%s]+/[^%s]+)%s+')
        if ipv6 then
            table.insert(result,ipv6)
        end
    end
    return result
end
function getLanIPv6Prefix()
    local LuciUtil = require("luci.util")
    local cmd = "ip addr show dev br-lan | grep inet6 | grep -v fe80 | grep -v deprecated"
    local ipv6List = LuciUtil.execi(cmd)
    local result = {}
    for line in ipv6List do
        line = luci.util.trim(line)
        local ipv6prefix = line:match('inet6 ([^%s]+)1/[^%s]+')
        if ipv6prefix then
            table.insert(result, ipv6prefix)
        end
    end
    return result
end

function getLanDHCPService()
    local LuciUci = require "luci.model.uci"
    local lanDhcpStatus = {}
    local uciCursor  = LuciUci.cursor()
    local ignore = uciCursor:get("dhcp", "lan", "ignore")
    local leasetime = uciCursor:get("dhcp", "lan", "leasetime")
    if ignore ~= "1" then
        ignore = "0"
    end
    local leasetimeNum,leasetimeUnit = leasetime:match("^(%d+)([^%d]+)")
    lanDhcpStatus["lanIp"] = getLanWanIp("lan")
    lanDhcpStatus["start"] = uciCursor:get("dhcp", "lan", "start")
    lanDhcpStatus["limit"] = uciCursor:get("dhcp", "lan", "limit")
    lanDhcpStatus["leasetime"] = leasetime
    lanDhcpStatus["leasetimeNum"] = leasetimeNum
    lanDhcpStatus["leasetimeUnit"] = leasetimeUnit
    lanDhcpStatus["ignore"] = ignore
    return lanDhcpStatus
end

--[[
Set Lan DHCP, range = start~end
]]--
function setLanDHCPService(startReq,endReq,leasetime,ignore)
    local LuciUci = require("luci.model.uci")
    local LuciUtil = require("luci.util")
    local uciCursor  = LuciUci.cursor()
    if ignore == "1" then
        uciCursor:set("dhcp", "lan", "ignore", tonumber(ignore))
    else
        local limit = tonumber(endReq) - tonumber(startReq) + 1
        if limit < 0 then
            return false
        end
        uciCursor:set("dhcp", "lan", "start", tonumber(startReq))
        uciCursor:set("dhcp", "lan", "limit", tonumber(limit))
        uciCursor:set("dhcp", "lan", "leasetime", leasetime)
        uciCursor:delete("dhcp", "lan", "ignore")
    end
    uciCursor:save("dhcp")
    uciCursor:load("dhcp")
    uciCursor:commit("dhcp")
    uciCursor:load("dhcp")
    LuciUtil.exec("/etc/init.d/dnsmasq restart > /dev/null")
    return true
end

function wanDown()
    local LuciUtil = require("luci.util")
    LuciUtil.exec("env -i /sbin/ifdown wan")
end

function wanRestart()
    local LuciUtil = require("luci.util")
    LuciUtil.exec("env -i /sbin/ifup wan")
    XQFunction.forkExec("/etc/init.d/filetunnel restart")
end

function dnsmsqRestart()
    local LuciUtil = require("luci.util")
    LuciUtil.exec("ubus call network reload; sleep 1; /etc/init.d/dnsmasq restart > /dev/null")
end

--[[
Get wan details, static ip/pppoe/dhcp/mobile
@return {proto="dhcp",ifname=ifname,dns=dns,peerdns=peerdns}
@return {proto="static",ifname=ifname,ipaddr=ipaddr,netmask=netmask,gateway=gateway,dns=dns}
@return {proto="pppoe",ifname=ifname,username=pppoename,password=pppoepasswd,dns=dns,peerdns=peerdns}
]]--
function getWanDetails()
    local LuciNetwork = require("luci.model.network").init()
    local wanNetwork = LuciNetwork:get_network("wan")
    local wanDetails = {}
    if wanNetwork then
        local wanType = wanNetwork:proto()
        if wanType == "mobile" or wanType == "3g" then
            wanType = "mobile"
        elseif wanType == "static" then
            wanDetails["ipaddr"] = wanNetwork:get_option_value("ipaddr")
            wanDetails["netmask"] = wanNetwork:get_option_value("netmask")
            wanDetails["gateway"] = wanNetwork:get_option_value("gateway")
        elseif wanType == "pppoe" then
            wanDetails["username"] = wanNetwork:get_option_value("username")
            wanDetails["password"] = wanNetwork:get_option_value("password")
            wanDetails["peerdns"] = wanNetwork:get_option_value("peerdns")
            wanDetails["service"] = wanNetwork:get_option_value("service")
			wanDetails["mru"] = wanNetwork:get_option_value("mru")
        elseif wanType == "dhcp" then
            wanDetails["peerdns"] = wanNetwork:get_option_value("peerdns")
        end
        if not XQFunction.isStrNil(wanNetwork:get_option_value("dns")) then
            wanDetails["dns"] = luci.util.split(wanNetwork:get_option_value("dns")," ")
        end
        wanDetails["wanType"] = wanType
        wanDetails["ifname"] = wanNetwork:get_option_value("ifname")
        return wanDetails
    else
        return nil
    end
end

function getIp6Details()
    local LuciNetwork = require("luci.model.network").init()
    local LuciUtil = require("luci.util")
    local json = require("cjson")
    local wanNetworkIpv4 = LuciNetwork:get_network("wan")
    local wanTypeIpv4 = wanNetworkIpv4:proto()
    local uci = luci.model.uci.cursor()
    local wanDetails = {}

    local wanType = uci:get("ipv6", "settings", "mode") or "none"
    wanDetails["assign"] = uci:get("ipv6", "settings", "ip6assign")
    wanDetails["peerdns"] = uci:get("ipv6", "dns", "peerdns")
    local wanStatus
    if wanTypeIpv4 == "pppoe" then
        wanStatus = "ubus call network.interface.wan_6 status"
    else
        wanStatus = "ubus call network.interface.wan6 status"
    end
    local ip6 = LuciUtil.exec(wanStatus)
    if not XQFunction.isStrNil(ip6) then
        ip6 = json.decode(ip6)
        if ip6["route"] then
        for i=1,#ip6["route"] do
            if ip6["route"][i]["nexthop"] ~= "::" then
                wanDetails["ip6gw"] = ip6["route"][i]["nexthop"]
                    break
                    end
            end
            wanDetails["dns"] = ip6["dns-server"]
        end
        if ip6["ipv6-address"] then
            local ipAddress = {}
                for _,ip in ipairs(ip6["ipv6-address"]) do
                    table.insert(ipAddress,ip.address .."/" .. ip.mask)
                end
                wanDetails["ip6addr"] = ipAddress
        end
    end
    wanDetails["lan_ip6addr"] = getLanIPv6Addrs()
    wanDetails["lan_ip6prefix"] = getLanIPv6Prefix()
    wanDetails["wanType"] = wanType
    wanDetails["ifname"] = ip6["device"]
    return wanDetails
end

function generateDns(dns1, dns2, peerdns)
    local dns
    if not XQFunction.isStrNil(dns1) and not XQFunction.isStrNil(dns2) then
        dns = {dns1,dns2}
    elseif not XQFunction.isStrNil(dns1) then
        dns = dns1
    elseif not XQFunction.isStrNil(dns2) then
        dns = dns2
    end
    return dns
end

function checkMTU(value)
    local mtu = tonumber(value)
    if mtu and mtu >= 576 and mtu <= 1492 then
        return true
    else
        return false
    end
end

function setWanPPPoE(name, password, dns1, dns2, peerdns, mtu, special, service)
    local XQPreference = require("xiaoqiang.XQPreference")
    local LuciNetwork = require("luci.model.network").init()
    local uci = require("luci.model.uci").cursor()
    local macaddr = uci:get("network", "wan", "macaddr")

    local iface = "wan"
    local ifname = getWanEth()
    local oldconf = uci:get_all("network", "wan") or {}
    local wanrestart = true
    local dnsrestart = true
    -- get hardware type
    local LuciUtil = require("luci.util")
    local HARDWARE = uci:get("misc", "hardware", "model") or ""
    if HARDWARE then
        HARDWARE = string.lower(HARDWARE)
    end

    if oldconf.username == name
        and oldconf.password == password
        and tonumber(oldconf.mru) == tonumber(mtu)
        and ((XQFunction.isStrNil(oldconf.service) and XQFunction.isStrNil(service)) or oldconf.service == service)
        and ((tonumber(oldconf.special) == tonumber(special)) or (not oldconf.special and tonumber(special) == 0)) then
        wanrestart = false
    end
    if name and password then
        local crypto = require("xiaoqiang.util.XQCryptoUtil")
        local sync = require("xiaoqiang.util.XQSynchrodata")
        local sysutil = require("xiaoqiang.util.XQSysUtil")
        sysutil.doConfUpload({
            ["pppoe_name"] = name,
            ["pppoe_password"] = password
        })
        local key = crypto.md5Str(name..password)
        local value = uci:get_all("xiaoqiang", key)
        if not value then
            uci:section("xiaoqiang", "record", key,{
                ["username"] = name,
                ["password"] = password,
                ["status"] = 0
            })
            uci:commit("xiaoqiang")
        end
    end
    local dnss = {}
    local odnss = {}
    if oldconf.dns and type(oldconf.dns) == "string" then
        odnss = {oldconf.dns}
    elseif oldconf.dns and type(oldconf.dns) == "table" then
        odnss = oldconf.dns
    end
    if not XQFunction.isStrNil(dns1) then
        table.insert(dnss, dns1)
    end
    if not XQFunction.isStrNil(dns2) then
        table.insert(dnss, dns2)
    end
    local use_peer_dns = #dnss > 0 and '0' or nil -- if set customized dns, ignore peer's
    if #dnss == #odnss then
        if #dnss == 0 then
           dnsrestart = false
        else
            local odnsd = {}
            local match = 0
            for _, dns in ipairs(odnss) do
                odnsd[dns] = 1
            end
            for _, dns in ipairs(dnss) do
                if odnsd[dns] == 1 then
                    match = match + 1
                end
            end
            if match == #dnss then
                dnsrestart = false
            end
        end
    end

    local wanNet = LuciNetwork:del_network(iface)
    local mtuvalue
    if mtu then
        if checkMTU(mtu) then
            mtuvalue = tonumber(mtu)
        else
            return false
        end
    else
        mtuvalue = 1480
    end
    wanNet = LuciNetwork:add_network(
        iface, {
            proto    ="pppoe",
            ifname   = ifname,
            username = name,
            password = password,
            dns      = generateDns(dns1,dns2,peerdns),
            peerdns  = use_peer_dns,
            macaddr  = macaddr,
            service  = service,
            mru      = mtuvalue,
            special  = special
        })
    if not XQFunction.isStrNil(dns1) then
        XQFunction.nvramSet("nv_wan_dns1", dns1)
    else
        XQFunction.nvramSet("nv_wan_dns1", "")
    end
    if not XQFunction.isStrNil(dns2) then
        XQFunction.nvramSet("nv_wan_dns2", dns2)
    else
        XQFunction.nvramSet("nv_wan_dns2", "")
    end
    if not XQFunction.isStrNil(name) then
        XQPreference.set(XQConfigs.PREF_PPPOE_NAME,name)
        XQFunction.nvramSet("nv_pppoe_name", name)
    end
    if not XQFunction.isStrNil(password) then
        XQPreference.set(XQConfigs.PREF_PPPOE_PASSWORD,password)
        XQFunction.nvramSet("nv_pppoe_pwd", password)
    end
    if not XQFunction.isStrNil(service) then
        XQFunction.nvramSet("nv_pppoe_service", service)
    end
    XQFunction.nvramSet("nv_wan_type", "pppoe")
    XQFunction.nvramCommit()
    if wanNet then
        LuciNetwork:save("network")
        LuciNetwork:commit("network")
        
        -- set wan type into autowan
        if HARDWARE:match("^d01") then
            -- 0-null/1-dhcp/2-pppoe/3-static
            LuciUtil.exec("ubus call autowan set '{\"wan_type\":2}'")
        end

        --os.execute(XQConfigs.VPN_DISABLE)
        if dnsrestart then
            dnsmsqRestart()
        end
        if wanrestart then
            wanRestart()
        else
            local pppoestatus = getPPPoEStatus()
            if pppoestatus and pppoestatus.status == 4 then
                pppoeStart()
            end
        end
		
        -- ipv6
        local ipv6_enable = uci:get("ipv6", "settings", "enabled") or "0"
        if ipv6_enable and ipv6_enable == "1" then					
            --switch off static wan6 interface
            local wanTypeIpv6 = uci:get("ipv6", "settings", "mode") or "none"
            if wanTypeIpv6 == "static" or wanTypeIpv6 == "off" or wanTypeIpv6 == "none" then
            	XQFunction.forkExec("/etc/init.d/ipv6 off")	
            else
            	XQFunction.forkExec("/etc/init.d/ipv6 " .. wanTypeIpv6)
            end			
        end
		
        return true
    else
        return false
    end
end

function checkWanIp(ip)
    local LuciIp = require("luci.ip")
    local ipNl = LuciIp.iptonl(ip)
    if (ipNl >= LuciIp.iptonl("1.0.0.0") and ipNl <= LuciIp.iptonl("126.255.255.255"))
        or (ipNl >= LuciIp.iptonl("128.0.0.0") and ipNl <= LuciIp.iptonl("223.255.255.255")) then
        return 0
    else
        return 1533
    end
end

function setWanStaticOrDHCP(ipType, ip, mask, gw, dns1, dns2, peerdns, mtu)
    local LuciNetwork = require("luci.model.network").init()
    local uci = require("luci.model.uci").cursor()
    local macaddr = uci:get("network", "wan", "macaddr")
    local oldconf = uci:get_all("network", "wan") or {}

    local iface = "wan"
    local ifname = getWanEth()
    local dnsrestart = true
    local wanrestart = true
    local dnss = {}
    local odnss = {}
    -- get hardware type
    local LuciUtil = require("luci.util")
    local HARDWARE = uci:get("misc", "hardware", "model") or ""
    if HARDWARE then
        HARDWARE = string.lower(HARDWARE)
    end

    if oldconf.dns and type(oldconf.dns) == "string" then
        odnss = {oldconf.dns}
    elseif oldconf.dns and type(oldconf.dns) == "table" then
        odnss = oldconf.dns
    end
    if not XQFunction.isStrNil(dns1) then
        table.insert(dnss, dns1)
    end
    if not XQFunction.isStrNil(dns2) then
        table.insert(dnss, dns2)
    end
    local use_peer_dns = #dnss > 0 and '0' or nil -- if set customized dns, ignore peer's
    if #dnss == #odnss then
        if #dnss == 0 then
	    dnsrestart = false
        else
            local odnsd = {}
            local match = 0
            for _, dns in ipairs(odnss) do
                odnsd[dns] = 1
            end
            for _, dns in ipairs(dnss) do
                if odnsd[dns] == 1 then
                    match = match + 1
                end
            end
            if match == #dnss then
                dnsrestart = false
            end
        end
    end
    local wanNet = LuciNetwork:del_network(iface)
    local dns = generateDns(dns1, dns2, peerdns)
    local mtuvalue
    if mtu then
        mtuvalue = tonumber(mtu)
    else
        mtuvalue = 1500
    end
    if ipType == "dhcp" then
        if oldconf.proto == "dhcp" then
            wanrestart = false
        end
        local network = {
            proto   = "dhcp",
            ifname  = ifname,
            dns     = dns,
            macaddr = macaddr,
            peerdns = use_peer_dns,
            mtu = mtuvalue
        }

        wanNet = LuciNetwork:add_network(iface, network)
    elseif ipType == "static" then
        if oldconf.proto == "static"
            and oldconf.ipaddr == ip
            and oldconf.netmask == mask
            and oldconf.gateway == gw
            and oldconf.mtu == mtuvalue then
            wanrestart = false
        end
        if not dns then
            dns = gw
        end
        local network = {
            proto   = "static",
            ipaddr  = ip,
            netmask = mask,
            gateway = gw,
            dns     = dns,
            macaddr = macaddr,
            ifname  = ifname,
            mtu = mtuvalue
        }

        wanNet = LuciNetwork:add_network(iface, network)
        if not XQFunction.isStrNil(ip) then
            XQFunction.nvramSet("nv_wan_ip", ip)
        end
        if not XQFunction.isStrNil(gw) then
            XQFunction.nvramSet("nv_wan_gateway", gw)
        end
        if not XQFunction.isStrNil(mask) then
            XQFunction.nvramSet("nv_wan_netmask", mask)
        end
        if not XQFunction.isStrNil(dns1) then
            XQFunction.nvramSet("nv_wan_dns1", dns1)
        else
            XQFunction.nvramSet("nv_wan_dns1", "")
        end
        if not XQFunction.isStrNil(dns2) then
            XQFunction.nvramSet("nv_wan_dns2", dns2)
        else
            XQFunction.nvramSet("nv_wan_dns2", "")
        end
    end
    XQFunction.nvramSet("nv_wan_type", ipType)
    XQFunction.nvramCommit()
    if wanNet then
        LuciNetwork:save("network")
        LuciNetwork:commit("network")

        -- set wan type into autowan
        if HARDWARE:match("^d01") then
            -- 0-null/1-dhcp/2-pppoe/3-static
            if ipType == "dhcp" then
                LuciUtil.exec("ubus call autowan set '{\"wan_type\":1}'")
            elseif ipType == "static" then
                LuciUtil.exec("ubus call autowan set '{\"wan_type\":3}'")
            end
        end

        if dnsrestart then
            dnsmsqRestart()
        end
        if wanrestart then
            wanRestart()
        end

        -- ipv6
        local ipv6_enable = uci:get("ipv6", "settings", "enabled") or "0"
        if ipv6_enable and ipv6_enable == "1" then					
            --switch off static wan6 interface
            local wanTypeIpv6 = uci:get("ipv6", "settings", "mode") or "none"
            if wanTypeIpv6 == "static" or wanTypeIpv6 == "off" or wanTypeIpv6 == "none" then
                XQFunction.forkExec("/etc/init.d/ipv6 off")	
            else
                --switch on wan6 interface
            	XQFunction.forkExec("/etc/init.d/ipv6 " .. wanTypeIpv6)
            end			
        end			
		
        return true
    else
        return false
    end
end

function setWanMac(mac)
    local LuciNetwork = require("luci.model.network").init()
    local LuciDatatypes = require("luci.cbi.datatypes")
    local network = LuciNetwork:get_network("wan")
    local oldMac = network:get_option_value("macaddr")
    local succeed = false
    if oldMac ~= mac then
        if XQFunction.isStrNil(mac) then
            local defaultMac = getDefaultWanMacAddress() or ""
            network:set("macaddr",defaultMac)
            succeed = true
        elseif LuciDatatypes.macaddr(mac) and mac ~= "ff:ff:ff:ff:ff:ff" and mac ~= "00:00:00:00:00:00" then
            network:set("macaddr",mac)
            succeed = true
        end
    else
        succeed = true
    end
    if succeed then
        LuciNetwork:save("network")
        LuciNetwork:commit("network")
        wanRestart()
    end
    return succeed
end

function _checkIP(ip)
    if XQFunction.isStrNil(ip) then
        return false
    end
    local LuciIp = require("luci.ip")
    local ipNl = LuciIp.iptonl(ip)
    if (ipNl >= LuciIp.iptonl("1.0.0.0") and ipNl <= LuciIp.iptonl("126.0.0.0"))
        or (ipNl >= LuciIp.iptonl("128.0.0.0") and ipNl <= LuciIp.iptonl("223.255.255.255")) then
        return true
    else
        return false
    end
end

function _checkMac(mac)
    if XQFunction.isStrNil(mac) then
        return false
    end
    local LuciDatatypes = require("luci.cbi.datatypes")
    if LuciDatatypes.macaddr(mac) and mac ~= "ff:ff:ff:ff:ff:ff" and mac ~= "00:00:00:00:00:00" then
        return true
    else
        return false
    end
end

function _parseMac(mac)
    if mac then
        return string.lower(string.gsub(mac,"[:-]",""))
    else
        return nil
    end
end

function _parseDhcpLeases()
    local NixioFs = require("nixio.fs")
    local uci =  require("luci.model.uci").cursor()
    local result = {}
    local leasefile = XQConfigs.DHCP_LEASE_FILEPATH
    uci:foreach("dhcp", "dnsmasq",
    function(s)
        if s.leasefile and NixioFs.access(s.leasefile) then
            leasefile = s.leasefile
            return false
        end
    end)
    local dhcp = io.open(leasefile, "r")
    if dhcp then
        for line in dhcp:lines() do
            if line then
                local ts, mac, ip, name = line:match("^(%d+) (%S+) (%S+) (%S+)")
                if name == "*" then
                    name = ""
                end
                if ts and mac and ip and name then
                    result[ip] = {
                        mac  = string.lower(XQFunction.macFormat(mac)),
                        ip   = ip,
                        name = name
                    }
                end
            end
        end
        dhcp:close()
    end
    return result
end

--
-- Event
--
function hookLanIPChangeEvent(ip)
    if XQFunction.isStrNil(ip) then
        return
    end
    local uci = require("luci.model.uci").cursor()
    local lan = ip:gsub(".%d+$","")
    uci:foreach("macbind", "host",
        function(s)
            local ip = s.ip
            ip = lan.."."..ip:match(".(%d+)$")
            uci:set("macbind", s[".name"], "ip", ip)
        end
    )
    uci:foreach("dhcp", "host",
        function(s)
            local ip = s.ip
            ip = lan.."."..ip:match(".(%d+)$")
            uci:set("dhcp", s[".name"], "ip", ip)
        end
    )
    uci:commit("dhcp")
    uci:commit("macbind")
end

--- Tag
--- 0:未添加
--- 1:已添加
--- 2:已绑定
function macBindInfo()
    local uci = require("luci.model.uci").cursor()
    local info = {}
    uci:foreach("macbind", "host",
        function(s)
            local item = {
                ["name"] = s.name,
                ["mac"] = s.mac,
                ["ip"] = s.ip,
                ["tag"] = 1
            }
            info[s.mac] = item
        end
    )
    uci:foreach("dhcp", "host",
        function(s)
            local item = {
                ["name"] = s.name,
                ["mac"] = s.mac,
                ["ip"] = s.ip,
                ["tag"] = 2
            }
            info[s.mac] = item
        end
    )
    return info
end

--- 0:设置成功
--- 1:IP冲突
--- 2:MAC/IP 不合法
function addBind(mac, ip)
    local uci = require("luci.model.uci").cursor()
    if _checkIP(ip) and _checkMac(mac) then
        local dhcp = _parseDhcpLeases()
        mac = string.lower(XQFunction.macFormat(mac))
        local host = dhcp[ip]
        if host and host.mac ~= mac then
            return 1
        end
        local name = _parseMac(mac)
        local options = {
            ["name"] = name,
            ["mac"] = mac,
            ["ip"] = ip
        }
        uci:section("macbind", "host", name, options)
        uci:commit("macbind")
    else
        return 2
    end
    return 0
end

function removeBind(mac)
    local uci = require("luci.model.uci").cursor()
    if _checkMac(mac) then
        local name = _parseMac(mac)
        uci:delete("macbind", name)
        uci:delete("dhcp", name)
        uci:commit("macbind")
        uci:commit("dhcp")
        return true
    else
        return false
    end
end

function unbindAll()
    local uci = require("luci.model.uci").cursor()
    uci:delete_all("dhcp", "host")
    uci:delete_all("macbind", "host")
    uci:commit("dhcp")
    uci:commit("macbind")
end

function saveBindInfo()
    local uci = require("luci.model.uci").cursor()
    uci:delete_all("dhcp", "host")
    uci:foreach("macbind", "host",
        function(s)
            local options = {
                ["name"] = s.name,
                ["mac"] = s.mac,
                ["ip"] = s.ip
            }
            uci:section("dhcp", "host", s.name, options)
        end
    )
    uci:commit("dhcp")
end

-- r1c:0/10/100    自动/10M/100M
-- r1d:0/100/1000  自动/100M/1000M
function getWanSpeed()
    local LuciUtil = require("luci.util")
    local XQPreference = require("xiaoqiang.XQPreference")
    local wanspeed = tonumber(XQPreference.get("WAN_SPEED", 0))
    return wanspeed or 0
end

function setWanSpeed(speed)
    local XQPreference = require("xiaoqiang.XQPreference")
    local speed = tonumber(speed)
    if speed then
        XQPreference.set("WAN_SPEED", speed)
        if speed == 10 then
            os.execute("/usr/bin/longloopd stop > /dev/null 2>&1")
        else
            os.execute("/usr/bin/longloopd start > /dev/null 2>&1")
        end
        os.execute("phyhelper swan "..tostring(speed).." > /dev/null 2>&1")
	return true
    end
    return false
end

function pppoeCatch(timeout)
    local LuciUtil = require("luci.util")
    local result = {
        ["code"] = 0,
        ["service"] = "",
        ["pppoename"] = "",
        ["pppoepasswd"] = ""
    }
    local pppoe = LuciUtil.execl("/usr/sbin/pppoe-catch start "..tostring(timeout))
    if pppoe and type(pppoe) == "table" then
        for index, value in ipairs(pppoe) do
            if not XQFunction.isStrNil(value) then
                local service = LuciUtil.trim(value):match("^Service%-Name:%s(.+)")
                if not XQFunction.isStrNil(service) then
                    result.service = service
                end
                if LuciUtil.trim(value):match("PPPoE:") then
                    local pppoename = pppoe[index + 1]
                    local pppoepasswd = pppoe[index + 2]
                    if not XQFunction.isStrNil(pppoename) then
                        result.pppoename = LuciUtil.trim(pppoename)
                    end
                    if not XQFunction.isStrNil(pppoepasswd) then
                        result.pppoepasswd = LuciUtil.trim(pppoepasswd)
                    end
                    break
                end
            end
        end
    end
    if XQFunction.isStrNil(result.pppoename) and XQFunction.isStrNil(result.pppoepasswd) then
        result.code = 1
    end
    return result
end

function setWan(proto, username, password, service)
    local uci = require("luci.model.uci").cursor()
    local owan = uci:get_all("network", "wan")
    if proto == "pppoe" then
        local wan = {
            ["ifname"] = owan.ifname,
            ["proto"] = proto,
            ["username"] = username,
            ["password"] = password,
            ["service"] = service
        }
        uci:delete("network", "wan")
        uci:section("network", "interface", "wan", wan)
        uci:commit("network")
        wanRestart()
        pppoeStart()
    elseif proto == "dhcp" then
        if owan.proto == "pppoe" then
            local wan = {
                ["ifname"] = owan.ifname,
                ["proto"] = "dhcp"
            }
            pppoeStop()
            uci:delete("network", "wan")
            uci:section("network", "interface", "wan", wan)
            uci:commit("network")
            wanRestart()
        end
    end
    return true
end

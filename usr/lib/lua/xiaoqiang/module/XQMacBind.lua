module ("xiaoqiang.module.XQMacBind", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local XQConfigs = require("xiaoqiang.common.XQConfigs")

local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
local uci = require("luci.model.uci").cursor()

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
--- 1:未生效
--- 2:已生效
function macBindInfo()
    local info = {}
    local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
    local XQEquipment = require("xiaoqiang.XQEquipment")
    uci:foreach("dhcp", "host",
        function(s)
            local item = {
                ["name"] = "",
                ["mac"] = s.mac,
                ["ip"] = s.ip,
                ["tag"] = 2
            }
            local mac = string.upper(s.mac)
            local name = ""
            local device = XQDBUtil.fetchDeviceInfo(mac)
            if device then
                local originName = device.oName
                local nickName = device.nickname
                if not XQFunction.isStrNil(nickname) then
                    name = nickname
                else
                    local company = XQEquipment.identifyDevice(mac, originName)
                    local dtype = company["type"]
                    if XQFunction.isStrNil(name) and not XQFunction.isStrNil(dtype.n) then
                        name = dtype.n
                    end
                    if XQFunction.isStrNil(name) and not XQFunction.isStrNil(originName) then
                        name = originName
                    end
                    if XQFunction.isStrNil(name) and not XQFunction.isStrNil(company.name) then
                        name = company.name
                    end
                    if XQFunction.isStrNil(name) then
                        name = mac
                    end
                    if dtype.c == 3 and XQFunction.isStrNil(nickName) then
                        name = dtype.n
                    end
                end
                item["name"] = name
            end
            info[s.mac] = item
        end
    )
    return info
end

--- 0:设置成功
--- 1:和其它设备IP冲突
--- 2:MAC/IP 不合法
--- 3:参数列表中IP冲突
function addBind(mac, ip, name)
    if _checkIP(ip) and _checkMac(mac) then
        local dhcp = _parseDhcpLeases()
        mac = string.lower(XQFunction.macFormat(mac))
        local host = dhcp[ip]
        if host and host.mac ~= mac then
            return 1
        end
        local oname = _parseMac(mac)
        local options = {
            ["name"] = oname,
            ["mac"] = mac,
            ["ip"] = ip
        }
        XQDBUtil.saveDeviceInfo(string.upper(mac), name, name, "", "")
        uci:section("macbind", "host", oname, options)
        uci:section("dhcp", "host", oname, options)
        uci:commit("macbind")
        uci:commit("dhcp")
    else
        return 2
    end
    return 0
end

--- 0:设置成功
--- 1:和其它设备IP冲突
--- 2:MAC/IP 不合法
--- 3:参数列表中IP冲突
function addBinds(binds)
    if type(binds) ~= "table" then
        return 0
    end
    local ipdict = {}
    local dhcp = _parseDhcpLeases()
    for _, item in ipairs(binds) do
        local mac = string.lower(XQFunction.macFormat(item.mac))
        local ip = item.ip
        if not _checkIP(ip) or not _checkMac(mac) then
            return 2
        end
        if ipdict[ip] ~= 1 then
            ipdict[ip] = 1
            local name = item.name
            local host = dhcp[ip]
            if host and host.mac ~= mac then
                return 1
            end
            local oname = _parseMac(mac)
            local options = {
                ["name"] = oname,
                ["mac"] = mac,
                ["ip"] = ip
            }
            XQDBUtil.saveDeviceInfo(string.upper(mac), name, name, "", "")
            uci:section("macbind", "host", oname, options)
            uci:section("dhcp", "host", oname, options)
        else
            return 3
        end
    end
    uci:commit("macbind")
    uci:commit("dhcp")
    return 0
end

function removeBind(mac)
    if _checkMac(mac) then
        local name = _parseMac(mac)
        uci:delete("dhcp", name)
        uci:commit("dhcp")
        return true
    else
        return false
    end
end

function removeBinds(binds)
    if type(binds) ~= "table" then
        return true
    end
    for _, mac in ipairs(binds) do
        if _checkMac(mac) then
            local name = _parseMac(mac)
            uci:delete("dhcp", name)
        else
            return false
        end
    end
    uci:commit("dhcp")
    return true
end

function unbindAll()
    uci:delete_all("dhcp", "host")
    uci:commit("dhcp")
end

function reload()
    os.execute("killall -s 10 noflushd ; /etc/init.d/dnsmasq restart")
end

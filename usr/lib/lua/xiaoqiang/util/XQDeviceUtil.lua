module ("xiaoqiang.util.XQDeviceUtil", package.seeall)

local Json = require("cjson")

local XQConfigs = require("xiaoqiang.common.XQConfigs")
local XQFunction = require("xiaoqiang.common.XQFunction")
local XQEquipment = require("xiaoqiang.XQEquipment")

local LuciDatatypes = require("luci.cbi.datatypes")

function getDeviceCompany(mac)
    local companyInfo = { name = "", icon = "" }
    if XQFunction.isStrNil(mac) or string.len(mac) < 8 then
        return companyInfo
    end
    return XQEquipment.identifyDevice(mac, nil)
end

function getDeviceInfoFromDB()
    local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
    local result = {}
    local deviceList = XQDBUtil.fetchAllDeviceInfo()
    if #deviceList > 0 then
        for _,device in ipairs(deviceList) do
            result[device.mac] = device
        end
    end
    return result
end

function getDeviceMacsFromDB()
    local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
    local result = {}
    local deviceList = XQDBUtil.fetchAllDeviceInfo()
    if #deviceList > 0 then
        for _,device in ipairs(deviceList) do
            table.insert(result, device.mac)
        end
    end
    return result
end

function getDeviceInfoFromConfig()
    local uci = require("luci.model.uci").cursor()
    local result = {}
    uci:foreach("deviceinfo", "device",
        function(s)
            local item = {
                ["mac"] = XQFunction.macFormat(s.mac),
                ["owner"] = s.owner,
                ["device"] = s.device
            }
            result[item.mac] = item
        end
    )
    return result
end

function fetchDeviceInfoFromConfig(mac)
    local deviceinfo = {
        ["owner"] = "",
        ["device"] = ""
    }
    if XQFunction.isStrNil(mac) then
        return deviceinfo
    else
        mac = XQFunction.macFormat(mac)
    end
    local mackey = string.lower(mac:gsub(":", ""))
    local uci = require("luci.model.uci").cursor()
    local info = uci:get_all("deviceinfo", mackey)
    if info then
        deviceinfo.owner = info.owner or ""
        deviceinfo.device = info.device or ""
    end
    return deviceinfo
end

function saveDeviceInfo(mac, owner, device)
    if XQFunction.isStrNil(mac) then
        return
    end
    local uci = require("luci.model.uci").cursor()
    local mac = XQFunction.macFormat(mac)
    local mackey = string.lower(mac:gsub(":", ""))
    if uci:get_all("deviceinfo", mackey) then
        if owner then
            uci:set("deviceinfo", mackey, "owner", owner)
        end
        if device then
            uci:set("deviceinfo", mackey, "device", device)
        end
    else
        local section = {
            ["mac"] = mac,
            ["owner"] = owner or "",
            ["device"] = device or ""
        }
        uci:section("deviceinfo", "device", mackey, section)
    end
    uci:commit("deviceinfo")
end

function saveDeviceName(mac, name, owner, device)
    local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
    local XQSync = require("xiaoqiang.util.XQSynchrodata")
    local mac = XQFunction.macFormat(mac)
    XQSync.syncDeviceInfo({["mac"] = mac, ["nickname"] = name, ["owner"] = owner, ["device"] = device})
    local code = XQDBUtil.updateDeviceNickname(mac,name)
    if code == 0 then
        saveDeviceInfo(mac, owner, device)
        return true
    else
        return false
    end
end

--
--	Get DHCP list
--

function getDHCPList()
    local NixioFs = require("nixio.fs")
    local LuciUci = require("luci.model.uci")
    local uci =  LuciUci.cursor()
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
                    result[#result+1] = {
                        mac  = XQFunction.macFormat(mac),
                        ip   = ip,
                        name = name
                    }
                end
            end
        end
        dhcp:close()
        return result
    else
        return {}
    end
end

function getDHCPDict()
    local dhcpDict = {}
    local dhcpList = getDHCPList()
    for _,value in ipairs(dhcpList) do
        dhcpDict[value.mac] = value
    end
    return dhcpDict
end

function getDHCPIpDict()
    local dhcpDict = {}
    local dhcpList = getDHCPList()
    for _,value in ipairs(dhcpList) do
        dhcpDict[value.ip] = value
    end
    return dhcpDict
end

function getMacfilterInfoList()
    local LuciUtil = require("luci.util")
    local macFilterInfo = {}
    local metaData = LuciUtil.execi("/usr/sbin/sysapi macfilter get")
    for filterInfo in metaData do
        filterInfo = filterInfo..";"
        local mac = filterInfo:match('mac=(%S-);') or ""
        local wan = filterInfo:match('wan=(%S-);') or ""
        local lan = filterInfo:match('lan=(%S-);') or ""
        local admin = filterInfo:match('admin=(%S-);') or ""
        local pridisk = filterInfo:match('pridisk=(%S-);') or ""
        local entry = {}
        if (not XQFunction.isStrNil(mac)) then
            entry["mac"] = XQFunction.macFormat(mac)
            entry["wan"] = (string.upper(wan) == "YES" and true or false)
            entry["lan"] = (string.upper(lan) == "YES" and true or false)
            entry["admin"] = (string.upper(admin) == "YES" and true or false)
            entry["pridisk"] = (string.upper(pridisk) == "YES" and true or false)
            table.insert(macFilterInfo, entry)
        end
    end
    return macFilterInfo
    -- local uci = require("luci.model.uci").cursor()
    -- local macFilterInfo = {}
    -- uci:foreach("macfilter", "mac",
    --     function(record)
    --         local item = {
    --             ["mac"] = XQFunction.macFormat(record.mac),
    --             ["wan"] = record.wan == "yes" and true or false,
    --             ["lan"] = record.lan == "yes" and true or false,
    --             ["admin"] = record.admin == "yes" and true or false,
    --             ["pridisk"] = record.pridisk == "yes" and true or false
    --         }
    --         table.insert(macFilterInfo, item)
    --     end
    -- )
    -- return macFilterInfo
end

function getMacfilterInfoDict()
    local macFilterDict = {}
    local macFilterList = getMacfilterInfoList()
    for _,value in ipairs(macFilterList) do
        macFilterDict[value.mac] = value
    end
    return macFilterDict
end

function getDevicesName(macs)
    local names = {}
    if macs and type(macs) == "table" then
        local dbinfo = getDeviceInfoFromDB()
        local dhcpinfo = getDHCPDict()
        for _, mac in ipairs(macs) do
            mac = XQFunction.macFormat(mac)
            local dinfo = dbinfo[mac]
            local dhinfo = dhcpinfo[mac]
            if dinfo and not XQFunction.isStrNil(dinfo.nickname) then
                names[mac] = dinfo.nickname
            else
                local dhcpname
                if dhinfo and not XQFunction.isStrNil(dhinfo.name) then
                    dhcpname = dhinfo.name
                    names[mac] = dhinfo.name
                end
                local iden = XQEquipment.identifyDevice(mac, dhcpname)
                if XQFunction.isStrNil(names[mac]) then
                    if iden and not XQFunction.isStrNil(iden["type"].n) then
                        names[mac] = iden["type"].n
                    elseif iden and not XQFunction.isStrNil(iden.name) then
                        names[mac] = iden["name"]
                    else
                        names[mac] = mac
                    end
                else

                end
            end
        end
        return names
    else
        return nil
    end
end

function getDevicesPermissions(macs)
    local LuciUtil = require("luci.util")
    local json = require("json")
    local macfilter = {}
    local permissions = {}
    local data = LuciUtil.execl("/usr/sbin/sysapi macfilter get")
    local macarry = {}
    local disk_access_permission = {}
    if macs and type(macs) == "table" then
        macarry = macs
    else
        for _, permission in ipairs(data) do
            local mac = permission:match('mac=(%S-);') or ""
            if mac and mac ~= "" then
                table.insert(macarry, XQFunction.macFormat(mac))
            end
        end
    end
    local payload = {
        ["api"] = 70,
        ["macs"] = macarry
    }
    local result = XQFunction.thrift_tunnel_to_datacenter(json.encode(payload))
    if result and result.code == 0 then
        for index, v in ipairs(result.canAccessAllDisk) do
            disk_access_permission[macarry[index]] = v
        end
    end
    for _, permission in ipairs(data) do
        permission = permission..";"
        local mac       = permission:match('mac=(%S-);') or ""
        local wan       = permission:match('wan=(%S-);') or ""
        local lan       = permission:match('lan=(%S-);') or ""
        local admin     = permission:match('admin=(%S-);') or ""
        local pridisk   = permission:match('pridisk=(%S-);') or ""

        local item = {}
        if mac then
            mac = XQFunction.macFormat(mac)
            item["wan"]     = string.upper(wan) == "YES" and 1 or 0
            item["lan"]     = string.upper(lan) == "YES" and 1 or 0
            item["admin"]   = string.upper(admin) == "YES" and 1 or 0
            item["pridisk"] = string.upper(pridisk) == "YES" and 1 or 0
            local disk_access = disk_access_permission[mac]
            if disk_access ~= nil then
                item.lan = disk_access and 1 or 0
            end
            macfilter[mac] = item
        end
    end
    for _, mac in ipairs(macarry) do
        if macfilter[mac] then
            permissions[mac] = macfilter[mac]
        else
            permissions[mac] = {
                ["wan"] = 1,
                ["lan"] = (disk_access_permission[mac] and 1 or 0),
                ["admin"] = 1,
                ["pridisk"] = 0
            }
        end
    end
    return permissions
end

--[[
@param devName : lan/wan，其他情况 DEVNAME = DEV
]]--
function getWanLanNetworkStatistics(devName)
    local LuciUtil = require("luci.util")
    local tracmd = ""
    if devName == "lan" then
        tracmd = "ubus call trafficd lan"
    elseif devName == "wan" then
        tracmd = "ubus call trafficd wan"
    end
    local statistics = {
        ["upload"] = "0",
        ["upspeed"] = "0",
        ["download"] = "0",
        ["downspeed"] = "0",
        ["devname"] = "",
        ["maxuploadspeed"] = "0",
        ["maxdownloadspeed"] = "0"
    }

    local ubusinfo = LuciUtil.exec(tracmd)
    if XQFunction.isStrNil(ubusinfo) then
        return statistics
    end
    local ubusinfo = Json.decode(ubusinfo)
    if devName == "wan" then
        statistics.devname = tostring(ubusinfo.ifname)
        statistics.upload = tostring(ubusinfo.tx_bytes)
        statistics.download = tostring(ubusinfo.rx_bytes)
        statistics.upspeed = tostring(math.floor(ubusinfo.tx_rate or 0))
        statistics.downspeed = tostring(math.floor(ubusinfo.rx_rate or 0))
        statistics.maxuploadspeed = tostring(math.floor(ubusinfo.max_tx_rate or 0))
        statistics.maxdownloadspeed = tostring(math.floor(ubusinfo.max_rx_rate or 0))

        local history = LuciUtil.exec("ubus call trafficd list_wan_rate")
        if not XQFunction.isStrNil(history) then
            historylist = {}
            history = Json.decode(history)
            for _, rate in ipairs(history.rate) do
                if rate then
                    table.insert(historylist, tostring(rate))
                end
            end
            statistics.history = table.concat(historylist, ",")
        end
    else
        statistics.devname = tostring(ubusinfo.ifname)
        statistics.upload = tostring(ubusinfo.rx_bytes)
        statistics.download = tostring(ubusinfo.tx_bytes)
        statistics.upspeed = tostring(math.floor(ubusinfo.rx_rate or 0))
        statistics.downspeed = tostring(math.floor(ubusinfo.tx_rate or 0))
        statistics.maxuploadspeed = tostring(math.floor(ubusinfo.max_rx_rate or 0))
        statistics.maxdownloadspeed = tostring(math.floor(ubusinfo.max_tx_rate or 0))
    end
    return statistics
end

function skip_master_dev_from_trafficd(device_info,skip_list)
    local LuciUtil = require("luci.util")
    local XQLanWanUtil = require("xiaoqiang.util.XQLanWanUtil")
	local dev_info = {}
	local ret_result = {}
	local skip_dict = {}
	if(skip_list ~= nil) then
		for _,ifname in ipairs(skip_list) do
			skip_dict[ifname] = 1
		end
	end

	if(device_info == nil) then
	    local deviceinfo = LuciUtil.exec("ubus call trafficd hw")

		if XQFunction.isStrNil(device_info) then
			return nil
		else
			dev_info = json.decode(deviceinfo)
		end
	else
		dev_info = device_info
	end
	local gw_ifname = XQLanWanUtil.getDefaultGWDev()
	if(gw_ifname == nil) then
		return nil
	end
	skip_dict[gw_ifname] = 1

	for k,v in pairs(dev_info) do
		if skip_dict[v.ifname] ~= 1 then
			ret_result[k] = v
		end
	end

	return ret_result
end


--[[
@param mac=B8:70:F4:27:0C:1B 网卡mac地址
@param upload=14745         主机当前累计上传数据总量（byte）
@param upspeed=54            主机5秒平均上传速度（byte/s）
@param download=25777       主机当前累计下载数据总量（byte）
@param downspeed=120         主机5秒平均下载速度（byte/s）
@param oneline=169           主机在线时长（秒）
@param devname               设备名
@param maxuploadspeed        上传峰值
@param maxdownloadspeed      下载峰值
]]--
function getDevNetStatisticsList()
    local LuciUtil = require("luci.util")
    local statList = {}
    local dhcpNameDict = getDHCPDict()
    local deviceInfoDict = getDeviceInfoFromDB()

    local deviceinfo = LuciUtil.exec("ubus call trafficd hw")
    if XQFunction.isStrNil(deviceinfo) then
        return statList
    else
        deviceinfo = Json.decode(deviceinfo)
    end
--[[
    local apmode = XQFunction.getNetMode()
    if apmode == "whc_re" then
    	local skip_list = {"eth3","wl01","wl11"}
    	deviceinfo = skip_master_dev_from_trafficd(deviceinfo,skip_list)
    end
]]--
    for key, dev in pairs(deviceinfo) do
        if dev then
            local item = {}
            local mac = XQFunction.macFormat(key)
            local name, nickName, oriName
            if dhcpNameDict[mac] then
                oriName = dhcpNameDict[mac].name
            end
            local device = deviceInfoDict[mac]
            if device then
                if XQFunction.isStrNil(oriName) then
                    oriName = device.oName
                end
                nickName = device.nickname
            end
            local company = XQEquipment.identifyDevice(mac, oriName)
            local dtype = company["type"]
            if not XQFunction.isStrNil(nickName) then
                 name = nickName
            end
            if XQFunction.isStrNil(name) and not XQFunction.isStrNil(dtype.n) then
                name = dtype.n
            end
            if XQFunction.isStrNil(name) and not XQFunction.isStrNil(oriName) then
                name = oriName
            end
            if XQFunction.isStrNil(name) and not XQFunction.isStrNil(company.name) then
                name = company.name
            end
            if XQFunction.isStrNil(name) then
                name = mac
            end

            local tx_bytes, tx_rate, rx_bytes, rx_rate, max_tx_rate, max_rx_rate = 0, 0, 0, 0, 0, 0
            local iplist = dev.ip_list
            if #iplist > 0 then
                for _, ip in ipairs(iplist) do
                    tx_bytes = tx_bytes + ip.tx_bytes or 0
                    rx_bytes = rx_bytes + ip.rx_bytes or 0
                    tx_rate = tx_rate + ip.tx_rate or 0
                    rx_rate = rx_rate + ip.rx_rate or 0
                    max_tx_rate = max_tx_rate + ip.max_tx_rate or 0
                    max_rx_rate = max_rx_rate + ip.max_rx_rate or 0
                end
            end
            item["mac"] = mac
            item["upload"] = tostring(tx_bytes)
            item["upspeed"] = tostring(math.floor(tx_rate))
            item["download"] = tostring(rx_bytes)
            item["downspeed"] = tostring(math.floor(rx_rate))
            item["online"] = tostring(dev.online_timer or 0)
            item["devname"] = name
            -- Add for D01 web show devicelist, mark mesh dev
            item["isap"] = tonumber(dev.is_ap) or 0
            -- Add end

            item["maxuploadspeed"] = tostring(math.floor(max_tx_rate))
            item["maxdownloadspeed"] = tostring(math.floor(max_rx_rate))
            statList[#statList+1] = item
        end
    end
    return statList
end

function get2g5gDeviceCount()
    local LuciUtil = require("luci.util")
    local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
    local XQLanWanUtil = require("xiaoqiang.util.XQLanWanUtil")
    local online_2g, online_5g = 0, 0
    local online_all = 0
    local deviceinfo = LuciUtil.exec("ubus call trafficd hw")
    local UCI = require("luci.model.uci").cursor()
    local ifname_2g = UCI:get("misc", "wireless", "ifname_2G") or ""
    local ifname_5g = UCI:get("misc", "wireless", "ifname_5G") or ""

    if XQFunction.isStrNil(deviceinfo) then
        return 0, 0
    else
        deviceinfo = Json.decode(deviceinfo)
    end

    local lanip = XQLanWanUtil.getLanIp()
    if not XQFunction.isStrNil(lanip) then
        lanip = lanip:gsub(".%d+$","")
    else
        lanip = nil
    end
    for _, item in pairs(deviceinfo) do
        local dev = item.ifname
        if item.ip_list then
            for _, ip in ipairs(item.ip_list) do
                local ignor = false
                if dev ~= "wl1.2" and dev ~= "wl3" and dev ~= "wl14" and lanip and ip.ip then
                    if ip.ip:match("^"..lanip) or ip.ip == "0.0.0.0" then
                        ignor = false
                    else
                        ignor = true
                    end
                end

		--如果是中继设备，也不计入设备统计。
		if ignor == false and not (item.is_ap == nil or item.is_ap == 0) then
		    ignor = true
		end

                if not ignor then
                    if dev:match(ifname_5g) and tonumber(item.assoc) == 1 then
                        online_5g = online_5g + 1
                    end
                    if dev:match(ifname_2g) and tonumber(item.assoc) == 1 then
                        online_2g = online_2g + 1
                    end
		    if ((not dev:match("wl") and tonumber(item.assoc) == 1) or (dev:match("wl") and tonumber(item.assoc) == 1)) then
                        online_all = online_all + 1
		    end
                end
            end
        end
    end
    return online_2g, online_5g, online_all
end

function getDevNetStatisticsDict()
    local statDict = {}
    local statlist = getDevNetStatisticsList()
    for _, item in ipairs(statlist) do
        if item then
            statDict[item.mac] = item
        end
    end
    return statDict
end

function getDeviceCount()
    local LuciUtil = require("luci.util")
    local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
    local XQLanWanUtil = require("xiaoqiang.util.XQLanWanUtil")
    local online, all = 0, 0
    local online_without_mash,all_without_mash = 0, 0
    local deviceinfo = LuciUtil.exec("ubus call trafficd hw")
    if XQFunction.isStrNil(deviceinfo) then
        return 0, 0
    else
        deviceinfo = Json.decode(deviceinfo)
    end
--[[
    local apmode = XQFunction.getNetMode()
    if apmode == "whc_re" then
        local skip_list = {"eth3","wl01","wl11"}
    	deviceinfo = skip_master_dev_from_trafficd(deviceinfo,skip_list)
    end
]]--
    local dbdevlist = XQDBUtil.fetchAllDeviceInfo()
    if dbdevlist then
        for _, item in ipairs(dbdevlist) do
            if item and not deviceinfo[item.mac] and (not XQFunction.isStrNil(item.oName) or not XQFunction.isStrNil(item.nickname)) then
                all = all + 1
                all_without_mash = all_without_mash + 1
            end
        end
    end
    local lanip = XQLanWanUtil.getLanIp()
    if not XQFunction.isStrNil(lanip) then
        lanip = lanip:gsub(".%d+$","")
    else
        lanip = nil
    end
    for _, item in pairs(deviceinfo) do
        local dev = item.ifname
        if item.ip_list then
            for _, ip in ipairs(item.ip_list) do
                local ignor = false
                if dev ~= "wl1.2" and dev ~= "wl3" and dev ~= "wl14" and lanip and ip.ip then
                    if ip.ip:match("^"..lanip) or ip.ip == "0.0.0.0" then
                        ignor = false
                    else
                        ignor = true
                    end
                end
                if not ignor then
                    if (not dev:match("wl") or (item.is_ap == 8 or item.is_ap == 4) or (dev:match("wl") and tonumber(item.assoc) == 1))
                        and ip.ageing_timer <= 300 then
                        online = online + 1
                        if not (item.is_ap == 4 or item.is_ap == 8) then
                        	online_without_mash = online_without_mash + 1
						end
                    end
                    all = all + 1
                    if not (item.is_ap == 4 or item.is_ap == 8) then
                    	all_without_mash = all_without_mash + 1
                    end
                end
            end
        end
    end
    return online, all,online_without_mash,all_without_mash
end

function getConnectDeviceCount()
    local LuciUtil = require("luci.util")
    local count = 0
    local deviceinfo = LuciUtil.exec("ubus call trafficd hw")
    if XQFunction.isStrNil(deviceinfo) then
        return count
    else
        deviceinfo = Json.decode(deviceinfo)
    end
    for _,device in pairs(deviceinfo) do
        if device and device.ip_list and #device.ip_list > 0 then
            local dev = device.ifname
            if not XQFunction.isStrNil(dev) and (tonumber(device.assoc) == 1 or not dev:match("wl")) then
                for _,ip in ipairs(device.ip_list) do
                    if ip.ageing_timer <= 300 and (ip.tx_bytes ~= 0 or ip.rx_bytes ~= 0) then
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

--[[
@return online:      0 (offline) 1 (online)
@return ip:          ip address
@return mac:         mac address
@return type:        wifi/line
@return tag:         1 (normal) 2 (in denylist)
@return port:        1 (2.4G wifi) 2 (5G wifi)
@return name:        name for show
@return origin_name: origin name
@return signal:      wifi signal
@return statistics:
]]--
-- function getConnectDeviceList()
--     local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
--     local XQPushUtil = require("xiaoqiang.util.XQPushUtil")
--     local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
--     local XQEquipment = require("xiaoqiang.XQEquipment")
--     local XQLog = require("xiaoqiang.XQLog")

--     local LuciUtil = require("luci.util")
--     local deviceList = {}

--     local deviceinfo = LuciUtil.exec("ubus call trafficd hw")
--     if XQFunction.isStrNil(deviceinfo) then
--         return deviceList
--     else
--         deviceinfo = Json.decode(deviceinfo)
--     end

--     local diskAccessPermission = {}
--     local macArray = {}
--     local index = 1
--     for k,_ in pairs(deviceinfo) do
--         macArray[index] = k
--         index = index + 1
--     end
--     local payload = {
--         ["api"] = 70,
--         ["macs"] = macArray
--     }
--     local permissionResult = XQFunction.thrift_tunnel_to_datacenter(Json.encode(payload))
--     if permissionResult and permissionResult.code == 0 then
--         index = 1
--         for _,v in pairs(permissionResult.canAccessAllDisk) do
--             diskAccessPermission[macArray[index]] = v
--             index = index + 1
--         end
--     end

--     local macFilterDict = getMacfilterInfoDict()
--     local dhcpDeviceDict = getDHCPDict()
--     local dhcpDevIpDict = getDHCPIpDict()
--     local deviceInfoDict = getDeviceInfoFromDB()
--     local wifiDeviceDict = XQWifiUtil.getAllWifiConnetDeviceDict()
--     local notifyDict = XQPushUtil.notifyDict()

--     for key ,item in pairs(deviceinfo) do
--         if item and item.ip_list and #item.ip_list > 0 then
--             local devicesignal, devicetype, deviceport
--             local dev = item.ifname
--             local mac = XQFunction.macFormat(key)

--             if not XQFunction.isStrNil(dev) and (tonumber(item.assoc) == 1 or not dev:match("wl")) then
--                 -- 信号强度
--                 local signal = wifiDeviceDict[mac]
--                 if signal and signal.signal then
--                     devicesignal = signal.signal
--                 else
--                     devicesignal = ""
--                 end
--                 if dev:match("eth") then
--                     devicetype = "line"
--                     deviceport = 0
--                 elseif dev == "wl0" then
--                     devicetype = "wifi"
--                     deviceport = 2
--                 elseif dev == "wl1" then
--                     devicetype = "wifi"
--                     deviceport = 1
--                 elseif dev == "wl1.2" then
--                     devicetype = "wifi"
--                     deviceport = 3
--                 end

--                 for _,ip in ipairs(item.ip_list) do
--                     if ip.ageing_timer <= 300 and (ip.tx_bytes ~= 0 or ip.rx_bytes ~= 0) then
--                         -- 设备名称
--                         local name, originName, nickName, company
--                         if dhcpDevIpDict[ip.ip] ~= nil then
--                             -- 还原真实MAC地址
--                             mac = dhcpDevIpDict[ip.ip].mac
--                             originName = dhcpDevIpDict[ip.ip].name
--                         end

--                         local push = 0
--                         local mackey = mac:gsub(":", "")
--                         if notifyDict[mackey] then
--                             push = 1
--                         end

--                         if originName and originName:match("^xiaomi%-ir") then -- fix miio model string
--                             originName = originName:gsub("%-",".")
--                         end

--                         -- 访问权限
--                         local authority = {}
--                         if (macFilterDict[mac]) then
--                             authority["wan"] = macFilterDict[mac]["wan"] and 1 or 0
--                             authority["lan"] = macFilterDict[mac]["lan"] and 1 or 0
--                             authority["admin"] = macFilterDict[mac]["admin"] and 1 or 0
--                             authority["pridisk"] = macFilterDict[mac]["pridisk"] and 1 or 0
--                         else
--                             authority["wan"] = 1
--                             authority["lan"] = 1
--                             authority["admin"] = 1
--                             -- private disk deny access default
--                             authority["pridisk"] = 0
--                         end
--                         -- user disk access permission decided by datacenter
--                         if diskAccessPermission[mac] ~= nil then
--                             authority["lan"] = diskAccessPermission[mac] and 1 or 0
--                         end

--                         local deviceInfo = deviceInfoDict[mac]
--                         if deviceInfo then
--                             if XQFunction.isStrNil(originName) then
--                                 originName = deviceInfo.oName
--                             end
--                             nickName = deviceInfo.nickname
--                         end
--                         if not deviceInfo then
--                             XQDBUtil.saveDeviceInfo(mac,originName or "","","","")
--                         end

--                         if not XQFunction.isStrNil(nickName) then
--                             name = nickName
--                         end
--                         company = XQEquipment.identifyDevice(mac, originName)
--                         local dtype = company["type"]
--                         if XQFunction.isStrNil(name) and not XQFunction.isStrNil(dtype.n) then
--                             name = dtype.n
--                         end
--                         if XQFunction.isStrNil(name) and not XQFunction.isStrNil(originName) then
--                             name = originName
--                         end
--                         if XQFunction.isStrNil(name) and not XQFunction.isStrNil(company.name) then
--                             name = company.name
--                         end
--                         if XQFunction.isStrNil(name) then
--                             name = mac
--                         end
--                         if dtype.c == 3 and XQFunction.isStrNil(nickName) then
--                             name = dtype.n
--                         end
--                         local device = {
--                             ["ip"] = ip.ip,
--                             ["mac"] = mac,
--                             ["online"] = 1,
--                             ["type"] = devicetype,
--                             ["port"] = deviceport,
--                             ["ctype"] = dtype.c,
--                             ["ptype"] = dtype.p,
--                             ["origin_name"] = originName or "",
--                             ["name"] = name,
--                             ["push"] = push,
--                             ["company"] = company,
--                             ["authority"] = authority
--                         }
--                         local statistics = {}
--                         statistics["dev"] = dev
--                         statistics["mac"] = mac
--                         statistics["ip"] = ip.ip
--                         statistics["upload"] = tostring(ip.tx_bytes or 0)
--                         statistics["upspeed"] = tostring(math.floor(ip.tx_rate or 0))
--                         statistics["download"] = tostring(ip.rx_bytes or 0)
--                         statistics["downspeed"] = tostring(math.floor(ip.rx_rate or 0))
--                         statistics["online"] = tostring(item.online_timer or 0)
--                         statistics["maxuploadspeed"] = tostring(math.floor(ip.max_tx_rate or 0))
--                         statistics["maxdownloadspeed"] = tostring(math.floor(ip.max_rx_rate or 0))
--                         device["statistics"] = statistics
--                         table.insert(deviceList, device)
--                     end
--                 end
--             end
--         end
--     end
--     -- if #deviceList > 0 then
--     --     table.sort(deviceList,
--     --         function(a, b)
--     --             return b.statistics.onlinets < a.statistics.onlinets
--     --         end
--     --     )
--     -- end
--     return deviceList
-- end

-- function getDevicesInfo(dlist)
--     local XQEquipment = require("xiaoqiang.XQEquipment")
--     local deviceInfoDict = getDeviceInfoFromDB()
--     local flist = {}
--     if dlist and type(dlist) == "table" and #dlist > 0 then
--         for _, mac in ipairs(dlist) do
--             local mac = XQFunction.macFormat(mac)
--             local name, originName, nickName, company
--             local deviceInfo = deviceInfoDict[mac]
--             if deviceInfo then
--                 originName = deviceInfo.oName or ""
--                 nickName = deviceInfo.nickname or ""
--                 if not XQFunction.isStrNil(nickName) then
--                     name = nickName
--                 end
--                 company = XQEquipment.identifyDevice(mac, originName)

--                 local dtype = company["type"]
--                 if XQFunction.isStrNil(name) and not XQFunction.isStrNil(dtype.n) then
--                     name = dtype.n
--                 end
--                 if XQFunction.isStrNil(name) and not XQFunction.isStrNil(originName) then
--                     name = originName
--                 end
--                 if XQFunction.isStrNil(name) and not XQFunction.isStrNil(company.name) then
--                     name = company.name
--                 end
--                 if XQFunction.isStrNil(name) then
--                     name = mac
--                 end
--                 if dtype.c == 3 and XQFunction.isStrNil(nickName) then
--                     name = dtype.n
--                 end
--                 local device = {
--                     ["mac"] = mac,
--                     ["online"] = 0,
--                     ["ctype"] = dtype.c,
--                     ["ptype"] = dtype.p,
--                     ["origin_name"] = originName or "",
--                     ["name"] = name,
--                     ["company"] = company
--                 }
--                 table.insert(flist, device)
--             else
--                 table.insert(flist, {
--                     ["mac"] = mac,
--                     ["online"] = 0,
--                     ["ctype"] = 0,
--                     ["ptype"] = 0,
--                     ["origin_name"] = "",
--                     ["name"] = mac,
--                     ["company"] = {["icon"] = "", ["name"] = ""}
--                 })
--             end
--         end
--     end
--     return flist
-- end

-- function getAllDevices(withbrlan)
--     local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
--     local XQEquipment = require("xiaoqiang.XQEquipment")
--     local XQPushUtil = require("xiaoqiang.util.XQPushUtil")

--     local LuciUtil = require("luci.util")
--     local deviceList = {}

--     local deviceinfo = LuciUtil.exec("ubus call trafficd hw '{\"all\":true}'")
--     if XQFunction.isStrNil(deviceinfo) then
--         return deviceList
--     else
--         deviceinfo = Json.decode(deviceinfo)
--     end

--     local dhcpDevIpDict = getDHCPIpDict()
--     local deviceInfoDict = getDeviceInfoFromDB()
--     local notifyDict = XQPushUtil.notifyDict()

--     for key ,item in pairs(deviceinfo) do
--         local dev = item.ifname
--         if XQFunction.isStrNil(dev) then
--             dev = "wl1"
--         end
--         local mac = XQFunction.macFormat(key)
--         local devicetype, deviceport
--         if dev:match("eth") then
--             devicetype = "line"
--             deviceport = 0
--         elseif dev == "wl0" then
--             devicetype = "wifi"
--             deviceport = 2
--         elseif dev == "wl1" then
--             devicetype = "wifi"
--             deviceport = 1
--         elseif dev == "wl1.2" then
--             devicetype = "wifi"
--             deviceport = 3
--         end

--         if not XQFunction.isStrNil(dev) then
--             for _,ip in ipairs(item.ip_list) do
--                 local name, originName, nickName, company
--                 if dhcpDevIpDict[ip.ip] ~= nil then
--                     mac = dhcpDevIpDict[ip.ip].mac
--                     originName = dhcpDevIpDict[ip.ip].name
--                 end

--                 local push = 0
--                 local mackey = mac:gsub(":", "")
--                 if notifyDict[mackey] then
--                     push = 1
--                 end

--                 if originName and originName:match("^xiaomi%-ir") then -- fix miio model string
--                     originName = originName:gsub("%-",".")
--                 end

--                 local deviceInfo = deviceInfoDict[mac]
--                 if deviceInfo then
--                     if XQFunction.isStrNil(originName) then
--                         originName = deviceInfo.oName
--                     end
--                     nickName = deviceInfo.nickname
--                 end
--                 if not XQFunction.isStrNil(nickName) then
--                     name = nickName
--                 end
--                 company = XQEquipment.identifyDevice(mac, originName)

--                 local dtype = company["type"]
--                 if XQFunction.isStrNil(name) and not XQFunction.isStrNil(dtype.n) then
--                     name = dtype.n
--                 end
--                 if XQFunction.isStrNil(name) and not XQFunction.isStrNil(originName) then
--                     name = originName
--                 end
--                 if XQFunction.isStrNil(name) and not XQFunction.isStrNil(company.name) then
--                     name = company.name
--                 end
--                 if XQFunction.isStrNil(name) then
--                     name = mac
--                 end
--                 if dtype.c == 3 and XQFunction.isStrNil(nickName) then
--                     name = dtype.n
--                 end
--                 local online = 0
--                 if ((not dev:match("wl") and withbrlan) or dev:match("wl")) then
--                     if ip.ageing_timer <= 300 and (ip.tx_bytes ~= 0 or ip.rx_bytes ~= 0) then
--                         online = 1
--                     end
--                     local device = {
--                         ["ip"] = ip.ip,
--                         ["mac"] = mac,
--                         ["online"] = online,
--                         ["type"] = devicetype,
--                         ["port"] = deviceport,
--                         ["ctype"] = dtype.c,
--                         ["ptype"] = dtype.p,
--                         ["origin_name"] = originName or "",
--                         ["name"] = name,
--                         ["push"] = push,
--                         ["company"] = company
--                     }
--                     local statistics = {}
--                     statistics["dev"] = dev
--                     statistics["mac"] = mac
--                     statistics["ip"] = ip.ip
--                     statistics["upload"] = tostring(ip.tx_bytes or 0)
--                     statistics["upspeed"] = tostring(math.floor(ip.tx_rate or 0))
--                     statistics["download"] = tostring(ip.rx_bytes or 0)
--                     statistics["downspeed"] = tostring(math.floor(ip.rx_rate or 0))
--                     statistics["online"] = tostring(item.online_timer or 0)
--                     statistics["maxuploadspeed"] = tostring(math.floor(ip.max_tx_rate or 0))
--                     statistics["maxdownloadspeed"] = tostring(math.floor(ip.max_rx_rate or 0))
--                     device["statistics"] = statistics
--                     table.insert(deviceList, device)
--                 end
--             end
--         end
--     end
--     return deviceList
-- end

-- function getConDevices(withbrlan)
--     local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
--     local XQEquipment = require("xiaoqiang.XQEquipment")
--     local XQPushUtil = require("xiaoqiang.util.XQPushUtil")

--     local LuciUtil = require("luci.util")
--     local deviceList = {}

--     local deviceinfo = LuciUtil.exec("ubus call trafficd hw")
--     if XQFunction.isStrNil(deviceinfo) then
--         return deviceList
--     else
--         deviceinfo = Json.decode(deviceinfo)
--     end

--     local dhcpDevIpDict = getDHCPIpDict()
--     --local dhcpDeviceDict = getDHCPDict()
--     local deviceInfoDict = getDeviceInfoFromDB()
--     local notifyDict = XQPushUtil.notifyDict()

--     for key ,item in pairs(deviceinfo) do
--         if item and item.ip_list and #item.ip_list > 0 then
--             local dev = item.ifname
--             local mac = XQFunction.macFormat(key)

--             local devicetype, deviceport
--             if dev:match("eth") then
--                 devicetype = "line"
--                 deviceport = 0
--             elseif dev == "wl0" then
--                 devicetype = "wifi"
--                 deviceport = 2
--             elseif dev == "wl1" then
--                 devicetype = "wifi"
--                 deviceport = 1
--             elseif dev == "wl1.2" then
--                 devicetype = "wifi"
--                 deviceport = 3
--             end

--             if not XQFunction.isStrNil(dev) and ((not dev:match("wl") and withbrlan) or (dev:match("wl") and tonumber(item.assoc) == 1)) then
--                 for _,ip in ipairs(item.ip_list) do
--                     local name, originName, nickName, company
--                     if dhcpDevIpDict[ip.ip] ~= nil then
--                         mac = dhcpDevIpDict[ip.ip].mac
--                         originName = dhcpDevIpDict[ip.ip].name
--                     end

--                     local push = 0
--                     local mackey = mac:gsub(":", "")
--                     if notifyDict[mackey] then
--                         push = 1
--                     end

--                     local deviceInfo = deviceInfoDict[mac]
--                     if deviceInfo then
--                         if XQFunction.isStrNil(originName) then
--                             originName = deviceInfo.oName
--                         end
--                         nickName = deviceInfo.nickname
--                     end
--                     if not XQFunction.isStrNil(nickName) then
--                         name = nickName
--                     end
--                     company = XQEquipment.identifyDevice(mac, originName)

--                     local dtype = company["type"]
--                     if XQFunction.isStrNil(name) and not XQFunction.isStrNil(dtype.n) then
--                         name = dtype.n
--                     end
--                     if XQFunction.isStrNil(name) and not XQFunction.isStrNil(originName) then
--                         name = originName
--                     end
--                     if XQFunction.isStrNil(name) and not XQFunction.isStrNil(company.name) then
--                         name = company.name
--                     end
--                     if XQFunction.isStrNil(name) then
--                         name = mac
--                     end
--                     if dtype.c == 3 and XQFunction.isStrNil(nickName) then
--                         name = dtype.n
--                     end
--                     if ip.ageing_timer <= 300 and (ip.tx_bytes ~= 0 or ip.rx_bytes ~= 0) then
--                         local device = {
--                             ["ip"] = ip.ip,
--                             ["mac"] = mac,
--                             ["online"] = 1,
--                             ["type"] = devicetype,
--                             ["port"] = deviceport,
--                             ["ctype"] = dtype.c,
--                             ["ptype"] = dtype.p,
--                             ["origin_name"] = originName or "",
--                             ["name"] = name,
--                             ["push"] = push,
--                             ["company"] = company
--                         }
--                         local statistics = {}
--                         statistics["dev"] = dev
--                         statistics["mac"] = mac
--                         statistics["ip"] = ip.ip
--                         statistics["upload"] = tostring(ip.tx_bytes or 0)
--                         statistics["upspeed"] = tostring(math.floor(ip.tx_rate or 0))
--                         statistics["download"] = tostring(ip.rx_bytes or 0)
--                         statistics["downspeed"] = tostring(math.floor(ip.rx_rate or 0))
--                         statistics["online"] = tostring(item.online_timer or 0)
--                         statistics["maxuploadspeed"] = tostring(math.floor(ip.max_tx_rate or 0))
--                         statistics["maxdownloadspeed"] = tostring(math.floor(ip.max_rx_rate or 0))
--                         device["statistics"] = statistics
--                         table.insert(deviceList, device)
--                     end
--                 end
--             end
--         end
--     end
--     return deviceList
-- end

function getSpecialDevCount()
    local XQEquipment = require("xiaoqiang.XQEquipment")
    local devcount = {
        ["mitv"] = 0,
        ["mibox"] = 0
    }
    local deviceinfo = getDeviceInfoFromDB()
    for key ,item in pairs(deviceinfo) do
        if item and not XQFunction.isStrNil(item.oName) then
            local mac = XQFunction.macFormat(key)
            local dhcpname = item.oName
            if dhcpname:match("^mitv") then
                devcount.mitv = devcount.mitv + 1
            end
            if dhcpname:match("^mibox") then
                devcount.mibox = devcount.mibox + 1
            end
        end
    end
    return devcount
end

function getDeviceInfo(mac, withpermission)
    local deviceinfo = {
        ["flag"] = 0,
        ["name"] = "",
        ["mac"] = "",
        ["dhcpname"] = "",
        ["type"] = {["c"] = 0, ["p"] = 0, ["n"] = ""}
    }
    if XQFunction.isStrNil(mac) then
        return deviceinfo
    else
        mac = XQFunction.macFormat(mac)
    end
    local XQEquipment = require("xiaoqiang.XQEquipment")
    local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
    local dhcpinfo = getDHCPDict()[mac]
    local device = XQDBUtil.fetchDeviceInfo(mac)
    local name, originName, nickName, company
    if dhcpinfo and dhcpinfo.name then
        originName = dhcpinfo.name
    end
    if device then
        if not XQFunction.isStrNil(device.mac) then
            deviceinfo.flag = 1
        end
        if not XQFunction.isStrNil(device.nickname) then
            nickName = device.nickname
            name = nickName
        end
        if not XQFunction.isStrNil(device.oName) and XQFunction.isStrNil(originName) then
            originName = device.oName
        end
    end
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
    local confinfo = fetchDeviceInfoFromConfig(mac)
    deviceinfo["mac"] = mac
    deviceinfo["name"] = name
    deviceinfo["owner"] = confinfo.owner or ""
    deviceinfo["device"] = confinfo.device or ""
    deviceinfo["dhcpname"] = originName or ""
    deviceinfo["type"] = dtype
    if withpermission then
        local XQPushUtil = require("xiaoqiang.util.XQPushUtil")
        local macFilterDict = getMacfilterInfoDict()
        local datacenterdata
        local payload = {
            ["api"] = 70,
            ["macs"] = {mac}
        }
        local permissionResult = XQFunction.thrift_tunnel_to_datacenter(Json.encode(payload))
        if permissionResult and permissionResult.code == 0 then
            datacenterdata = permissionResult.canAccessAllDisk[1]
        end
        -- 访问权限
        local authority = {}
        if (macFilterDict[mac]) then
            authority["wan"] = macFilterDict[mac]["wan"] and 1 or 0
            authority["lan"] = macFilterDict[mac]["lan"] and 1 or 0
            authority["admin"] = macFilterDict[mac]["admin"] and 1 or 0
            authority["pridisk"] = macFilterDict[mac]["pridisk"] and 1 or 0
        else
            authority["wan"] = 1
            authority["lan"] = 1
            authority["admin"] = 1
            -- private disk deny access default
            authority["pridisk"] = 0
        end
        -- user disk access permission decided by datacenter
        if datacenterdata ~= nil then
            authority["lan"] = datacenterdata and 1 or 0
        end
        local notifyDict = XQPushUtil.notifyDict()
        local push = 0
        local mackey = mac:gsub(":", "")
        if notifyDict[mackey] then
            push = 1
        end
        local times = XQPushUtil.getAuthenFailedTimes(mac) or 0
        deviceinfo["push"] = push
        deviceinfo["times"] = times
        deviceinfo["authority"] = authority
    end
    return deviceinfo
end

-- online    : true/false (online/all)
-- withbrlan : true/false (wifi+lan/wifi)
function getDeviceList(online, withbrlan)
    local LuciDatatypes = require("luci.cbi.datatypes")
    local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
    local XQEquipment = require("xiaoqiang.XQEquipment")
    local XQPushUtil = require("xiaoqiang.util.XQPushUtil")
    local XQLanWanUtil = require("xiaoqiang.util.XQLanWanUtil")

    local LuciUtil = require("luci.util")
    local deviceList = {}
    local cmd = "ubus call trafficd hw"
    local deviceinfo = LuciUtil.exec(cmd)
    if XQFunction.isStrNil(deviceinfo) then
        return deviceList
    else
        deviceinfo = Json.decode(deviceinfo)
    end

    local lanip = XQLanWanUtil.getLanIp()
    if not XQFunction.isStrNil(lanip) then
        lanip = lanip:gsub(".%d+$","")
    else
        lanip = nil
    end

    local macFilterDict = getMacfilterInfoDict()
    local dhcpDevIpDict = getDHCPIpDict()
    local deviceInfoDict = getDeviceInfoFromDB()
    local notifyDict = XQPushUtil.notifyDict()
    local pushDict = XQPushUtil.getAuthenFailedTimesDict()


    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
    local macfilter = XQWifiUtil.getWiFiMacfilterModel()
    if macfilter == 1 then
        local wifilist = XQWifiUtil.getCurrentMacfilterList()
        if wifilist then
            for _, value in ipairs(wifilist) do
                if not deviceinfo[value] then
                    local item = {
                        ["hw"] = value,
                        ["ifname"] = "wl1",
                        ["assoc"] = 0,
                        ["ip_list"] = {
                            {
                                ["ip"] = "0.0.0.0",
                                ["hw"] = value,
                                ["ageing_timer"] = 400,
                                ["rx_bytes"] = 0,
                                ["tx_bytes"] = 0,
                                ["rx_rate"] = 0,
                                ["tx_rate"] = 0,
                                ["max_rx_rate"] = 0,
                                ["max_tx_rate"] = 0
                            }
                        }
                    }
                    deviceinfo[value] = item
                end
            end
        end
    end

    if not online and deviceInfoDict then
        for key, item in pairs(deviceInfoDict) do
            if not deviceinfo[key] and (not XQFunction.isStrNil(item.oName) or not XQFunction.isStrNil(item.nickname)) then
                local item = {
                    ["hw"] = key,
                    ["ifname"] = "wl1",
                    ["assoc"] = 0,
                    ["ip_list"] = {
                        {
                            ["ip"] = "0.0.0.0",
                            ["hw"] = key,
                            ["ageing_timer"] = 400,
                            ["rx_bytes"] = 0,
                            ["tx_bytes"] = 0,
                            ["rx_rate"] = 0,
                            ["tx_rate"] = 0,
                            ["max_rx_rate"] = 0,
                            ["max_tx_rate"] = 0
                        }
                    }
                }
                deviceinfo[key] = item
            end
        end
    end

    -- read guest iface-name
    local uci = require("luci.model.uci").cursor()
    local wifi_2g_ifname = uci:get("misc","wireless","iface_2g_ifname") or ""
    local wifi_5g_ifname = uci:get("misc","wireless","iface_5g_ifname") or ""
    local guest_2g_ifname = uci:get("misc","wireless","iface_guest_2g_ifname") or ""
    local guest_5g_ifname = uci:get("misc","wireless","iface_guest_5g_ifname") or ""

    for key ,item in pairs(deviceinfo) do
        local devflag = 1
        local dev = item.ifname
        if XQFunction.isStrNil(dev) and not online then
            devflag = 0
            dev = "wl1"
        end
        local mac = XQFunction.macFormat(key)
        local devicetype, deviceport
        if dev:match("eth") then
            devicetype = "line"
            deviceport = 0
	elseif dev == "" then
	    dev = "eth"
	    devicetype = "line"
	    deviceport = 0
        elseif dev == wifi_5g_ifname then
            devicetype = "wifi"
            deviceport = 2
        elseif dev == wifi_2g_ifname then
            devicetype = "wifi"
            deviceport = 1
        elseif dev == guest_2g_ifname or dev == guest_5g_ifname then
            devicetype = "wifi"
            deviceport = 3
        end

        if not XQFunction.isStrNil(dev) then
            local multiip, added, devonline = false, false, false
            multiip = #item.ip_list > 1
            for _, ip in ipairs(item.ip_list) do
                if (tonumber(item.assoc) == 1) then
                    devonline = true
                end
            end
            for _, ip in ipairs(item.ip_list) do
                local name, originName, nickName, company
                if dhcpDevIpDict[ip.ip] ~= nil then
                    -- mac = dhcpDevIpDict[ip.ip].mac
                    originName = dhcpDevIpDict[ip.ip].name
                end

                local push, times = 0, 0
                local mackey = mac:gsub(":", "")
                if notifyDict[mackey] then
                    push = 1
                end
                times = tonumber(pushDict[mackey]) or 0

                local deviceInfo = deviceInfoDict[mac]
                if deviceInfo then
                    if XQFunction.isStrNil(originName) then
                        originName = deviceInfo.oName
                    end
                    nickName = deviceInfo.nickname
                end
                if not XQFunction.isStrNil(nickName) then
                    name = nickName
                end
                if not deviceInfo then
                    XQDBUtil.saveDeviceInfo(mac,originName or "","","","")
                end
                company = XQEquipment.identifyDevice(mac, originName)

                -- 访问权限
                local authority = {}
                if (macFilterDict[mac]) then
                    authority["wan"] = macFilterDict[mac]["wan"] and 1 or 0
                    authority["lan"] = macFilterDict[mac]["lan"] and 1 or 0
                    authority["admin"] = macFilterDict[mac]["admin"] and 1 or 0
                    authority["pridisk"] = macFilterDict[mac]["pridisk"] and 1 or 0
                else
                    authority["wan"] = 1
                    authority["lan"] = 1
                    authority["admin"] = 1
                    -- private disk deny access default
                    authority["pridisk"] = 0
                end

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
                local onlineflag = 0
                local ignor = false
                if dev ~= "wl1.2" and dev ~= "wl3" and dev ~= "wl14" and lanip and ip.ip then
                    if ip.ip:match("^"..lanip) or ip.ip == "0.0.0.0" then
                        ignor = false
                    else
                        ignor = true
                    end
                end
                if ((not dev:match("wl") and withbrlan) or dev:match("wl")) and not ignor then
                    if ( tonumber(item.assoc) == 1) then
                        onlineflag = 1
                        if devflag == 0 then
                            onlineflag = 0
                        end
                    end
                    local parent = item.parent or ""
                    if not XQFunction.isStrNil(parent) then
                        devicetype = "ap"
                    end
                    local device = {
                        ["ip"] = ip.ip,
                        ["mac"] = mac,
                        ["online"] = onlineflag,
                        ["type"] = devicetype,
                        ["port"] = deviceport,
                        ["ctype"] = dtype.c,
                        ["ptype"] = dtype.p,
                        ["origin_name"] = originName or "",
                        ["name"] = name,
                        ["push"] = push,
                        ["company"] = company,
                        ["times"] = times,
                        ["authority"] = authority,
                        ["parent"] = parent,
                        ["isap"] = tonumber(item.is_ap) or 0,
                        ["hostname"] = item.hostname or ""
                    }
                    local statistics = {}
                    statistics["dev"] = dev
                    statistics["mac"] = mac
                    statistics["ip"] = ip.ip
                    statistics["upload"] = tostring(ip.tx_bytes or 0)
                    statistics["upspeed"] = tostring(math.floor(ip.tx_rate or 0))
                    statistics["download"] = tostring(ip.rx_bytes or 0)
                    statistics["downspeed"] = tostring(math.floor(ip.rx_rate or 0))
                    statistics["online"] = tostring(item.online_timer or 0)
                    statistics["maxuploadspeed"] = tostring(math.floor(ip.max_tx_rate or 0))
                    statistics["maxdownloadspeed"] = tostring(math.floor(ip.max_rx_rate or 0))
                    device["statistics"] = statistics
                    if online and onlineflag == 1 then
                        table.insert(deviceList, device)
                    elseif not online then
                        if multiip and devonline and onlineflag == 1 then
                            table.insert(deviceList, device)
                        elseif multiip and not devonline and onlineflag ~= 1 and not added then
                            table.insert(deviceList, device)
                            added = true
                        elseif not multiip then
                            table.insert(deviceList, device)
                        end
                    end
                end
            end
        end
    end
    return deviceList
end

function devicelistForMAgent()
    local LuciUtil = require("luci.util")
    local XQPushUtil = require("xiaoqiang.util.XQPushUtil")
    local XQLanWanUtil = require("xiaoqiang.util.XQLanWanUtil")
    local deviceList = {}
    local ubuscall = "ubus call trafficd hw"
    local deviceinfo = LuciUtil.exec(ubuscall)
    if XQFunction.isStrNil(deviceinfo) then
        return deviceList
    else
        deviceinfo = Json.decode(deviceinfo)
    end

    local lanip = XQLanWanUtil.getLanIp()
    if not XQFunction.isStrNil(lanip) then
        lanip = lanip:gsub(".%d+$","")
    else
        lanip = nil
    end

    local macFilterDict = getMacfilterInfoDict()
    local dhcpDevIpDict = getDHCPIpDict()
    local deviceInfoDict = getDeviceInfoFromDB()
    local notifyDict = XQPushUtil.notifyDict()
    local pushDict = XQPushUtil.getAuthenFailedTimesDict()

    local diskAccessPermission = {}
    local macArray = {}
    local index = 1
    for k,_ in pairs(deviceinfo) do
        macArray[index] = k
        index = index + 1
    end
    for k,_ in pairs(deviceInfoDict) do
        if LuciDatatypes.macaddr(k) and not deviceinfo[k] then
            table.insert(macArray, k)
        end
    end
    local payload = {
        ["api"] = 70,
        ["macs"] = macArray
    }
    local permissionResult = XQFunction.thrift_tunnel_to_datacenter(Json.encode(payload))
    if permissionResult and permissionResult.code == 0 then
        index = 1
        for _,v in pairs(permissionResult.canAccessAllDisk) do
            diskAccessPermission[macArray[index]] = v
            index = index + 1
        end
    end

    -- read guest iface-name
    local uci = require("luci.model.uci").cursor()
    local wifi_2g_ifname = uci:get("misc","wireless","iface_2g_ifname") or ""
    local wifi_5g_ifname = uci:get("misc","wireless","iface_5g_ifname") or ""
    local guest_2g_ifname = uci:get("misc","wireless","iface_guest_2g_ifname") or ""
    local guest_5g_ifname = uci:get("misc","wireless","iface_guest_5g_ifname") or ""

    for key ,item in pairs(deviceinfo) do
        local dev = item.ifname
        if not XQFunction.isStrNil(dev) then
            local mac = XQFunction.macFormat(key)
            local devicetype, deviceport
            local parent = item.parent or ""
            if dev:match("eth") then
                devicetype = "line"
                deviceport = 0
            elseif dev == wifi_5g_ifname then
                devicetype = "wifi"
                deviceport = 2
            elseif dev == wifi_2g_ifname then
                devicetype = "wifi"
                deviceport = 1
            elseif dev == guest_2g_ifname or dev == guest_5g_ifname then
                devicetype = "wifi"
                deviceport = 3
            end
            if not XQFunction.isStrNil(parent) then
                devicetype = "ap"
                deviceport = 4
            end

            -- Basic info
            local originName, nickName
            local deviceInfo = deviceInfoDict[mac]
            if deviceInfo then
                originName = deviceInfo.oName or ""
                nickName = deviceInfo.nickname or ""
            end
            -- Push
            local push, times = 0, 0
            local mackey = mac:gsub(":", "")
            if notifyDict[mackey] then
                push = 1
            end
            times = tonumber(pushDict[mackey]) or 0
            -- Authority
            local authority = {}
            if (macFilterDict[mac]) then
                authority["wan"] = macFilterDict[mac]["wan"] and 1 or 0
                authority["lan"] = macFilterDict[mac]["lan"] and 1 or 0
                authority["admin"] = macFilterDict[mac]["admin"] and 1 or 0
                authority["pridisk"] = macFilterDict[mac]["pridisk"] and 1 or 0
            else
                authority["wan"] = 1
                authority["lan"] = 1
                authority["admin"] = 1
                -- private disk deny access default
                authority["pridisk"] = 0
            end
            -- user disk access permission decided by datacenter
            if diskAccessPermission[mac] ~= nil then
                authority["lan"] = diskAccessPermission[mac] and 1 or 0
            end
            for _, ip in ipairs(item.ip_list) do
                if dev ~= "wl1.2" and dev ~= "wl3" and dev ~= "wl14" and lanip and ip.ip then
                    if ip.ip:match("^"..lanip) then
                        ignor = false
                    else
                        ignor = true
                    end
                end
                if (not dev:match("wl") or (dev:match("wl") and tonumber(item.assoc) == 1))
		    --部分型号去掉了ipaccount,无法统计流量信息.
                    --and ip.ageing_timer <= 300 and (ip.tx_bytes ~= 0 or ip.rx_bytes ~= 0)
                    and ip.ageing_timer <= 300
                    and not ignor then
                    -- DHCP lease
                    if dhcpDevIpDict[ip.ip] then
                        if XQFunction.isStrNil(dhcpDevIpDict[ip.ip].name) then
                            originName = dhcpDevIpDict[ip.ip].name
                        end
                    end
                    local device = {
                        ["ip"] = ip.ip,
                        ["mac"] = mac,
                        ["dhcp"] = originName,
                        ["data"] = {
                            ["nickname"] = nickName,
                            ["type"] = devicetype,
                            ["port"] = deviceport,
                            ["push"] = push,
                            ["times"] = times,
                            ["authority"] = authority,
                            ["parent"] = parent,
                            ["isap"] = tonumber(item.is_ap) or 0,
                            ["hostname"] = item.hostname or "",
                            ["statistics"] = {
                                ["upload"] = tostring(ip.tx_bytes or 0),
                                ["upspeed"] = tostring(math.floor(ip.tx_rate or 0)),
                                ["download"] = tostring(ip.rx_bytes or 0),
                                ["downspeed"] = tostring(math.floor(ip.rx_rate or 0)),
                                ["online"] = tostring(item.online_timer or 0),
                                ["maxuploadspeed"] = tostring(math.floor(ip.max_tx_rate or 0)),
                                ["maxdownloadspeed"] = tostring(math.floor(ip.max_rx_rate or 0))
                            }
                        }
                    }
                    table.insert(deviceList, device)
                end
            end
        end
    end
    return deviceList
end

-- online    : true/false (online/all)
-- withbrlan : true/false (wifi+lan/wifi)
function getDeviceListV2(online, withbrlan)
    local LuciUtil = require("luci.util")
    local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
    local XQEquipment = require("xiaoqiang.XQEquipment")
    local XQPushUtil = require("xiaoqiang.util.XQPushUtil")
    local XQLanWanUtil = require("xiaoqiang.util.XQLanWanUtil")
    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")

    local deviceList = {}
    local ubuscall = "ubus call trafficd hw"
    local deviceinfo = LuciUtil.exec(ubuscall)
    if XQFunction.isStrNil(deviceinfo) then
        return deviceList
    else
        deviceinfo = Json.decode(deviceinfo)
    end

    local lanip = XQLanWanUtil.getLanIp()
    if not XQFunction.isStrNil(lanip) then
        lanip = lanip:gsub(".%d+$","")
    else
        lanip = nil
    end

    local macFilterDict = getMacfilterInfoDict()
    local dhcpDevDict = getDHCPDict()
    local deviceInfoDict = getDeviceInfoFromDB()
    local notifyDict = XQPushUtil.notifyDict()
    local pushDict = XQPushUtil.getAuthenFailedTimesDict()


    if not online and deviceInfoDict then
        for key, item in pairs(deviceInfoDict) do
            if not deviceinfo[key] and (not XQFunction.isStrNil(item.oName) or not XQFunction.isStrNil(item.nickname)) then
                local item = {
                    ["hw"] = key,
                    ["ifname"] = "wl1",
                    ["assoc"] = 0,
                    ["ip_list"] = {
                        {
                            ["ip"] = "0.0.0.0",
                            ["hw"] = key,
                            ["ageing_timer"] = 400,
                            ["rx_bytes"] = 0,
                            ["tx_bytes"] = 0,
                            ["rx_rate"] = 0,
                            ["tx_rate"] = 0,
                            ["max_rx_rate"] = 0,
                            ["max_tx_rate"] = 0
                        }
                    }
                }
                deviceinfo[key] = item
            end
        end
    end
    -- 0/1/2/3  line/wifi2.4/wifi5/guest wifi
    for key ,item in pairs(deviceinfo) do
        local mac = XQFunction.macFormat(key)
        local dev = item.ifname
        local devicetype = 0
        if dev:match("eth") then
            devicetype = 0
        elseif dev == "wl0" then
            devicetype = 2
        elseif dev == "wl1" then
            devicetype = 1
        elseif dev == "wl1.2" then
            devicetype = 3
        elseif dev == "wl3" then
            devicetype = 3
        elseif dev == "wl14" then
            devicetype = 3
        elseif dev == "" then
        	devicetype = 0
        end

        if (not withbrlan and devicetype ~= 0) or withbrlan then
            local device = {}
            -- 设备是否在线(有一个ip活跃那么设备就是在线的)
            local devonline = false
            for _, ip in ipairs(item.ip_list) do
                if (tonumber(item.assoc) == 1) then
                    devonline = true
                    break
                end
            end
            device["mac"] = mac
            device["online"] = devonline and 1 or 0
            device["type"] = devicetype
            device["isap"] = tonumber(item.is_ap) or 0
            device["parent"] = item.parent or ""

            -- 基本信息
            local name, originName, nickName, company
            if dhcpDevDict[mac] ~= nil then
                originName = dhcpDevDict[mac].name
            end
            local deviceInfo = deviceInfoDict[mac]
            if deviceInfo then
                if XQFunction.isStrNil(originName) then
                    originName = deviceInfo.oName
                end
                nickName = deviceInfo.nickname
            end
            if not XQFunction.isStrNil(nickName) then
                name = nickName
            end
            if not deviceInfo then
                XQDBUtil.saveDeviceInfo(mac,originName or "","","","")
            end
            company = XQEquipment.identifyDevice(mac, originName)
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
            device["name"] = name or ""
            device["oname"] = originName or ""
            device["icon"] = company.icon or ""

            -- 设备上线提醒开关，防蹭网次数
            local push, times = 0, 0
            local mackey = mac:gsub(":", "")
            if notifyDict[mackey] then
                push = 1
            end
            times = tonumber(pushDict[mackey]) or 0
            device["push"] = push
            device["times"] = times

            -- 访问权限
            local authority = {}
            if (macFilterDict[mac]) then
                authority["wan"] = macFilterDict[mac]["wan"] and 1 or 0
                authority["lan"] = macFilterDict[mac]["lan"] and 1 or 0
                authority["admin"] = macFilterDict[mac]["admin"] and 1 or 0
                authority["pridisk"] = macFilterDict[mac]["pridisk"] and 1 or 0
            else
                authority["wan"] = 1
                authority["lan"] = 1
                authority["admin"] = 1
                authority["pridisk"] = 0
            end

            device["authority"] = authority

            -- 设备使用的IP信息
            local iplist = {}
            local statistics = {}
            for _, ip in ipairs(item.ip_list) do
                local ignor = false
                if dev ~= "wl1.2" and dev ~= "wl3" and dev ~= "wl14" and lanip and ip.ip then
                    if ip.ip:match("^"..lanip) or ip.ip == "0.0.0.0" then
                        ignor = false
                    else
                        ignor = true
                    end
                end
                if not ignor then
                    local active = 0
                    if (tonumber(item.assoc) == 1) then
                        active = 1
                    end
                    local ipinfo = {
                        ["ip"] = ip.ip,
                        ["active"] = active,
                        ["upspeed"] = tostring(math.floor(ip.tx_rate or 0)),
                        ["downspeed"] = tostring(math.floor(ip.rx_rate or 0)),
                        ["online"] = tostring(item.online_timer or 0)
                    }
                    if active == 1 or not online then
                        table.insert(iplist, ipinfo)
                        if not statistics["online"] then
                            statistics["online"] = ipinfo.online
                        end
                        statistics["upspeed"] = tostring(tonumber(statistics["upspeed"] or 0) + tonumber(ipinfo.upspeed))
                        statistics["downspeed"] = tostring(tonumber(statistics["downspeed"] or 0) + tonumber(ipinfo.downspeed))
                    end
                end
            end
            device["ip"] = iplist
            device["statistics"] = statistics
            if (devonline and online) or not online then
                table.insert(deviceList, device)
            end
        end
    end
    return deviceList
end

function devicesInfo()
    local LuciDatatypes = require("luci.cbi.datatypes")
    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
    local XQPushUtil = require("xiaoqiang.util.XQPushUtil")
    local XQParentControl = require("xiaoqiang.module.XQParentControl")
    local info = {}
    local macarr = {}
    local macdic = {}
    local permission = {}
    local notifyDict = XQPushUtil.notifyDict()
    local deviceInfoDict = getDeviceInfoFromDB()
    local macFilterDict = getMacfilterInfoDict()
    local configDeviceinfo = getDeviceInfoFromConfig()
    local macfiltermode = XQWifiUtil.getWiFiMacfilterModel()
    local wifimacfilter = {}
    if macfiltermode == 1 then
        local mlist = XQWifiUtil.getCurrentMacfilterList()
        if mlist then
            for _, mac in ipairs(mlist) do
                wifimacfilter[mac] = 1
            end
        end
    end
    for mac, item in pairs(deviceInfoDict) do
        if LuciDatatypes.macaddr(mac) then
            info[mac] = {["nickname"] = item.nickname or ""}
            macdic[mac] = 1
            table.insert(macarr, mac)
        end
    end
    local payload = {
        ["api"] = 70,
        ["macs"] = macarr
    }
    local permissionResult = XQFunction.thrift_tunnel_to_datacenter(Json.encode(payload))
    if permissionResult and permissionResult.code == 0 then
        permission = permissionResult.canAccessAllDisk
    end
    local pcontrols = XQParentControl.parentctl_rules(macdic)
    local ncontrols = XQParentControl.netacctl_status(macdic)
    local ucontrols = XQParentControl.get_urlfilter_info(macdic)
    local result = {}
    for mac, item in pairs(info) do
        local filter = macFilterDict[mac]
        local configinfo = configDeviceinfo[mac]
        if notifyDict[mac] then
            item["push"] = 1
        else
            item["push"] = 0
        end
        item["pcontrol"] = pcontrols[mac]
        item["netacctl"] = ncontrols[mac]
        item["urlfilter"] = ucontrols[mac]
        if filter then
            item["wan"] = filter["wan"] and 1 or 0
            item["lan"] = filter["lan"] and 1 or 0
            item["admin"] = filter["admin"] and 1 or 0
            item["pridisk"] = filter["pridisk"] and 1 or 0
        else
            item["wan"] = 1
            item["lan"] = 1
            item["admin"] = 1
            item["pridisk"] = 0
        end
        if wifimacfilter[mac] == 1 then
            item["limited"] = 1
        else
            item["limited"] = 0
        end
        if configinfo then
            item["owner"] = configinfo.owner or ""
            item["device"] = configinfo.device or ""
        else
            item["owner"] = ""
            item["device"] = ""
        end
        if permission[mac] ~= nil then
            item["lan"] = permission[mac] and 1 or 0
        end
        result["device/"..mac] = item
    end
    return result
end

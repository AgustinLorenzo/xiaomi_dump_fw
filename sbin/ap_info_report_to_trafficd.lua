#!/usr/bin/lua
local json = require("cjson")
local uci = require("luci.model.uci").cursor()
local model = uci:get("xiaoqiang","common","NETMODE") or "router"
local mac_cmd
local ap_flag = nil 
local pp
local data
local hw

function get_description()
	local sys = require("xiaoqiang.util.XQSysUtil")
	return sys.getRouterInfo4Trafficd()
end

function get_version()
	local sys = require("xiaoqiang.util.XQSysUtil")
	return sys.getRomVersion()
end

function get_routername()
    local name = uci:get("xiaoqiang","common","ROUTER_NAME") or ""
    return name
end

function get_deviceid()
    local device_id = uci:get("messaging","deviceInfo","DEVICE_ID")
    return device_id
end

function get_iwinfo_device()
    local LuciUtil = require("luci.util")
    local guest_wifi_ifname = uci:get("misc","modules","guestwifi")
    local ifname_list = {"wl0","wl1",guest_wifi_ifname}
    local ret = {}
    for _,ifname in ipairs(ifname_list) do
    	local tmp = {}
    	tmp["dev"] = ifname
    	tmp["list"] = {}
	local jsonStr = LuciUtil.trim(LuciUtil.exec("iwinfo " .. ifname .." assoclist |sed '1,7'd|awk '{print $1;}'"))
	local lines = LuciUtil.split(jsonStr or "","\n")
	tmp["list"] = lines
	table.insert(ret,tmp)
    end
    return ret
end

function get_br_eth_device()
    local brutil = require("xiaoqiang.util.XQBrUtil")
    local br_macs = brutil.get_macs("br-lan")
    local tmp = {}
    tmp["dev"] = "eth0"
    tmp["list"] = {}
    for _,item in ipairs(br_macs) do
	if (item.is_local == "no") and (item.dev:match("eth")) then
	    table.insert(tmp["list"],item.mac)
	end
    end
    return tmp
end
if(model == "router") then
	return 0
end
    
if model == "lanapmode" then
	mac_cmd = "ifconfig br-lan | grep HWaddr"
	ap_flag = 2
elseif model == "wifiapmode" then
	local apcli_ifname = uci:get("xiaoqiang","common","active_apclii0") or ""
	mac_cmd = "ifconfig "..apcli_ifname.." | grep HWaddr"
	ap_flag = 1
else 
	mac_cmd = "ifconfig br-lan | grep HWaddr"
	ap_flag = 8
end

pp = io.popen(mac_cmd)
data = pp:read("*line")
hw = string.find(data,'HWaddr%s+([0-9A-F:]+)%s*$')
pp:close()

	
local tbus_message = {}
if(ap_flag == nil) then
    return nil
end

tbus_message["hw"] = hw
tbus_message["ap_flags"] = ap_flag
tbus_message["version"] = get_version() or ""
tbus_message["router_name"] = get_routername()
tbus_message["device_id"] = get_deviceid()
tbus_message["description"] = get_description()
tbus_message["dev_sync"] = get_iwinfo_device()
if ap_flag == 1 then
    eth_tmp = get_br_eth_device()
    table.insert(tbus_message["dev_sync"],eth_tmp)
end

print("tbus_message:"..json.encode(tbus_message));

router_ip = uci:get("network","lan","gateway")

cmd = "tbus -h "..router_ip.." -p 784 send trafficd '"..json.encode(tbus_message).."'"
print(cmd)

os.execute(cmd)

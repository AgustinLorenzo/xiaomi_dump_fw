module ("xiaoqiang.util.XQBrUtil", package.seeall)
local util=require("luci.util")
local json=require("cjson")
function get_macs(br_dev)
	local file_name = [[/sys/class/net/]]..br_dev..[[/brif]]
	local file = io.open(file_name)
	if file == nil then
		return nil
	end
	file:close()
	local port_map = get_port_map(br_dev)
	if br_dev == nil then
		return nil
	end
	local cmd = [[cat /sys/class/net/]]..br_dev..[[/brforward > /tmp/brforward_tmp;hexdump -v -e '5/1 "%02x:" /1 "%02x" /1 " %x" /1 " %x" 1/4 " %i" 1/4 "\n"' /tmp/brforward_tmp  | awk '{ islocal = $3 ? "yes" : "no" ; printf "%i;%s;%s;%8.2f\n",$2,$1,islocal,$4/100 } ' ;]]
	macs_table = util.execl(cmd)
	local items = {}
	for _,line in ipairs(macs_table) do
		local item = {}
		fields = util.split(line,";")
		item["no"] = fields[1]
		item["dev"] = port_map[tonumber(item.no)]
		item["mac"] = fields[2]
		item["is_local"] = fields[3]
		item["ageing"] = util.trim(fields[4])
		--print(json.encode(item))
		table.insert(items,item)
	end
	--print(json.encode(items))
	return items
end


function get_port_map(br_dev)
	local port_num = {}
	local cmd = [[ls /sys/class/net/]]..br_dev..[[/brif]]
	files = util.execl(cmd)
	for _,ifname in ipairs(files) do
		local file_name = [[/sys/class/net/]]..br_dev..[[/brif/]]..ifname..[[/port_no]]
		local file = io.open(file_name)
		if file == nil then
			return nil
		end
		local file_content = file:read("*a")
		file:close()
		local port = tonumber(file_content)
		port_num[port] = ifname
		--print(string.format("%s-%d",line,port))
	end
	return port_num
end

function print_br_macs(br_dev)
	macs = get_macs(br_dev)

	print(string.format("%s:",br_dev))
	if macs == nil then
		print("Device name error:"..br_dev)
		return nil
	end
	print(string.format("port_no\tdev\tmac_addr\t\tis_local\tageing_timer"))
	for _,mac in ipairs(macs) do
		print(string.format("%3s\t%s\t%s\t%s\t\t%8s",mac.no,mac.dev,mac.mac,mac.is_local,mac.ageing))
	end
end

function print_all_macs()
	for _,br in ipairs({"br-lan","br-guest"}) do
		print_br_macs(br)
	end
end

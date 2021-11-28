local Json = require("json")

local XQFunction = require("xiaoqiang.common.XQFunction")

local sleep = arg[1]
local payload = arg[2]
-- model=1 means allow
-- model=0 means deny
if payload then
    if sleep and tonumber(sleep) and tonumber(sleep) > 0 then
        os.execute("sleep "..tostring(sleep))
    end
    local suc, info = pcall(Json.decode, payload)
    if suc and info and type(info) == "table" then
        local macstr = XQFunction._cmdformat(table.concat(info.maclist, ";"))
        os.execute("iwpriv wl0 set ACLClearAll=1")
        os.execute("iwpriv wl1 set ACLClearAll=1")
        os.execute("iwpriv wl3 set ACLClearAll=1")
        if tonumber(info.model) == 0 then
            for _, mac in ipairs(info.maclist) do
                local cmac = XQFunction._cmdformat(mac)
                os.execute("iwpriv wl0 set DisConnectSta=\""..cmac.."\"")
                os.execute("iwpriv wl1 set DisConnectSta=\""..cmac.."\"")
                os.execute("iwpriv wl3 set DisConnectSta=\""..cmac.."\"")
            end
        end
        os.execute("iwpriv wl0 set ACLAddEntry=\""..macstr.."\"")
        os.execute("iwpriv wl1 set ACLAddEntry=\""..macstr.."\"")
        
        if tonumber(info.model) == 0 then
            os.execute("iwpriv wl0 set AccessPolicy=2")
            os.execute("iwpriv wl1 set AccessPolicy=2")
            os.execute("iwpriv wl3 set ACLAddEntry=\""..macstr.."\"")
            os.execute("iwpriv wl3 set AccessPolicy=2")
        else
            os.execute("iwpriv wl0 set AccessPolicy=1")
            os.execute("iwpriv wl1 set AccessPolicy=1")
            os.execute("iwpriv wl3 set AccessPolicy=0")
        end
        if #info.maclist == 0 then
            os.execute("iwpriv wl0 set AccessPolicy=0")
            os.execute("iwpriv wl1 set AccessPolicy=0")
            os.execute("iwpriv wl3 set AccessPolicy=0")
        end
        os.execute("ubus call trafficd update_assoclist")
    end
end

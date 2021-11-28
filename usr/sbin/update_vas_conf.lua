
local vas = require("xiaoqiang.module.XQVASModule")

local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

function base64_dec(data)
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

function sys_wakeup()
    os.execute("killall -s 10 noflushd ")
end

function update(b64str)
    local json = require("json")
    if not b64str then
        os.exit(1)
    else
        b64str = base64_dec(b64str)
    end
    local suc, info = pcall(json.decode, b64str)
    if suc and info then
        sys_wakeup()
        vas.updateVasConf(info)
        os.exit(0)
    end
    os.exit(1)
end

function get()
    local json = require("json")
    local info = vas.get_vas_info()
    print(json.encode(info))
    os.exit(0)
end

local param = arg[1]
if param == "get" then
    get()
else
    update(param)
end
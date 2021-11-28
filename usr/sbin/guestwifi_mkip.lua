local Log = require("xiaoqiang.XQLog")
local Guest  = require("xiaoqiang.module.XQGuestWifi")

--try to start ccgame service
local function main()
    --Log.log(6,".....arg0:" .. arg[0])
    --Log.log(6,".....arg1:" .. arg[1])
    local ip = arg[1]
    local new_ip = Guest.hookLanIPChangeEvent(ip)
    Log.log(1,"hookLanIPChangeEvent() calc ip new:" .. new_ip)
    print(new_ip)
end

--main
main()
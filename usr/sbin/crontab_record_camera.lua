#!/usr/bin/lua
--
-- Camera File Multiprocess Backup
-- @zhangyanlu
--
local XQCameraUtil = require("xiaoqiang.util.XQCameraUtil")
local XQLog = require("xiaoqiang.XQLog")

function main()
    for k,v in pairs(XQCameraUtil.getAntsCams()) do
        -- load config
        local cfg = XQCameraUtil.getConfig(v.origin_name)
        if cfg.enable == "yes" then
            os.execute("/usr/sbin/record_camera_by_ip.lua ".. v.ip .. " &")
            os.execute("/bin/sleep 1")
        end 
    end
end


if XQCameraUtil.isRunning("main") then
    XQLog.log(2,"XQCameraUtil:record camera is running.. exit..")
else
    XQCameraUtil.writePID("main")
    local space = XQCameraUtil.getCurrentDisk()
    XQLog.log(2,"XQCameraUtil:".. XQCameraUtil.getModel().. " " ..  space .. "MB")
    if space > 1 then
        main()
    end
end







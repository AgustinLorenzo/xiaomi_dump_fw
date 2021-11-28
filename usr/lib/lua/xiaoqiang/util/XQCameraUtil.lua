module ("xiaoqiang.util.XQCameraUtil", package.seeall)


local LuciProtocol = require("luci.http.protocol")
local urlencode = LuciProtocol.urlencode
local XQLog = require("xiaoqiang.XQLog")


-- utils
local XQDeviceUtil = require("xiaoqiang.util.XQDeviceUtil")
local XQFunction = require("xiaoqiang.common.XQFunction")
local XQHttpUtil = require("xiaoqiang.util.XQHttpUtil")

local JSON = require("json")
local LuciUtil = require("luci.util")
local LuciFs = require("luci.fs")

-- dirs config
local DIR_NAME = "/摄像机监控视频"

local ANTS_HTTP_BASE_MAIN = "http://%s/sd/record/"
local ANTS_HTTP_BASE_SUB = "http://%s/sd/record_sub/"

local ANTS_HTTP_BASE = ANTS_HTTP_BASE_MAIN

function set_ANTS_HTTP_BASE_MAIN( )
    ANTS_HTTP_BASE = ANTS_HTTP_BASE_MAIN
end

function set_ANTS_HTTP_BASE_SUB( )
    ANTS_HTTP_BASE = ANTS_HTTP_BASE_SUB
end

local MODEL = XQFunction.nvramGet("model")

local UCI = require("luci.model.uci")
local CONF = "record_camera"
local CUR_FILE = "/tmp/crontab_record_camera.lua.FILE"
local DEFAULT_CONF = {}
DEFAULT_CONF.enable = "no"
DEFAULT_CONF.hd = "yes"
DEFAULT_CONF.days = 7

local CURSOR = UCI.cursor()
local BASE_PATH = CURSOR:get("misc", "hardware", "camera")

function chmod777(file)
    local chmodcmd = "/bin/chmod 777 %s"
    LuciUtil.exec(chmodcmd:format(file))
end

function chmod777R(file)
    local chmodcmd = "/bin/chmod -R 777 %s"
    LuciUtil.exec(chmodcmd:format(file))
end

function set_base( b)
    BASE_PATH = b
end
function reset_base()
    BASE_PATH = CURSOR:get("misc", "hardware", "camera")
end

local HTTP_TOKEN = ""
function set_token( tok)
    HTTP_TOKEN = tok
end
function reset_token( tok )
    HTTP_TOKEN = ""
end

function getModel()
	return MODEL
end


function getCurrentDisk()
    local disk = XQFunction.thrift_tunnel_to_datacenter([[{"api":26}]])
    if disk and disk.code == 0 then
        return  math.floor(tonumber(disk.free) / (1024*1024) )
    else
        return  0
    end
end

function getCurrentDisk1()
    local disk = XQFunction.thrift_tunnel_to_datacenter([[{"api":26}]])
    if disk and disk.code == 0 then
        return  disk
    else
        return  nil
    end
end


function checkPathExists() 
    local disk = XQFunction.thrift_tunnel_to_datacenter([[{"api":17}]])
    local max_path = ""
    local mac_capa = 0
    if disk.code == 0 then
        for k,v in pairs(disk.allpath) do
            if v.path == BASE_PATH then
                XQLog.log(2,"XQCameraUtil:dir ok : " .. BASE_PATH )
                return BASE_PATH
            end
            local capa = tonumber(v.available)
            if mac_capa < capa then 
                max_path = v.path
                max_capa = capa
            end
        end
        BASE_PATH = max_path 
        XQLog.log(2,"XQCameraUtil:dir checked : " .. BASE_PATH )
    end
    chmod777R(BASE_PATH .. DIR_NAME)
end

function getUid(did)
    _,_, uid = did:find("%w+-%w+-(%w+)-?%w*")
    return uid
end

function getpwd(did)
    _,_, pwd = did:find("%w+-%w+-%w+-?(%w*)")
    return pwd
end

function getConfig(did)
    local uid = getUid(did)
    if not LuciFs.access("/etc/config/record_camera") then
        LuciFs.writefile("/etc/config/record_camera","")
    end
    local c = UCI:cursor()
    local conf = c:get_all(CONF,uid)
    if not conf then
        return DEFAULT_CONF
    else
    	conf.days = tonumber(conf.days)
        return conf
    end
end

function setConfig(did,config)
    local uid = getUid(did)
    local c = UCI:cursor() 
    c:section(CONF,"camera",uid,config)
    c:save(CONF)
    c:commit(CONF)
end

function getDay(days)
    local d = tonumber(days)*24*60*60
    if d < 86400 then
        d = 86400
    end
    local cmd = "/bin/date  \"+%Y-%m-%d %H:%M\" -D %s -d $(( $(/bin/date +%s) - " .. d ..  " )) "
    local theday = LuciUtil.exec(cmd)
    local r = {}
    _,_,r.year,r.month,r.day,r.hour,r.min = theday:find("(%d+)-(%d+)-(%d+)%s+(%d+):(%d+)")
    r.sec = "00"
    return r
end

function getCurrentPID()
    local stat = LuciFs.readfile("/proc/self/stat")
    local pid = ""
    if stat then
       _,_,pid = stat:find("^(%d+)%s.+")
    end
    return pid 
end

function isRunning(name)
    local pid = LuciFs.readfile("/tmp/record_camera_" .. name.. ".PID")
    if pid then
        return LuciFs.access("/proc/".. pid )
    end
    return false
end

function writePID(name)
    local pid = getCurrentPID()
    if pid then 
        LuciFs.writefile("/tmp/record_camera_" .. name.. ".PID",pid)
    end 
end

function getAntsCams()
    local res = {}
    local device_list = XQDeviceUtil.getDeviceList(true, true)
    for key,value in pairs(device_list) do 
        if value.ptype == 6 then
            table.insert(res,value)
        end
    end
    return res
end

function getFilesOnCam(item,afterDay)
    local res = {}
    local base = ANTS_HTTP_BASE:format(item.ip)
    local r = XQHttpUtil.httpGetRequest(base .. "?pwd=" .. getpwd(item.origin_name))
    if r.code == 200 then 
        local list = string.gmatch(r.res,"<A HREF=\"(%d+Y%d+M%d+D%d+H)\"")
        for w in list do
            _,_,yy,mm,dd,hh = w:find("(%d+)Y(%d+)M(%d+)D(%d+)H")
            local v1 = yy..mm..dd..hh
            local v2 = afterDay.year .. afterDay.month .. afterDay.day .. afterDay.hour
            if v1 > v2 then 
                local r1 = XQHttpUtil.httpGetRequest(base .. w .. "/".. "?pwd=" .. getpwd(item.origin_name))
                if r1.code == 200 then
                    local list1 = string.gmatch(r1.res,"[^\n]+")
                    for w1 in list1 do
                        local f = {}
                        _,_,f.year,f.month,f.day,f.hour = w:find("(%d+)Y(%d+)M(%d+)D(%d+)H")
                        _,_,f.min,f.sec,f.size  = w1:find("<A HREF=\"(%d+)M(%d+)S%.mp4\".+%s+(%d+)")
                        if f.min and f.sec and f.size then
                            f.url = base .. w .. "/" .. f.min .. "M" .. f.sec .. "S.mp4"
                            -- f.id = getUid(item.origin_name)
                            f.pwd = getpwd(item.origin_name)
                            f.size = tonumber(f.size)
                            f.dir_name = item.name .. "_" .. item.mac:gsub(":","")
                            table.insert(res,f)
                        end
                    end
                end
            end
        end
    end
    return res
end

function listlocaldir(path)
    local res = {}
    local base = LuciFs.dir(BASE_PATH .. DIR_NAME .. path)
    if base then
        for _,v in pairs(base) do 
            if v ~= "." and v ~= ".." then
                table.insert(res,v)
            end 
        end 
    end 
    return res
end

function walkCamFilesOnRouter(v,fn,para1)
    local days = listlocaldir("/" .. v )
    if days and #days > 0 then
        for _,days_dir in pairs(days) do
            local hours = listlocaldir("/" .. v .. "/" .. days_dir )
            if hours and #hours > 0  then
                for _,hours_dir in pairs(hours) do 
                    local files = listlocaldir("/" .. v .. "/" .. days_dir .. "/" .. hours_dir )
                    if files and #files > 0 then 
                        for _,fname in pairs(files) do
                            local f = {}
                            f.file = "/" .. v .. "/" .. days_dir .. "/" .. hours_dir .. "/" .. fname 
                            _,_,f.dir_name,f.year,f.month,f.day,f.hour,f.min,f.sec = f.file:find("/(%S+)/(%d+)年(%d+)月(%d+)日/(%d+)时/(%d+)分(%d+)秒.mp4")
                            if LuciFs.access( BASE_PATH .. DIR_NAME .. f.file  ) then
                                local stat = LuciFs.stat(BASE_PATH .. DIR_NAME .. f.file )
                                f.size = stat.size
                                fn(f,para1)
                            end
                        end
                    else 
                        LuciFs.rmdir(BASE_PATH .. DIR_NAME .. "/" .. v .. "/" .. days_dir .. "/" .. hours_dir ) 
                        XQLog.log(2,"XQCameraUtil:empty dir:" .. "/" .. v .. "/" .. days_dir .. "/" .. hours_dir )
                    end 
                end
            else
                LuciFs.rmdir(BASE_PATH .. DIR_NAME .. "/" .. v .. "/" .. days_dir) 
                XQLog.log(2,"XQCameraUtil:empty dir:" .. "/" .. v .. "/" .. days_dir  )
            end
        end
    end
end

function hasFile(f)
    local fname = "%s%s/%s/%s年%s月%s日/%s时/%s分%s秒.mp4"
    local file = fname:format(BASE_PATH,DIR_NAME,f.dir_name,f.year,f.month,f.day,f.hour,f.min,f.sec);
    if LuciFs.access(file) then
        local stat = LuciFs.stat(file)
        if f.size == stat.size  then
            XQLog.log(2,"XQCameraUtil:already download: " ..  file )
            return true
        end
    end
    return false
end

function mergeFiles(remotefiles)
    local res = {}
    for k,f in pairs(remotefiles) do
        if not hasFile(f) then
            table.insert(res, f)
        end
    end
    return res
end

function _fnDoDelete(v,afterDay)
    if v.year and v.month and v.day and v.hour then
        local v1 = v.year .. v.month .. v.day .. v.hour 
        local v2 = afterDay.year .. afterDay.month .. afterDay.day .. afterDay.hour       
        if v1 < v2 then
            XQLog.log(2,"XQCameraUtil:delete: " .. v.file)
            LuciFs.unlink(BASE_PATH .. DIR_NAME .. v.file)
        --else
        --   XQLog.log(7,"XQCameraUtil:exists: " .. v.file)
        end 
    end
end 

function doDelete(camDir,afterDay)
   walkCamFilesOnRouter(camDir,_fnDoDelete,afterDay)
end

function doDownload(f)
    
    local cmd = "/usr/bin/curl '%s' -o '%s' --create-dirs --connect-timeout 3 -sS"
    
    local fname = "%s%s/%s/%s年%s月%s日/%s时/%s分%s秒.mp4"
    local file = fname:format(BASE_PATH,DIR_NAME,f.dir_name,f.year,f.month,f.day,f.hour,f.min,f.sec);
    
    XQLog.log(2,"XQCameraUtil:downloading: " .. f.url .. "?pwd=" .. f.pwd .. " to " .. file);

    if string.find(f.url,"'") or string.find(f.pwd,"'") or string.find(file,"'") then
        return
    end
    
    LuciUtil.exec(cmd:format(f.url.."?pwd=" .. f.pwd ,file))
    
    if LuciFs.access(file) then
        local stat = LuciFs.stat(file)
        if f.size ~= stat.size then
            XQLog.log(2,"XQCameraUtil:download error: expect " .. f.size .. " ,got " .. stat.size )
            LuciFs.unlink(file)
        else
            local fname1 = "%s年%s月%s日%s时%s分"
            LuciFs.writefile(CUR_FILE,fname1:format( f.year,f.month,f.day,f.hour,f.min ) )
            chmod777(file)
        end
    end

end

-- function DoExec(cmd)
--		local LuciUtil = require("luci.util")
--	XQLog.log(7,cmd)
--	local s = LuciUtil.exec(cmd)
	-- XQLog.log(7,s)
--	return s
-- end

-- 
-- camera backup api
-- zhangyanlu@xiaomi.com
-- 

local Errorm1 = "{ \"code\" : -1 , \"msg\" : \"api not exists\" }";  
local Error3 = "{ \"code\" : 3 , \"msg\" : \"parameter format error\" }";
local OK0 = "{ \"code\" : 0 , \"msg\" : \"ok\" }";

function getAll(did)
	if not did then
		return Error3
	end
	local res = {}
	local cfg = getConfig(did)
	res.config = cfg
    if isRunning("main") then
	   res.isRunning = "yes"
    else 
        res.isRunning = "no"
    end
    local disk = getCurrentDisk1();
	if disk ~= nil then 
        res.space =  math.floor(tonumber(disk.free) / (1024*1024) )
        res.total = math.floor(tonumber(disk.capacity) / (1024*1024) )
    end

    res.code = 0
    if LuciFs.access(CUR_FILE) then
        res.file = LuciFs.readfile(CUR_FILE)
    end
    local p = "%s%s/%s/"
    local l = getAntsCams()
    local disname = ""
    for _,v in pairs(l) do
        if v.origin_name == did then
            disname = v.name .. "_" .. v.mac:gsub(":","")
        end 
    end 
    if cfg.custom_dir and cfg.custom_dir ~= "" then
        res.path = p:format(cfg.custom_dir,DIR_NAME,disname)
    else 
        res.path = p:format(BASE_PATH,DIR_NAME,disname)
    end
	return JSON.encode(res)
end

function setAllConfig(did,cfg)
	local _cfg = {}
	if cfg.enable == "yes" then
		_cfg.enable = "yes"
	else
		_cfg.enable = "no"
	end
	if cfg.days and tonumber(cfg.days) > 0 then
		_cfg.days = cfg.days
	else
		_cfg.days = 1
	end
	if cfg.hd == "yes" then
		_cfg.hd = "yes"
	else
		_cfg.hd = "no"
	end
    if cfg.custom_dir and cfg.custom_dir ~= "" then
        _cfg.custom_dir = cfg.custom_dir
    end
    if cfg.token and cfg.token ~= "" then
        _cfg.token = cfg.token 
    end 
	if did and did ~= "" then
		setConfig(did,_cfg)
	end 
    return OK0
end

function runNow()
    XQFunction.forkExec("/usr/sbin/crontab_record_camera.lua")
    return OK0
end

function request(payload)
	if payload == nil then
		return Error3
	end
	
	local params = JSON.decode(payload)
	if params == nil then
		return Error3
	end
	if params.command == "get_all" then
		return getAll(params.did)
	elseif params.command == "set_config" then
		return setAllConfig(params.did,params.config)
	elseif params.command == "run_backup" then
	    return runNow()
	else
		return Errorm1
	end
	
end






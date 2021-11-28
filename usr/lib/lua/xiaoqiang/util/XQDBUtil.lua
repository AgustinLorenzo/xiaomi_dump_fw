module ("xiaoqiang.util.XQDBUtil", package.seeall)

local suc, SQLite3 = pcall(require, "lsqlite3")
local XQ_DB = "/etc/xqDb"
local uci = require("luci.model.uci").cursor()
local XQLog = require("xiaoqiang.XQLog")

DEBUG = 7
INFO = 6
NOTICE = 5
WARN = 4
ERROR = 3
CRIT = 2


-- --
-- -- |TABLE| USER_INFO(UUID,NAME,ICONURL)
-- -- |TABLE| PASSPORT_INFO(UUID,TOKEN,STOKEN,SID,SSECURITY)
-- -- |TABLE| DEVICE_INFO(MAC,ONAME,NICKNAME,COMPANY,OWNNERID)
-- --

-- function savePassport(uuid,token,stoken,sid,ssecurity)
--     local db = SQLite3.open(XQ_DB)
--     local fetch = string.format("select * from PASSPORT_INFO where UUID = '%s'",uuid)
--     local exist = false
--     for row in db:rows(fetch) do
--         if row then
--             exist = true
--         end
--     end
--     local sqlStr
--     if not exist then
--         sqlStr = string.format("insert into PASSPORT_INFO values('%s','%s','%s','%s','%s')",uuid,token,stoken,sid,ssecurity)
--     else
--         sqlStr = string.format("update PASSPORT_INFO set UUID = '%s', TOKEN = '%s', STOKEN = '%s', SID = '%s', SSECURITY = '%s' where UUID = '%s'",uuid,token,stoken,sid,ssecurity,uuid)
--     end
--     db:exec(sqlStr)
--     return db:close()
-- end

-- function fetchPassport(uuid)
--     local db = SQLite3.open(XQ_DB)
--     local sqlStr = string.format("select * from PASSPORT_INFO where UUID = '%s'",uuid)
--     local result = {}
--     for row in db:rows(sqlStr) do
--         if row then
--             table.insert(result,{
--                 ["uuid"] = row[1],
--                 ["token"] = row[2],
--                 ["stoken"] = row[3],
--                 ["sid"] = row[4],
--                 ["ssecurity"] = row[5]
--             })
--         end
--     end
--     db:close()
--     return result
-- end

-- function fetchAllPassport()
--     local db = SQLite3.open(XQ_DB)
--     local sqlStr = "select * from PASSPORT_INFO"
--     local result = {}
--     for row in db:rows(sqlStr) do
--         if row then
--             table.insert(result,{
--                 ["uuid"] = row[1],
--                 ["token"] = row[2],
--                 ["stoken"] = row[3],
--                 ["sid"] = row[4],
--                 ["ssecurity"] = row[5]
--             })
--         end
--     end
--     db:close()
--     return result
-- end

-- function deletePassport(uuid)
--     local db = SQLite3.open(XQ_DB)
--     local sqlStr = string.format("delete from PASSPORT_INFO where UUID = '%s'",uuid)
--     db:exec(sqlStr)
--     return db:close()
-- end

-- function saveUserInfo(uuid,name,iconUrl)
--     local db = SQLite3.open(XQ_DB)
--     local fetch = string.format("select * from USER_INFO where UUID = '%s'",uuid)
--     local exist = false
--     for row in db:rows(fetch) do
--         if row then
--             exist = true
--         end
--     end
--     local sqlStr
--     if not exist then
--         sqlStr = string.format("insert into USER_INFO values('%s','%s','%s')",uuid,name,iconUrl)
--     else
--         sqlStr = string.format("update USER_INFO set UUID = '%s', NAME = '%s', ICONURL = '%s' where UUID = '%s'",uuid,name,iconUrl,uuid)
--     end
--     db:exec(sqlStr)
--     return db:close()
-- end

-- function fetchUserInfo(uuid)
--     local db = SQLite3.open(XQ_DB)
--     local sqlStr = string.format("select * from USER_INFO where UUID = '%s'",uuid)
--     local result = {}
--     for row in db:rows(sqlStr) do
--         if row then
--             table.insert(result,{
--                 ["uuid"] = row[1],
--                 ["name"] = row[2],
--                 ["iconUrl"] = row[3]
--             })
--         end
--     end
--     db:close()
--     return result
-- end

-- function fetchAllUserInfo()
--     local db = SQLite3.open(XQ_DB)
--     local sqlStr = string.format("select * from USER_INFO")
--     local result = {}
--     for row in db:rows(sqlStr) do
--         if row then
--             table.insert(result,{
--                 ["uuid"] = row[1],
--                 ["name"] = row[2],
--                 ["iconUrl"] = row[3]
--             })
--         end
--     end
--     db:close()
--     return result
-- end

-- function deleteUserInfo(uuid)
--     local db = SQLite3.open(XQ_DB)
--     local sqlStr = string.format("delete from USER_INFO where UUID = '%s'",uuid)
--     db:exec(sqlStr)
--     return db:close()
-- end

local LuciDatatypes = require("luci.cbi.datatypes")

function conf_saveDeviceInfo(mac,oName,nickname,company,ownnerId)
    if not LuciDatatypes.macaddr(mac) then
        return false
    end
    local key = mac:gsub(":", "").."_INFO"
    local section = {
        ["mac"] = mac,
        ["oname"] = oNmae,
        ["nickname"] = nickname,
        ["company"] = company
    }
    uci:section("devicelist", "deviceinfo", key, section)
    return uci:commit("devicelist")
end

function saveDeviceInfo(mac,oName,nickname,company,ownnerId)
    if not suc then
        return conf_saveDeviceInfo(mac,oName,nickname,company,ownnerId)
    end
    if not LuciDatatypes.macaddr(mac) then
        return
    end
    local db = SQLite3.open(XQ_DB)
    local fetch = string.format("select * from DEVICE_INFO where MAC = '%s'",mac)
    local exist = false
    for row in db:rows(fetch) do
        if row then
            exist = true
        end
    end
    local sqlStr
    if not exist then
        sqlStr = string.format("insert into DEVICE_INFO values('%s','%s','%s','%s','%s')",mac,oName,nickname,company,ownnerId)
    else
        sqlStr = string.format("update DEVICE_INFO set MAC = '%s', ONAME = '%s', NICKNAME = '%s', COMPANY = '%s', OWNNERID = '%s' where MAC = '%s'",mac,oName,nickname,company,ownnerId,mac)
    end
    db:exec(sqlStr)
    return db:close()
end

function conf_updateDeviceNickname(mac, nickname)
    if not LuciDatatypes.macaddr(mac) then
        return false
    end
    local key = mac:gsub(":", "").."_INFO"
    if uci:get_all("devicelist", key) then
        return uci:set("devicelist", "key", "nickname", nickname)
    end
    return false
end

function updateDeviceNickname(mac,nickname)
    if not suc then
        return conf_updateDeviceNickname(mac, nickname)
    end
    if not LuciDatatypes.macaddr(mac) then
        return
    end
    local db = SQLite3.open(XQ_DB)
    local sqlStr = string.format("update DEVICE_INFO set NICKNAME = '%s' where MAC = '%s'",nickname,mac)
    db:exec(sqlStr)
    return db:close()
end

-- function updateDeviceOwnnerId(mac,ownnerId)
--     local db = SQLite3.open(XQ_DB)
--     local sqlStr = string.format("update DEVICE_INFO set OWNNERID = '%s' where MAC = '%s'",ownnerId,mac)
--     db:exec(sqlStr)
--     return db:close()
-- end

-- function updateDeviceCompany(mac,company)
--     local db = SQLite3.open(XQ_DB)
--     local sqlStr = string.format("update DEVICE_INFO set COMPANY = '%s' where MAC = '%s'",company,mac)
--     db:exec(sqlStr)
--     return db:close()
-- end

function conf_fetchDeviceInfo(mac)
    if not LuciDatatypes.macaddr(mac) then
        return {}
    end
    local key = mac:gsub(":", "").."_INFO"
    local info = uci:get_all("devicelist", key)
    if info then
        return {
            ["mac"] = info.mac or "",
            ["oName"] = info.oname or "",
            ["nickname"] = info.nickname or "",
            ["company"] = info.company or "",
            ["ownnerId"] = ""
        }
    end
    return {}
end

function fetchDeviceInfo(mac)
    if not suc then
        return conf_fetchDeviceInfo(mac)
    end
    if not LuciDatatypes.macaddr(mac) then
        return
    end
    local db = SQLite3.open(XQ_DB)
    local sqlStr = string.format("select * from DEVICE_INFO where MAC = '%s'",mac)
    local result = {}
    for row in db:rows(sqlStr) do
        if row then
            result = {
                ["mac"] = row[1],
                ["oName"] = row[2],
                ["nickname"] = row[3],
                ["company"] = row[4],
                ["ownnerId"] = row[5]
            }
        end
    end
    db:close()
    return result
end

function conf_fetchAllDeviceInfo()
    local result = {}
    uci:foreach("devicelist", "deviceinfo",
        function(s)
            table.insert(result, {
                ["mac"] = s.mac or "",
                ["oName"] = s.oname or "",
                ["nickname"] = s.nickname or "",
                ["company"] = s.company or "",
                ["ownnerId"] = ""
            })
        end
    )
    return result
end

function fetchAllDeviceInfo()
    if not suc then
        return conf_fetchAllDeviceInfo()
    end
    local db = SQLite3.open(XQ_DB)
    local sqlStr = string.format("select * from DEVICE_INFO")
    local result = {}
    for row in db:rows(sqlStr) do
        if row and LuciDatatypes.macaddr(row[1]) then
            table.insert(result,{
                ["mac"] = row[1],
                ["oName"] = row[2],
                ["nickname"] = row[3],
                ["company"] = row[4],
                ["ownnerId"] = row[5]
            })
        end
    end
    db:close()
    return result
end

-- function deleteDeviceInfo(mac)
--     if not suc then
--         return
--     end
--     if not LuciDatatypes.macaddr(mac) then
--         return
--     end
--     local db = SQLite3.open(XQ_DB)
--     local sqlStr = string.format("delete from DEVICE_INFO where MAC = '%s'",mac)
--     db:exec(sqlStr)
--     return db:close()
-- end

-- vip devic on/offline push function

function sql_exec(cmd,db_in)
	local socket = require("socket")
        local func_ret
        if cmd == nil then
                return false
        end
        
        local db        
        if db_in ~= nil then    
                db = db_in
        else
                db = SQLite3.open(XQ_DB)
        end
        
        local ret = db:exec(cmd)
        
        if ret ~= SQLite3.OK then
        --if ret == SQLite.BUSY then
                local count = 0
                repeat
                        socket.select(nil,nil,0.1)      
                        ret = db:exec(cmd)      
                        count = count + 1
                until(ret == SQLite3.OK or count >= 3)  
                
                if(ret ~= SQLite3.OK) then
                        XQLog.log(ERROR,string.format("SQLite cmd retry[%d] exec failed[%s] resson[%s]",count,cmd,db:errmsg()))
                        func_ret = false
                else
                        XQLog.log(INFO,string.format("SQLite cmd retry[%d] exec success",count))
                        func_ret = true
                end
        else
                XQLog.log(INFO,string.format("SQLite cmd[%s] exec success",cmd))
                func_ret = true
        end
        if not db_in then
                db:close()
        end
        return func_ret
                                
end

function table_is_exist(table_name,db_in)
        local func_ret
        local db
        if db_in then
                db =  db_in
        else
                db = SQLite3.open(XQ_DB)
        end
        
        local cmd=string.format("select name from sqlite_master where name = '%s'",table_name)
        local ret = {}
        for row in db:rows(cmd) do
                ret = row
        end
        --ret = db:rows(cmd)()
        
        if next(ret) == nil then
                XQLog.log(ERROR,"[vip push]can not found table named "..table_name)
                func_ret = false
        else
                XQLog.log(ERROR,"[vip push]found table named "..table_name)
                func_ret = true
        end
        
        if not db_in then
                db:close()
        end
        return func_ret 
end


function table_dump(table_name,db_in)
        local db
        if db_in then
                db =  db_in
        else
                db = SQLite3.open(XQ_DB)
        end
        
        local cmd=string.format("select * from '%s'",table_name)
	local json = require("cjson")
        local ret = {}
        for row in db:rows(cmd) do
                XQLog.log(DEBUG,json.encode(row))
        end

        if not db_in then
                db:close()
        end
end

function table_create(db_in)
        local db
        local func_ret
        if db_in then
                db =  db_in
        else
                db = SQLite3.open(XQ_DB)
        end
        
        local cmd=string.format("CREATE TABLE DEVICE_PUSH_INFO (MAC TEXT PRIMARY KEY NOT NULL,STATUS TEXT,TIME INTEGER,ACTION TEXT,PUSHTIME INTEGER,LAST_ACTION TEXT,NAME TEXT);")
        local ret = sql_exec(cmd,db)

        if ret == false then
                XQLog.log(ERROR,"[vip push]create table for DEVICE_PUSH_INFO error")
                func_ret = false
        else
                func_ret = true
        end
        
        if not db_in then
                db:close()
        end
        return func_ret
end


function set_pending_status(mac,action,mac,db_in)
        local db
        if db_in then
                db = db_in
        else
                db = SQLite.open(XQ_DB)
        end
        
        mac = string.upper(mac)
        local fetch = string.format("select * from DEVICE_PUSH_INFO where MAC = '%s'",mac)
        local exist = false
        for row in db:rows(fetch) do
                if row then
                        exist = true
                end
        end
        XQLog.log(DEBUG,"[vip push]exist is :"..json.encode(exist)) 
        local cmd
	if nil == name then
	    if not exist then
		cmd = string.format("replace into %s(MAC,STATUS,TIME,ACTION) values('%s','pending',%d,'%s')","DEVICE_PUSH_INFO",string.upper(mac),os.time(),action)
	    else
		cmd = string.format("update DEVICE_PUSH_INFO set STATUS = 'pending',TIME = %d,ACTION = '%s' where MAC = '%s'",os.time(),action,mac)
	    end
	else
	    if not exist then
		cmd = string.format("replace into %s(MAC,STATUS,TIME,ACTION,NAME) values('%s','pending',%d,'%s','%s')","DEVICE_PUSH_INFO",string.upper(mac),os.time(),action,name)
	    else
                cmd = string.format("update DEVICE_PUSH_INFO set STATUS = 'pending',TIME = %d,ACTION = '%s',NAME = '%s'  where MAC = '%s'",os.time(),action,name,mac)
	    end
	end
        local func_ret = sql_exec(cmd)
        
        if not db_in then
                db:close()
        end
        
        return func_ret
end     

function set_pending_status_with_name(mac,name,action,db_in)
        local db
        if db_in then
                db = db_in
        else
                db = SQLite.open(XQ_DB)
        end
        
        mac = string.upper(mac)
        local fetch = string.format("select * from DEVICE_PUSH_INFO where MAC = '%s'",mac)
        local exist = false
        for row in db:rows(fetch) do
                if row then
                        exist = true
                end
        end
        XQLog.log(DEBUG,"[vip push]exist is :"..json.encode(exist)) 
        local cmd
        if not exist then
                cmd = string.format("replace into %s(MAC,STATUS,TIME,ACTION,NAME) values('%s','pending',%d,'%s','%s')","DEVICE_PUSH_INFO",string.upper(mac),os.time(),action,name)
        else
                cmd = string.format("update DEVICE_PUSH_INFO set STATUS = 'pending',TIME = %d,ACTION = '%s',NAME='%s' where MAC = '%s'",os.time(),action,name,mac)
        end
        
        local func_ret = sql_exec(cmd)
        
        if not db_in then
                db:close()
        end
        
        return func_ret
end     

function call_push_action_up()                                                                            
	local LuciUtil = require("luci.util")
	local XQFunction = require("xiaoqiang.common.XQFunction")
        local ret = tonumber(LuciUtil.exec("ps | grep -v grep | grep vip_device_push_act.lua 2>&1 > /dev/null; echo $?"))
        if ret == 1 then    
                XQLog.log(6,"can not found processon 'vip_device_push_act.lua' call it up")
                XQFunction.forkExec("vip_device_push_act.lua")
        else    
                XQLog.log(4,"vip_device_push_act.lua exist")                                                     
        end
end

function vip_device_pre_push(mac,name,action)
        if mac == nil or action == nil then
                return nil
        end
        
        local db = SQLite3.open(XQ_DB)
        if db == nil then
                XQLog.log(ERROR,"[vip push]open db failed")
        end

        if not table_is_exist("DEVICE_PUSH_INFO",db) then
                XQLog.log(NOTICE,"[vip push]can't found table named 'DEIVCE_PUSH_INFO'")
                if not table_create(db) then
                        XQLog.log(ERROR,"[vip push]create table error")
                        db:close()
                        return false
                end
        end
	if name == nil then
	    if not set_pending_status(mac,action,db) then
		    XQLog.log(ERROR,"[vip push]set mac["..string.upper(mac).."] status[pending] error")
	    else
		    XQLog.log(DEBUG,"[vip push]set mac["..string.upper(mac).."] status[pending] success,call vip_device_push_act.lua")
		    call_push_action_up()
	    end
	else
	    if not set_pending_status_with_name(mac,name,action,db) then
		    XQLog.log(ERROR,"[vip push]set mac["..string.upper(mac).."] status[pending] error")
	    else
		    XQLog.log(DEBUG,"[vip push]set mac["..string.upper(mac).."] status[pending] success,call vip_device_push_act.lua")
		    call_push_action_up()
	    end
	end

        --table_dump("DEVICE_PUSH_INFO",db)

        db:close()
end


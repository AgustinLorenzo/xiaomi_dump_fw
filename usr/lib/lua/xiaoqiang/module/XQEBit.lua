module ("xiaoqiang.module.XQEBit", package.seeall)

local json = require("json")
local logger = require("xiaoqiang.XQLog")

local XQFunction = require("xiaoqiang.common.XQFunction")
local HttpClient = require("xiaoqiang.util.XQHttpUtil")
local LuciProtocol = require("luci.http.protocol")

local APP_ID = "APP_MIOFGBVQ"
local SECRET = "2ErNCyfk8HZoH432T7Em0K16"

local URL_USER_QUERY = "http://218.85.118.9:8000/api2/user/query"
local URL_TASK_QUERY = "http://218.85.118.9:8000/api2/task/query"
local URL_SPUP_OPEN = "http://218.85.118.9:8000/api2/speedup/open"
local URL_SPUP_CLOSE = "http://218.85.118.9:8000/api2/speedup/close"
local URL_SPUP_QUERY = "http://218.85.118.9:8000/api2/speedup/query"
local URL_SPUP_CHECK = "http://218.85.118.9:8000/api2/speedup/check"

-- @return timestamp, secret
function genSecret()
    local crypto = require("xiaoqiang.util.XQCryptoUtil")
    local t = os.time()
    local s = APP_ID..tostring(t)..SECRET
    return t, crypto.md5Str(s)
end

function wanip()
    local XQLanWanUtil = require("xiaoqiang.util.XQLanWanUtil")
    local wan = XQLanWanUtil.ubusWanStatus()
    if XQFunction.isStrNil(wan.ipv4.address) then
        return nil
    else
        return wan.ipv4.address
    end
end

function task_query(timestamp, secret, taskid)
    local params = {
        ["app"] = APP_ID,
        ["timestamp"] = timestamp,
        ["secret"] = secret,
        ["task_id"] = taskid
    }
    local result = HttpClient.httpPostRequest(URL_TASK_QUERY, json.encode(params), nil, "application/json")
    if result and result.code and result.code == 200 then
        return json.decode(result.res)
    else
        logger.log(4, "XQEBit task/query failed", result)
        return nil
    end
end

-- app          : (string) 应用程序标识
-- timestamp    : (int) 时间戳
-- secret       : (string) 动态口令
-- data         : (string) 要查询的信息,类型由参数_type 指定
-- _type        : (int) 可选。 0 表示参数 data 是 IP 地址; 1 代表宽带帐号; 2 代表翼比特 用户标识;缺省为 0
-- auid         : (string) 应用程序用户标识
function basic_info_query(data)
    local timestamp, secret = genSecret()
    local pdata
    if not data then
        pdata = wanip()
        if not pdata then
            return nil
        end
    else
        pdata = data
    end
    local params = {
        ["app"] = APP_ID,
        ["timestamp"] = timestamp,
        ["secret"] = secret,
        ["_type"] = 0,
        ["data"] = pdata
    }
    local result = HttpClient.httpPostRequest(URL_USER_QUERY, json.encode(params), nil, "application/json")
    if result and result.code and result.code == 200 then
        local idinfo = json.decode(result.res)
        if idinfo.task_id then
            return task_query(timestamp, secret, idinfo.task_id)
        end
    else
        logger.log(4, "XQEBit user/query failed", result)
    end
    return nil
end

-- app          : (string) 应用程序标识
-- timestamp    : (int) 时间戳
-- secret       : (string) 动态口令
-- auid         : (string) 应用程序用户标识
-- dial_acct    : (string) 用户宽带帐号
-- ip_addr      : (string) 用户 IP 地址和端口
-- bandwidths   : ([int, int]) 可选。提速后的速率
-- duration     : (int) 可选。提速时长,单位分钟
function speed_up_open(up, down, duration, account, ip)
    if not ip then
        ip = wanip()
    end
    local timestamp, secret = genSecret()
    local params = {
        ["app"] = APP_ID,
        ["timestamp"] = timestamp,
        ["secret"] = secret,
        ["ip_addr"] = ip,
        ["dial_acct"] = account,
        ["bandwidths"] = { up, down },
        ["duration"] = duration
    }
    local result = HttpClient.httpPostRequest(URL_SPUP_OPEN, json.encode(params), nil, "application/json")
    if result and result.code and result.code == 200 then
        local idinfo = json.decode(result.res)
        if idinfo.task_id then
            return task_query(timestamp, secret, idinfo.task_id)
        end
    else
        logger.log(4, "XQEBit speedup/open failed", result)
    end
    return nil
end

-- app          : (string) 应用程序标识
-- timestamp    : (int) 时间戳
-- secret       : (string) 动态口令
-- channel_id   : (string) 提速通道标识
function speed_up_close(channelid)
    local timestamp, secret = genSecret()
    local params = {
        ["app"] = APP_ID,
        ["timestamp"] = timestamp,
        ["secret"] = secret,
        ["channel_id"] = channelid
    }
    local result = HttpClient.httpPostRequest(URL_SPUP_CLOSE, json.encode(params), nil, "application/json")
    if result and result.code and result.code == 200 then
        local idinfo = json.decode(result.res)
        if idinfo.task_id then
            return task_query(timestamp, secret, idinfo.task_id)
        end
    else
        logger.log(4, "XQEBit speedup/close failed", result)
    end
    return nil
end

-- app          : (string) 应用程序标识
-- timestamp    : (int) 时间戳
-- secret       : (string) 动态口令
-- channel_id   : (string) 提速通道标识
function speed_up_query(channelid)
    local timestamp, secret = genSecret()
    local params = {
        ["app"] = APP_ID,
        ["timestamp"] = timestamp,
        ["secret"] = secret,
        ["channel_id"] = channelid
    }
    local result = HttpClient.httpPostRequest(URL_SPUP_QUERY, json.encode(params), nil, "application/json")
    if result and result.code and result.code == 200 then
        local idinfo = json.decode(result.res)
        if idinfo.task_id then
            return task_query(timestamp, secret, idinfo.task_id)
        end
    else
        logger.log(4, "XQEBit speedup/query failed", result)
    end
    return nil
end

-- app          : (string) 应用程序标识
-- timestamp    : (int) 时间戳
-- secret       : (string) 动态口令
-- dial_acct    : (string) 用户宽带帐号
-- ip_addr      : (string) 用户 IP 地址和端口
function speed_up_check(account, ip)
    if not ip then
        ip = wanip()
    end
    local timestamp, secret = genSecret()
    local params = {
        ["app"] = APP_ID,
        ["timestamp"] = timestamp,
        ["secret"] = secret,
        ["ip_addr"] = ip,
        ["dial_acct"] = account
    }
    local result = HttpClient.httpPostRequest(URL_SPUP_CHECK, json.encode(params), nil, "application/json")
    if result and result.code and result.code == 200 then
        local idinfo = json.decode(result.res)
        if idinfo.task_id then
            return task_query(timestamp, secret, idinfo.task_id)
        end
    else
        logger.log(4, "XQEBit speedup/check failed", result)
    end
    return nil
end

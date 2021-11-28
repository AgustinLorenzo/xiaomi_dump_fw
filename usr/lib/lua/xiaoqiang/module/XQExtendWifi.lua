module ("xiaoqiang.module.XQExtendWifi", package.seeall)
local log = require("xiaoqiang.XQLog")

local TMP_FILE = "/tmp/replace_router"

local function get_type_value_from_file(type_)
	if type(type_) ~= "string" or type_ == nil then
		return
	end
	
	local file = io.open(TMP_FILE,"r")
	if file == nil then
		return
	end
	
	for line in file:lines() do
		local t = string.find(line,type_.."=")
		if t ~= nil then
			local val = string.sub(line,t+string.len(type_)+1)
			io.close(file)
			return val
		end
	end
	
	io.close(file)
end

function write_t_v(type_,val)
	 if type(type_) ~= "string" or type_ == nil then                                                       
	        return                                                                                        
	 end
	 
	 if type(val) ~= "string" or val == nil then
	 	return
	 end 
	--[[	 
	 local file = io.open(TMP_FILE,"r+w")
	 if file == nil then
	  	return
	 end
	 
	 clean_type_and_val(type_)
	 
	 file:seek("end")
	 
	 file:write(type_.."="..val)
	 
	 io.close(file)
	]]--
	 local tmp_cmd="echo "..type_.."="..val.." >>"..TMP_FILE
	 os.execute(tmp_cmd)
	   
	 return get_val(type_)
end
	  
	  
	
function clean_type_and_val(type_)
	if type(type_) ~= "string" or type_ == nil then
		return
	end
	
	local tmp_str="sed -i \'/"..type_.."/d\' "..TMP_FILE
	local old_val = get_type_value_from_file(type_)
	
	os.execute(tmp_str)
	return old_val
end

function get_val(type_)
	if type(type_) ~= "string" or type_ == nil then
		print("get type error type:"..type(type_).."type:"..type_)
		return 
	end
	print("will get type")
	return get_type_value_from_file(type_)
end

function get_peer_ip()
	return get_val("peer_ip")
end

function get_self_ip()
	return get_val("self_ip")
end

function get_self_ifname()
	return get_val("self_ifname")
end

function get_peer_ifname()
	return get_val("peer_ifname")
end	
function get_token()
	return get_val("token")
end
--[[
function get_act()
	return get_val("extendwifi_act")
end

function set_act(val)
	return write_t_v("extendwifi_act",val)
end
]]--
function set_token(val)
	return write_t_v("token",val)
end

function getLanEth()
    local LuciNetwork = require("luci.model.network").init()
    local wanNetwork = LuciNetwork:get_network("lan")
    return wanNetwork:get_option_value("ifname")
end

function landown()
    local cmd = "ifconfig "..getLanEth().." down"
    os.execute(cmd)
    log.log(1,"run cmd:"..cmd)
end

function lanup()
    local cmd = "ifconfig "..getLanEth().." up"
    os.execute(cmd)
    log.log(1,"run cmd:"..cmd)
end
    
-- api funcation
function oneClickGetRemoteTokenForLua(username,password,nonce)
    local log = require("xiaoqiang.XQLog")
    local XQFunction = require("xiaoqiang.common.XQFunction")
    local result = {
    	["code"] = 0
    }

    --params check
    if XQFunction.isStrNil(username) or XQFunction.isStrNil(password) or XQFunction.isStrNil(nonce) then
	result["code"] = 1636
--	result["msg"] = "params error"
	return result
    end
    --clean old token
--    os.execute("sed -i \'/token/d\' /tmp/replace_router")
    clean_type_and_val("token")
    --get peer ip
    local peer_ip = get_peer_ip()
    if peer_ip == nil or peer_ip == "" then
    	result["code"] = 1639
--    	result["msg"] = "get peer ip error"
	log.log(1,"func(oneClickGetRemoteTokenForLua),get peer ip error")
    	return result 
    end
    --request peer token
    res=get_remote_token(peer_ip,username,password,nonce)
    if res.code ~= 0 then
    	return res
    end
    
    --write new token to file
    set_token(res.result)
    result["token"]=res.result
    return result
end


function ExtendWifiRequestRemoteAPIForLua(api_str,need_token,params_str)
	local log = require("xiaoqiang.XQLog")
	local result = {
		["code"] = 0
	}

	if need_token == "" or need_token == nil then
		need_token="0"
	end
	
	if params_st ~= nil then
		log.log(1,"func(exten),get api_str"..api_str.." params_str:"..params_str)
	else
		log.log(1,"func(exten),get api_str"..api_str)
	end
	
	if api_str == nil or api_str == "" or type(api_str) ~= "string" then
		result.code = 1636
		return result
	end
	
	if need_token ~= "1" and need_token ~= "0" then
		result.code = 1639
		log.log(1,"func(ExtendWifiRequestRemoteAPIForLua),need_token error")
		return result
	end	
	
	if get_peer_ip() == "" or get_peer_ip() == nil then
		result.code = 1639
		log.log(1,"func(ExtendWifiRequestRemoteAPIForLua),get peer ip error")
		return result
	end
	
	local token = get_token()
		
	if need_token == "1" and (token == "" or token == nil) then
		result.code = 1639
		log.log(1,"func(ExtendWifiRequestRemoteAPIForLua),get token error")
		return result
	end
	 
	if need_token == "1" then 
		log.log(1,"get remote_ip"..get_peer_ip().." get token:"..token)
	else
		log.log(1,"get remote_ip"..get_peer_ip().." do not need token")
		token = ""
	end
	
	local ret
	ret = ExtenWifiRequestRemoteAPI_(get_peer_ip(),api_str,token,params_str)
	if ret.code ~= 0 then
		result["code"] = ret.code
		result["msg"] = ret.msg
	else
		result["code"] = 0
		result["msg"] = ret.msg
	end
	log.log(1,"func(ExtendWifiRequestRemoteAPIForLua).result.msg"..result.msg)	
	return result
end
--[[
function ExtendWifiSetActForLua(act)
	local log = require("xiaoqiang.XQLog")
	local result = {
		["code"] = 0
	}
	
	if act == nil or act == "" then
		result["code"] = 1
		result["msg"] = "params error"
		return result
	end
	
	if act ~= "1" and act ~= "2" then
		result["code"] = 2
		result["msg"] = "params must be <1-3>"
		return result
	end
	
	clean_type_and_val("extendwifi_act")
	
	set_act(act)

	return result
end
]]--
function ExtendWifiSetSynDirForLua(act,syn_dir)
	local log = require("xiaoqiang.XQLog")
	local ret = {
		["code"] = 0
	}
	
	if syn_dir == "" or syn_dir == nil then
		ret["code"] = 1612
--		ret["msg"] = "params error"
		return ret
	end	
	
	if type(syn_dir) ~= "string" then
		ret["code"] =1636
		return ret
	end
	
	if act == "" or act == nil then
		ret["code"] = 1612
--		ret["msg"] = "params error"
		return ret
	end	
	
	if type(act) ~= "string" then
		ret["code"] =1636
		return ret
	end
	
	
	if act ~= "1" and act ~= "2" then
		ret["code"] = 1636
		return ret
	end
	
        ret=ExtendWifiCallNewRouterDataCenterAPI(act,118,syn_dir)
        
	return ret
end 


function ExtendWifiCallNewRouterDataCenterAPI(act,payload)
	local log = require("xiaoqiang.XQLog")
	local ret ={
		["code"] = 0
	}
	--[[
	local payload_ ={
		["api"] = api_id
	}
	if payload ~= nil and payload ~= "" then
		payload_["source"] = payload 
	end
	local json = require("cjson")
	local payload_j = json.encode(payload_)
	]]--	
	
	if payload == "" or payload == nil then
		ret["code"] = 1612
		return ret
	end
	
	if type(payload) ~= "string" then
		ret["code"] = 1636
		return ret
	end	
	
	if act == nil or act == "" then
		ret["code"] = 1612	
		return ret
	end
	
	if act ~= "1" and act ~= "2" then
		ret["code"] = 1636
		return ret
	end
		
	if act == "1" then
		local result=ExtendWifiCallPeerDataCenterAPI(payload)
		return result
	else
		local ret=ExtendWifiCallSelfDataCenterAPI(payload)
		local result={
		["code"] = 0,
		["msg"] = ret
		}
		return result
	end
end

function ExtenWifiRequestRemoteAPI_(remote_ip,api_str,token,params)
	local XQHttpUtil = require("xiaoqiang.util.XQHttpUtil")
	local log = require("xiaoqiang.XQLog")
	local result={
		["code"]=0
	}
	local url
	if type(remote_ip) ~= "string" or remote_ip == nil or type(api_str) ~= "string" or api_str == nil then
		return
	end
	--log.log(1,"remote_ip:"..remote_ip)
	--log.log(1,"api_str:"..api_str)
	--log.log(1,"token:"..token)
	if token == "" or token == nil then
		url="http://"..remote_ip.."/cgi-bin/luci"..api_str
	else
		url="http://"..remote_ip.."/cgi-bin/luci/;stok="..token..api_str
	end
	
	if params ~= nil then
		log.log(1,"func(ExtenWifiRequestRemoteAPI_),url:"..url.." params:"..params)
	else
		log.log(1,"func(ExtenWifiRequestRemoteAPI_),url:"..url)
	end
	local ret=XQHttpUtil.httpGetRequest(url,params)
	if ret.code == 200 then
		result["code"] = 0
		result["msg"] = ret.res
	else	
		result["code"] = 1643
		result["msg"] = "http request error"
	end
	return result
end

	
function ExtendWifiCallSelfDataCenterAPI(payload_)
	local log= require("xiaoqiang.XQLog")
	local XQConfigs = require("xiaoqiang.common.XQConfigs")
        local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")
        local payload = XQCryptoUtil.binaryBase64Enc(payload_)
        local cmd = XQConfigs.THRIFT_TUNNEL_TO_DATACENTER % payload
        local LuciUtil = require("luci.util")
        local ret=LuciUtil.exec(cmd)
        return ret
end

function ExtendWifiCallPeerDataCenterAPI(payload_)
        local log = require("xiaoqiang.XQLog")
        local params = "payload="..payload_
        local ret=ExtendWifiRequestRemoteAPIForLua("/api/xqdatacenter/request","1",params)
        log.log(1,"func(ExtendWifiCallPeerDataCenterAPI)return "..ret.code)
        return ret
end

function ExtendWifiCallOldRouterDataCenterAPI(act,payload)
        local log = require("xiaoqiang.XQLog")
        local result ={
        	["code"] = 0
        }
        --[[
        local payload_t = {
        	["api"] = api_id
        }
        if payload ~= nil then
        	payload_t["sources"] = payload
        end
        local json=require("cjson")
        local payload = json.encode(payload_t)
        ]]--
        if payload == nil or payload == "" then
        	result["code"] = 1612
        	return result
        end
        
        if type(payload) ~= "string" then
        	result["code"] = 1636
        	return result
        end
        
        if act == nil or act == "" then
        	result["code"] = 1612
        	return result	
        end
        
        if act ~= "1" and act ~= "2" then
        	result["code"] = 1636
        	return result
        end
        
        if act == "1" then
                local ret=ExtendWifiCallSelfDataCenterAPI(payload)
                result ={
                ["code"] = 0,
                ["msg"] = ret
                }
                return result
        else
                local ret=ExtendWifiCallPeerDataCenterAPI(payload)
       		return ret 
        end
end
 
function get_remote_token(remote_ip,username,password,nonce)
	local log = require("xiaoqiang.XQLog")
	local XQHttpUtil = require("xiaoqiang.util.XQHttpUtil")
	local XQNetUtil = require("xiaoqiang.util.XQNetUtil")
	local result = {
		["code"] = 0,
	}
	local url="http://"..remote_ip.."/cgi-bin/luci/api/xqsystem/token"
	local params = {
		{"username",username},
		{"password",password},
		{"nonce",nonce},
	}
	local params_str=""
	table.foreach(params,function(k,v) params_str = params_str..v[1].."="..v[2].."&" end)
	log.log(1,"func(get_remote_token),http request: "..url.."?"..string.sub(params_str,1,-2))
	local ret=XQHttpUtil.httpGetRequest(url,string.sub(params_str,1,-2))
	if ret.code == 200 then
		local json = require("cjson")
		local json_res = json.decode(ret.res)
		if json_res.code == 0 then
			result["code"] = 0
			result["result"] = json_res.token
		elseif json_res.code == 401 then
			result["code"] = 1653
		elseif json_res.code == 1582 then
			result["code"] = 1654
		else
			result["code"] = 1639
		end
	else	
		result["code"] = 1643
	end
	log.log(1,"get remote token return code:"..result.code)
	return result
end                        

	

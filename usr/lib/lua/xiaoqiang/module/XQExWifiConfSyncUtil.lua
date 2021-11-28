module ("xiaoqiang.module.XQExWifiConfSyncUtil", package.seeall)

local http         = require("socket.http")
local cjson        = require("cjson")
local LuciHttp     = require("luci.http")
local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")
local XQLog        = require("xiaoqiang.XQLog")
local PWDKEY       = "a2ffa5c9be07488bbb04a3a47d3c5f6a"
local random_start = 1002
local random_end   = 9998
local debug_level  = 6

local ExWIFI_ERROR_CODE = {
    ["ERROR_INTERNAL"]     = 1639,
    ["ERROR_PEER_INFO"]    = 1640,
    ["ERROR_CONFIG_TRANS"] = 1641,
    ["ERROR_INVALID_MODE"] = 1642
}


local function _nonce_gen(mac)
    local nonce, nonce_encode
    local dtype, device, device_encode, time, random

    dtype = 0 -- 0: Web, 1: Android, 2: iOS, 3: Mac, 4: PC
    device = string.upper(mac)
    device_encode = LuciHttp.urlencode(device)
    time = os.time()
    math.randomseed(time)
    random = math.random(random_start, random_end)

    nonce = dtype .. "_" .. device .. "_" .. time .. "_" .. random
    nonce_encode = dtype .. "_" .. device_encode .. "_" .. time .. "_" .. random
    --XQLog.log(debug_level, "nonce gen: " .. nonce .. "nonce_encode: " .. nonce_encode)

    return nonce, nonce_encode
end

local function _password_gen(plaintext, nonce)
    local password = nil

    if not nonce then
        XQLog.log(debug_level, "please generate nonce first!")
        return nil
    end

    password = XQCryptoUtil.sha1(plaintext .. PWDKEY)
    --XQLog.log(debug_level, "step 1: plaintext: " .. plaintext .. " password : " .. password)

    password = XQCryptoUtil.sha1(nonce .. password)
    --XQLog.log(debug_level, "step 2: password gen: " .. password)

    return password
end

local function _file_size(file)
    local current = file:seek()
    local size    = file:seek("end")
    file:seek("set", current)
    return size
end

function account_login(remote, mac, plaintext)
    local password, nonce, nonce_encode
    local response_body = {}
    local jobj, url, token, code

    nonce, nonce_encode = _nonce_gen(mac)
    password = _password_gen(plaintext, nonce)

    local login_request = "username=admin&password=" .. password .. "&logtype=2&nonce=" .. nonce_encode
    XQLog.log(debug_level, "login request: " .. login_request)

    local res, status, response_header = http.request {
        url = "http://" .. remote.. "/cgi-bin/luci/api/xqsystem/login",
        method = "POST",
        headers =
            {
                ["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8";
                ["Content-Length"] = #login_request;
            },
        source = ltn12.source.string(login_request),
        sink   = ltn12.sink.table(response_body),
    }

    if (not res) or (not status) or (not response_header) then
        XQLog.log(debug_level, "http login request failed!")
        return nil
    end

    if (res ~= 1) or (status ~= 200) then
        XQLog.log(debug_level, "login request failed, res: " .. res .. " status: " .. status)
        return nil
    end

    if type(response_body) == "table" then
        for k, v in pairs(response_body) do
            jobj = cjson.decode(v)
        end
    end
    if not jobj then
        url   = jobj.url
        token = jobj.token
        code  = jobj.code
    end
    if (code == 0) then
        return token
    end

    return nil
end

function config_get(remote, token, path)
    local jobj, checksum

    if (not remote) or (not token) or (not path) then
        XQLog.log(debug_level, "invalid input parameters!")
        return ExWIFI_ERROR_CODE.ERROR_INTERNAL
    end

    XQLog.log(debug_level, "get config from peer: " .. remote .. " " .. path)
    local file = io.open(path, 'wb')
    if not file then
        XQLog.log(debug_level, "file open failed: " .. path)
        return ExWIFI_ERROR_CODE.ERROR_INTERNAL
    end

    local res, status, response_header = http.request {
        url    = "http://" .. remote .. "/cgi-bin/luci/;stok=" .. token .. "/api/misystem/extendwifi_config_pull",
        method = "GET",
        sink   = ltn12.sink.file(file), -- file will be closed automatically
    }

    if (not res) or (not status) or (not response_header) then
        XQLog.log(debug_level, "http get request failed!")
        return ExWIFI_ERROR_CODE.ERROR_CONFIG_TRANS
    end

    if (res ~= 1) or (status ~= 200) then
        XQLog.log(debug_level, "get request failed, res: " .. res .. " status: " .. status)
        return ExWIFI_ERROR_CODE.ERROR_CONFIG_TRANS
    end

    if type(response_header) == "table" then
        for k, v in pairs(response_header) do
            if (k == "Content-Checksum") then
                checksum = v
            end
        end
    end

    local file = io.open(path, 'r')
    if not file then
        XQLog.log(debug_level, "config file open failed!")
        return ExWIFI_ERROR_CODE.ERROR_CONFIG_TRANS
    end

    local m5sum = XQCryptoUtil.md5File(path)
    if (checksum ~= md5sum) then
        XQLog.log(debug_level, "config file checksum failed!")
        io.close(file)
        return ExWIFI_ERROR_CODE.ERROR_CONFIG_TRANS
    end

    XQLog.log(debug_level, "config file checksum ok!")
    io.close(file)

    XQLog.log(debug_level, "everything seems ok with config get!")
    return 0
end

function config_post(remote, token, path)
    local response_body = {}
    local jobj, code, ssid_24g, passwd_24g, ssid_5g, passwd_5g

    if (not remote) or (not token) or (not path) then
        XQLog.log(debug_level, "invalid input parameters!")
        return ExWIFI_ERROR_CODE.ERROR_INTERNAL
    end

    XQLog.log(debug_level, "post config to peer: " .. remote .. " " .. path)
    local file = io.open(path, 'rb')
    if not file then
        XQLog.log(debug_level, "file open failed: " .. path)
        return ExWIFI_ERROR_CODE.ERROR_INTERNAL
    end

    local md5sum = XQCryptoUtil.md5File(path)
    if not md5sum then
        io.close()
        XQLog.log(debug_level, "file calculate checksum failed: " .. path)
        return ExWIFI_ERROR_CODE.ERROR_INTERNAL
    end

    local size         = _file_size(file)
    local content      = file:read("*a")
    local name         = "config"
    local filename     = "config.tar.gz"
    local boundary     = "-----------------------------7004473821227421780129388645"
    local disposition  = "Content-Disposition: form-data; name=\"" .. name .. "\"; filename=\"" .. filename .. "\"\r\n"
    local ctype        = "Content-Type: application/octetstream\r\n\r\n"
    local request_body = "--" .. boundary .. "\r\n" .. disposition .. ctype .. content .. "\r\n--" .. boundary .. "--\r\n"

    local res, status, response_header = http.request {
        url     = "http://" .. remote .. "/cgi-bin/luci/;stok=" .. token .. "/api/misystem/extendwifi_config_push?checksum=" .. md5sum,
        method  = "POST",
        headers =
            {
                ["Content-Type"]     = "multipart/form-data; boundary=" .. boundary;
                ["Content-Length"]   = #request_body;
            },
        --source  = ltn12.source.file(file),
        source  = ltn12.source.string(request_body),
        sink    = ltn12.sink.table(response_body),
    }
    file:close()

    if (not res) or (not status) or (not response_header) then
        XQLog.log(debug_level, "http post request failed!")
        return ExWIFI_ERROR_CODE.ERROR_CONFIG_TRANS
    end

    if (res ~= 1) or (status ~= 200) then
        XQLog.log(debug_level, "post request failed, res: " .. res .. " status: " .. status)
        return ExWIFI_ERROR_CODE.ERROR_CONFIG_TRANS
    end

    if type(response_body) == "table" then
        for k, v in pairs(response_body) do
            jobj = cjson.decode(v)
        end
    end
    if jobj then
        code       = jobj.code
        ssid_24g   = jobj.ssid_24g
        passwd_24g = jobj.password_24g
        ssid_5g    = jobj.ssid_5g
        passwd_5g  = jobj.password_5g
    end
    if (code ~= 0) then
        if code then
            XQLog.log(debug_level, "peer has met some problem when do config post, code: " .. code)
        end
        return ExWIFI_ERROR_CODE.ERROR_CONFIG_TRANS
    end

    if ssid_24g then
        XQLog.log(debug_level, "peer ssid_24g: " .. ssid_24g)
    end
    if passwd_24g then
        XQLog.log(debug_level, "peer passwd_24g: " .. passwd_24g)
    end
    if ssid_5g then
        XQLog.log(debug_level, "peer ssid_5g: " .. ssid_5g)
    end
    if passwd_5g then
        XQLog.log(debug_level, "peer passwd_5g: " .. passwd_5g)
    end

    XQLog.log(debug_level, "everything seems ok with config post!")
    return code, ssid_24g, passwd_24g, ssid_5g, passwd_5g
end

function config_finish(remote, token, wifi, reboot)
    local response_body = {}
    local param, jobj, code

    if (not remote) or (not token) then
        XQLog.log(debug_level, "invalid input parameters!")
        return 1
    end

    if (not wifi) and (reboot) then --turn off local wifi
        param = "reboot=yes"
    elseif (wifi) and (not reboot) then --turn off peer wifi
        param = "wifi=off"
    else
        XQLog.log(debug_level, "invalid input parameters, wifi: " .. wifi .. " reboot: " .. reboot)
        return 1
    end

    local res, status, response_header = http.request {
        url    = "http://" .. remote .. "/cgi-bin/luci/;stok=" .. token .. "/api/misystem/extendwifi_config_fini?" .. param,
        method = "GET",
        sink   = ltn12.sink.table(response_body),
    }

    if (not res) or (not status) or (not response_header) then
        XQLog.log(debug_level, "http finish request failed!")
        return 1
    end

    if (res ~= 1) or (status ~= 200) then
        XQLog.log(debug_level, "finish request failed, res: " .. res .. " status: " .. status)
        return 1
    end

    if type(response_body) == "table" then
        for k, v in pairs(response_body) do
            jobj = cjson.decode(v)
        end
    end
    if jobj then
        code = jobj.code
    end
    if (code ~= 0) then
        if code then
            XQLog.log(debug_level, "peer has met some problem when do config finish, code: " .. code)
        end
        return 1
    end

    XQLog.log(debug_level, "everything seems ok with config finish!")
    return 0
end

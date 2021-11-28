#!/usr/bin/lua
-- 命令解析和处理相关

local json= require 'json'
require 'miqos.common'

local fcmd={}

local function uci_commit_save(cursor)
    cursor:commit('miqos')
    -- tmp下的配置改变,复写回/etc下
    if not tmp2cfg() then
        logger(1, 'copy tmp cfg to /etc/config/ failed.')
    end
end

local function update_qos_enabled(qos_on_flag)
    local cursor=get_cursor()
    if qos_on_flag then
        cursor:set('miqos','settings','enabled','1')
    else
        cursor:set('miqos','settings','enabled','0')
    end

    uci_commit_save(cursor)
end

local function switch_dev_redirect(enable)
    if enable == 1 then
        logger(3, 'enable dev_redirect caused by qos on.')
        os.execute("[ -f /proc/sys/net/dev_redirect_enable ] && echo 1 > /proc/sys/net/dev_redirect_enable");
    else
        logger(3, 'disable dev_redirect caused by qos off.')
        os.execute("[ -f /proc/sys/net/dev_redirect_enable ] && echo 0 > /proc/sys/net/dev_redirect_enable");
    end
end

-- 开启band-limit-QoS
function fcmd.on()
    update_qos_enabled(true)
    if not cfg.enabled.started then
        cfg.enabled.changed = true
    end
    cfg.enabled.started=true

    -- 读取网络配置
    if not read_network_conf() then
        logger(3, 'failed to read network config when `qos on`!')
    end

    switch_dev_redirect(1);

    return {status=0,data='ok'},true
end

-- 关闭band-limit-QoS,开启优先级-QoS
function fcmd.off()
    update_qos_enabled(false)
    cfg.enabled.started=true

    -- 读取网络配置
    if not read_network_conf() then
        logger(3, 'failed to read network config when `qos off`!')
    end

    switch_dev_redirect(0);

    return {status=0,data='ok'},true
end

-- 关闭所有QoS规则，但保持服务在线(调用qdisc-clean)
function fcmd.shutdown()
    cleanup_system()

    logger(3, 'QOS_VER: '..QOS_VER..' shutdown!')
    --[[
    if QOS_VER == "FIX" then
        fix_set_leteng_qos()
    end
    --]]

    switch_dev_redirect(0);

    cfg.enabled.started=false
    if not QOS_VER or QOS_VER == 'FIX' or QOS_VER == 'NOIFB' then -- FIX版本shutdown不用重刷规则
        return {status=0,data='ok'},false
    else
        return {status=0,data='ok'},true
    end
end

-- 优先级调整
function fcmd.nprio(act,ip,type)
    if not act or not ip or not type then
        logger(3,'ERROR: parameter lost for cmd `nprio`')
        return {status=1,data='unkown error.'},false
    end

    if g_debug then
        logger(3,'nprio ' .. act ..','.. ip .. ',' .. type)
    end

    if act == 'add' then
        if not special_host_list.host[ip] or type ~=  special_host_list.host[ip] then
            special_host_list.host[ip]=type
            special_host_list.changed=true
            return {status=0,data='ok'},false
        else
            return {status=0,data='already in list.'},false
        end

    elseif act == 'del' then
        if special_host_list.host[ip] then
            special_host_list.host[ip]=nil
            special_host_list.changed=true
            return {status=0,data='ok'},false
        else
            return {status=0,data='not exist in list.'},false
        end
    else
        return {status=1,data='not supported action for cmd `nprio`.'},false
    end
end


-- 更新预留带宽特殊设备列表
function fcmd.reserve(act,ip,type)
    if not act or not ip or not type then
        logger(3,'ERROR: parameter lost for cmd `reserve`')
        return {status=1,data='unkown error.'},false
    end
    if g_debug then
        logger(3, 'update_reserved_hosts, act:' .. act ..', ip:'..ip ..', type:' .. type)
    end


    if act == 'add' then
        if not band_reserve_hosts[type] then
            band_reserve_hosts[type]={}
        end
        if band_reserve_hosts[type] and band_reserve_hosts[type][ip] then
            return {status=0,data='already reserved.'}, false
        end
        band_reserve_hosts[type][ip]=type
    elseif act == 'del' then
        if band_reserve_hosts[type] and band_reserve_hosts[type][ip] then
            band_reserve_hosts[type][ip]=nil
        else
            return {status=0,data='already delted.'}, false
        end
    else
        logger(3,'do not support act: ' .. act)
        return {status=1,data='not supported.'},false
    end

    band_reserve_hosts.changed=true

    return {status=0,data='ok'},false

end


function update_bw(max_up,max_down)

    if tonumber(max_up) >= 0 and tonumber(max_down) >= 0 then
        local cursor=get_cursor()
        cursor:set('miqos','settings','upload',max_up)
        cursor:set('miqos','settings','download',max_down)

        uci_commit_save(cursor)
        return true
    end
    return false
end

-- 修改band参数
function fcmd.change_band(up,down)
--  when bands change from zero to non zero, do cleanup_system once,
--  cause maybe there are leteng qos rules on qdisc
    if tonumber(cfg.bands.UP) <=0 or tonumber(cfg.bands.DOWN) <= 0 then
        if tonumber(up) > 0 and tonumber(down) > 0 then
            logger(3,'bands from zero to non zero, do cleanup_system')
            cleanup_system()
        end
    end

    if up and down and update_bw(up,down) then
        return {status=0,data='ok'},true
    end
    return {status=1,data='update bandwidth failed.'},false
end

local function get_bw()
    local cursor=get_cursor()
    local up = cursor:get('miqos','settings','upload') or '0'
    local down=cursor:get('miqos','settings','download') or '0'
    return up,down
end

-- 输出band参数
function fcmd.show_band()
    local data={}
    data['uplink'],data['downlink']=get_bw()
    return {status=0,data=data},false
end

local function update_guest(in_up,in_down)

    local cursor=get_cursor()
    cursor:set('miqos','guest','up_per',in_up)
    cursor:set('miqos','guest','down_per',in_down)

    uci_commit_save(cursor)
    return true
end

-- 设置guest的限制参数
function fcmd.on_guest(up,down)
    if up and down and update_guest(up,down) then
        return {status=0,data='ok'},true
    end
    return {status=1,data='update guest limit failed.'},false
end

-- 输出guest参数
function fcmd.show_guest()
    return {status=0,data=cfg.guest},false
end

local function update_xq_limit(in_up, in_down)
    local cursor=get_cursor()
    cursor:set('miqos','xq','up_per',in_up)
    cursor:set('miqos','xq','down_per',in_down)

    uci_commit_save(cursor)
    return true
end

--[[
local function update_leteng_limit(up, down)
    local cursor=get_cursor()
    cursor:set('miqos','xq','leteng_up',up)
    cursor:set('miqos','xq','leteng_down',down)

    uci_commit_save(cursor)
    return true
end

function fcmd.on_leteng(up,down)
    if up and down and update_leteng_limit(up, down) then
        cfg.leteng.modeoff=false
        cfg.leteng.changed=1
        return {status=0,data='ok'},true
    end
    return {status=1,data='update leteng limit failed.'},false
end

function fcmd.show_leteng()
    local mode=''

    if cfg.leteng.modeoff then
        mode='True'
    else
        mode='False'
    end

    return {modeoff=mode,data=cfg.leteng},false
end
--]]

function fcmd.on_xq(up,down)
    if up and down and update_xq_limit(up, down) then
        return {status=0,data='ok'},true
    end
    return {status=1,data='update xq limit failed.'},false
end

function fcmd.show_xq()
    return {status=0,data=cfg.xq},false
end

-- 显示每个host的限速数据
function fcmd.show_limit()
    if QOS_VER == "FIX" or QOS_VER == 'NOIFB' then
        update_counters(nil)
    end
    return {
        status=0,
        data=g_limit,   -- 全局g_limit保存返回的数据
        mode=cfg.qos_type.mode,
        arrange_bandwidth={
            upload=cfg.bands.UP,
            download=cfg.bands.DOWN,
        },
    },false
end

-- 简化配置中MAC设置
local function compact_output_group_def()
    local ret={}
    if not g_group_def then
        read_qos_group_config()
    end
    local t={'max_grp_uplink','min_grp_uplink','max_grp_downlink','min_grp_downlink','flag'}
    for k, v in pairs(g_group_def) do
        if k ~= cfg.group.default then
            ret[k]={}
            for _,n in pairs(t) do
                ret[k][n]=v[n]
            end
        end
    end
    return ret
end

-- 限速每个host的限速配置
function fcmd.show_cfg()
    return {status=0,data=compact_output_group_def(),mode=cfg.qos_type.mode}
end

local function add_or_change_group(mac, maxup, maxdown, minup, mindown, on_flag)

    local str_mac=string.upper(mac)
    local mac_name=string.gsub(str_mac,':','')
    local cursor=get_cursor()
    local all=cursor:get_all('miqos')
    local name = ''
    for k,v in pairs(all) do
        if v['.type'] == 'group' and v['name'] == str_mac then
            name = k
            break
        end
    end

    if name == '' then
        name = cursor:section('miqos','group',mac_name)
        cursor:set('miqos',name,'name',str_mac)
        cursor:set('miqos',name,'min_grp_uplink','0.5')
        cursor:set('miqos',name,'min_grp_downlink','0.5')
        cursor:set('miqos',name,'max_grp_uplink','0')
        cursor:set('miqos',name,'max_grp_downlink','0')
        cursor:set('miqos',name,'mode','general')
        cursor:set('miqos',name,'mac',{str_mac})
    end

    if not on_flag and maxup and maxdown then on_flag = "on" end
    if on_flag and (on_flag == 'on' or on_flag == 'off') then
        cursor:set('miqos',name,'flag',on_flag)
    end

    local tmp_num
    if minup then
        tmp_num = tonumber(minup)
        if tmp_num <= 0 or tmp_num > 1 then
            minup = g_default_min_updown_factor
            if g_debug then
                logger(3,'setting min reserve out of range, set it to default value.')
            end
        end
        cursor:set('miqos',name,'min_grp_uplink',minup)
    end
    if mindown then
        tmp_num = tonumber(mindown)
        if tmp_num <= 0 or tmp_num > 1 then
            mindown = g_default_min_updown_factor
            if g_debug then
                logger(3,'setting min reserve out of range, set it to default value.')
            end
        end
        cursor:set('miqos',name,'min_grp_downlink',mindown)
    end
    if maxup then
        tmp_num = tonumber(maxup)
        if tmp_num < 8 then
            maxup = 0
            if g_debug then
                logger(3,'NOTE: setting min reserve out of range, set it to default value.')
            end
        end
        cursor:set('miqos',name,'max_grp_uplink',maxup)
    end
    if maxdown then
        tmp_num = tonumber(maxdown)
        if tmp_num < 8 then
            maxdown = 0
            if g_debug then
                logger(3,'NOTE: setting min reserve out of range, set it to default value.')
            end
        end
        cursor:set('miqos',name,'max_grp_downlink',maxdown)
    end

    uci_commit_save(cursor)
end

-- 开启某个host的限速
function fcmd.on_limit(mode,mac,u1,d1,u2,d2)
    if mode == 'max' then
        add_or_change_group(mac,u1,d1,nil,nil)
    elseif mode == 'min' then
        add_or_change_group(mac,nil,nil,u1,d1)
    elseif mode == 'both' then
        add_or_change_group(mac,u1,d1,u2,d2)
    else
        logger(3,'not supported on_limit mode.')
        return {status=1,data='not supported on_limit mode.'},false
    end

    cfg.group.changed=true  -- 告知有限速设置变化需要重新刷host规则

    return {status=0,data='ok'},true
end

function fcmd.set_limit(mode,mac,u1,d1,u2,d2)
    if mode == 'max' then
        add_or_change_group(mac,u1,d1,nil,nil)
    elseif mode == 'min' then
        add_or_change_group(mac,nil,nil,u1,d1)
    elseif mode == 'both' then
        add_or_change_group(mac,u1,d1,u2,d2)
    else
        logger(3,'not supported on_limit mode.')
        return {status=1,data='not supported on_limit mode.'},false
    end

    cfg.group.changed=true  -- 告知有限速设置变化需要重新刷host规则

    return {status=0,data='ok'},false
end

function fcmd.apply()
    return {status=0,data='ok'},true
end

local function del_group(mac)
    local cursor=get_cursor()
    local all=cursor:get_all('miqos')

    if mac then
        local str_mac = string.upper(mac)
        for k,v in pairs(all) do
            if v['.type'] == 'group' and v['name'] == str_mac then
                cursor:delete('miqos',k)
                break
            end
        end
    else
        for k,v in pairs(all) do
            if v['.type'] == 'group' and v['name'] ~= '00' then
                cursor:delete('miqos',k)
            end
        end
    end

    uci_commit_save(cursor)
end

-- 关闭host的限速
function fcmd.off_limit(mac)
    del_group(mac)
    cfg.group.changed=true  -- 告知有限速设置变化需要重新刷host规则
    return {status=0,data='ok'},true
end

function fcmd.limit_flag(mac, on_flag)
    if not mac and not on_flag then
        return {status=1, data="parameters mac or on_flag is NULL."}, false
    end

    if on_flag ~= "on" and on_flag ~= "off" then
        return {status=1, data="parameters on_flag is not one of on/off."}, false
    end

    if not g_group_def then
        read_qos_group_config()
    end
    if g_group_def[mac] then
        if g_group_def[mac].flag and g_group_def[mac].flag == on_flag then
            return {status=0, data="parameters on_flag with same value."}, false
        else
            add_or_change_group(mac, nil, nil, nil, nil, on_flag)
        end
    else
        add_or_change_group(mac, nil, nil, nil, nil, on_flag)
    end
    return {status=0, data="ok"}, true
end

local function update_qos_auto_mode(mode)
    local cursor=get_cursor()
    cursor:set('miqos','settings','qos_auto',mode)
    uci_commit_save(cursor)
end

-- 设置QoS运行模式,auto,min,max,both
function fcmd.set_type(type)
    if type == 'auto' then
        logger(3, "----->>set to auto-limit-mode.")
    elseif type == 'min' then
        logger(3, "----->>set to min-limit-mode.")
    elseif type == 'max' then
        logger(3, "----->>set to max-limit-mode.")
    elseif type == 'both' then
        logger(3, "----->>set to both-limit-mode.")
    else
        logger(3, "----->>set to service-limit-mode.")
        type = 'service'
    end

    update_qos_auto_mode(type)

    return {status=0,data='ok'},true
end

function fcmd.set_seq(seq)
    local cursor=get_cursor()
    cursor:set('miqos','param','seq_prio',seq)
    uci_commit_save(cursor)

    return {status=0,data='ok'},true
end

function fcmd.get_seq()
    local str=cfg.flow.seq
    if str == '' then
        str = cfg.flow.dft
    end
    return {status=0,data={seq_prio=str}},false
end

function fcmd.supress_host(flag)
    if flag == 'on' then
        cfg.supress_host.enabled = true
    elseif flag == 'off' then
        cfg.supress_host.enabled = false
    else
        return {status=1,data="not supported supress command."},false
    end
    cfg.supress_host.changed = true
    return {status=0,data="ok"},true
end

-- 如果设备有限速，才需要重刷规则
local function check_device_change_refresh(mac)
    local refresh=false
    if mac then
        local mac_str = string.upper(mac)
        if mac_str == '00' then   -- 有线
            refresh = true
        elseif g_group_def and g_group_def[mac_str] then
            local u=math.ceil(g_group_def[mac_str]['max_grp_uplink'] or '0')
            local d=math.ceil(g_group_def[mac_str]['max_grp_downlink'] or '0')
            if (u > 8 or d > 8) then
                refresh=true
            end
        end
    end
    return refresh
end

function fcmd.device_in(mac)
    return {status=0,data='ok'},check_device_change_refresh(mac)
end

function fcmd.device_out(mac)
    return {status=0,data='ok'},check_device_change_refresh(mac)
end

function fcmd.game_mode_on()
    cfg.wangzhe.changed=true
    cfg.wangzhe.modeon=true
    cfg.wangzhe.cleanflag=true
    return {status=0,data='ok'},true
end

function fcmd.game_mode_off()
    cfg.wangzhe.modeon=false
    cfg.wangzhe.cleanother=true
    cfg.enabled.changed=true
    return {status=0,data='ok'},true
end

function fcmd.wangzhe_plug_on()
    cfg.wangzhe.plugon=true
    return {status=0,data='ok'},true
end

function fcmd.wangzhe_plug_off()
    cfg.wangzhe.plugon=false
    return {status=0,data='ok'},true
end

function fcmd.game_dev_add(ip)
    cfg.wangzhe.iplist[ip]={devip=ip}
    cfg.wangzhe.changed=true
    return {status=0,data='ok'},true
end

function fcmd.game_dev_del(ip)
    if cfg.wangzhe.iplist[ip] then
        cfg.wangzhe.iplist[ip].devip=nil
        cfg.wangzhe.iplist[ip]=nil
    end
    cfg.wangzhe.changed=true
    return {status=0,data='ok'},true
end

function fcmd.game_dev_band(up,down)
    cfg.wangzhe.devbands.UP=tonumber(up)
    cfg.wangzhe.devbands.DOWN=tonumber(down)
    cfg.wangzhe.bandchanged=true

    return {status=0,data='ok'},true
end

function fcmd.game_mode_band(up,down)
    cfg.wangzhe.bands.UP=tonumber(up)
    cfg.wangzhe.bands.DOWN=tonumber(down)
    cfg.wangzhe.bandchanged=true

    return {status=0,data='ok'},true
end

function fcmd.show_game_state()
    local data={}
    local change=''
    local mode=''
    local plug=''

    for _ip,_dev in pairs(cfg.wangzhe.iplist) do
        data[_ip]={
            IP=_dev.devip,
        }
    end

    if cfg.wangzhe.modeon then
        mode='True'
    else
        mode='False'
    end

    if cfg.wangzhe.plugon then
        plug='True'
    else
        plug='False'
    end

    if cfg.wangzhe.changed then
        change='True'
    else
        change='False'
    end

    return {
        modeon=mode,
        changed=change,
        devs=data,
        plugon=plug,
        total_bands={
            upload=cfg.wangzhe.bands.UP,
            download=cfg.wangzhe.bands.DOWN,
        },
        dev_bands={
            upload=cfg.wangzhe.devbands.UP,
            download=cfg.wangzhe.devbands.DOWN,
        },
    },false
end

function fcmd.show_wangzhe()
    local data={}

    if cfg.wangzhe.plugon then
        data['switch']=1
    else
        data['switch']=0
    end

    return {status=0,data=data},false
end

-- 命令处理的包装函数
function process_cmd(cmd, ...)
    if not cmd or not fcmd[cmd] then
        if cmd then
            logger(3, 'cmd `' .. cmd .. '` is not defined.')
        else
            logger(3, 'cmd is NULL. r u sure?')
        end
        return {status=1,data='cmd is not defined.'}
    else
        --logger(3,p_sysinfo() .. '===CMD: `qos ' .. cmd .. '` ')
        -- 返回错误码和对应的数据,json的展开形式
        return fcmd[cmd](unpack(arg))
    end
end






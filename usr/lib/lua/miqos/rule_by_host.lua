#!/usr/bin/lua
--双层队列分流,使用算法htb，第一层为host区分，第二层为dataflow分流

require 'miqos.common'
-- 流队列的配置
local THIS_QDISC='host'

-- 将对应的处理方法加入qdisc表
local qdisc_df ={}
qdisc[THIS_QDISC]= qdisc_df

local lip  = require "luci.ip"
local const_tc_dump=' tc -d class show dev %s |grep "level 5" '

local htb_cfg={
    rate_score=0.5,             -- 默认无配置的host的分数因子
    ceil_score=1.0,             -- 默认无配置的host的分数因子
    htb_buffer_factor=1.5,      -- htb buffer默认因子
    qos={ack=false,syn=true,fin=true,rst=true,icmp=true,small=false},    -- 优先级的包
    online_timeout={wl=5,wi=300},   -- 在线超时时间判断
}

local xq_maxlimit_on_htb={
    UP=0.85,
    DOWN=0.85
}

-- layer1
local CLASS_HIER ={
    dft=0x4000,      -- qdisc默认的队列最低优先级队列
    quan_v=1500,  -- quan 至少必须 > MTU,否则会出现发不出包的情况
    ['root']={
        id=0x1000,
        quan=8,
        fwmark='0x00010000/0x000f0000',
        fprio='4'
    },
    ['child']={
        -- prio
        {          -- 优先级队列不再保留其他队列，所有优先处理的都流到这个队列
            id=0x2000,
            prio='1',
            quan=4,
            fwmark='0x00020000/0x000f0000',
            fprio='4',
            rate=0.35,
            ceil=0.8,
            highest_prio='1',
        },
        -- host
        {
            id=0x3000,
            prio='4',    -- 内部子节点优先级，2,3,4,5 共4个队列
            quan=4,
            fwmark='',     -- fwmark为空，表示有子节点
            fprio='',
            rate=0.60,
            ceil=0.98,
            supress=2048,    -- 对host进行压制
        },
        -- guest
        {
            id=0x4000,
            prio='6',
            quan=2,
            fwmark='0x00040000/0x000f0000',
            fprio='4',
            rate=0.05,
            ceil=0,         --ceil为0,通过limit来控制可配置的ceil限速
            limit=cfg.guest,   -- guest的最高限速
        },
        -- xq
        {
            id=0x5000,
            prio='7',
            quan=1,
            fwmark='0x00050000/0x000f0000',
            fprio='4',
            rate=0.05,
            ceil=0,
            limit=xq_maxlimit_on_htb,        -- xq的最高限速
        }
    }
}

--layer2, host的扩展
local CLASS_HIER_host_ext ={
    [1]={
        id=0x1,
        prio=2,
        rate=0.15,
        ceil=0.6,
    },
    [2]={
        id=0x2,
        prio=3,
        rate=0.4,
        ceil=1.00,
    },
    [3]={
        id=0x3,
        prio=4,
        rate=0.4,
        ceil=1.00,
    },
    [4]={
        id=0x4,
        prio=5,
        rate=0.05,
        ceil=0.95,
        default=true,
    },
}

--ip<->mac N对1 映射表
local new_ip_mac_map={}
local cur_ip_mac_map={}
local alive_mac_ips_map={}

local band_reserve_type={
    'video',
}

-- 对于某些特殊的设备预留带宽配置
local band_reserve_rule={
    ['video']={
        band=0,
        {id=0,band=0,},                          -- <512 不预留
        {id=512,band=480},       --60*8,         -- 标清底线 60Kb/s， > 512kbps
        {id=2048,band=800},      --100*8,        -- 高清底线 100Kb/s, > 2Mbps
        {id=5120,band=1600},     --200*8,        -- 超清底线 200kb/s, > 5Mbps
        {id=10249,band=2400},    --300*8,        -- 蓝光底线 300kb/s, > 10Mbps
    },
    ['other']={},
}

-- 简单粗暴的扣减需要预留部分的带宽
local function dec_reserved_bands(cur_alive,total_rate)
    local reserve_in_total=0
    for k, v in pairs(band_reserve_hosts) do
        if k ~= 'changed' then
            local num=0
            for host, _ in pairs(v) do
                if cur_alive[host] then
                    num = num + 1
                end
            end

            --logger(3,'k:'..k..',num:'..num)
            if num > 0 and band_reserve_rule[k]['band'] then
                reserve_in_total = reserve_in_total + num * band_reserve_rule[k]['band']
            end
        end
    end

    -- pr(cur_alive)
    -- pr(band_reserve_hosts)

    if g_debug then
        logger(3,"try to reserved bands in total:" .. reserve_in_total)
    end

    -- 判断是否预留带宽超出了整体带宽的70%,否则不作预留
    if reserve_in_total <=0 or reserve_in_total > math.ceil(total_rate * 0.7) then
        return false, 0
    else
        return true, reserve_in_total
    end
end


-- 清理qdisc规则
function qdisc_df.clean(devs)
    local tblist={}
    for _,dev in pairs(devs) do
        local expr = string.format("%s del dev %s root ", const_tc_qdisc, dev.dev)
        table.insert(tblist,expr)
    end

    if not exec_cmd(tblist,1) then
        logger(3, 'ERROR: clean qdisc rules for host mode failed!')
    end

    -- 清除当前列表
    cur_ip_mac_map={}
    alive_mac_ips_map={}
    new_ip_mac_map={}
    -- logger(3,"###clean cur_ip_mac_map")

end

-- 更新counters计数，在更新qos后更新计数器（后续可能改为定期获取）
function qdisc_df.update_counters(devs)

    if cfg.enabled.flag == '0' then
        return
    end

    local up_id=devs[UP]['id']
    local down_id=devs[DOWN]['id']

    local tc_counters={
            [up_id]={},   -- uplink
            [down_id]={},   -- downlink
    }
    for k,dev in pairs(devs) do
        local v=dev['dev']
        local w={}
        local pp=io.popen(string.format(const_tc_dump, v))
        local data=pp:read("*line")
        local lineno=1

        while data do
            -- 1st line
            local first,_,ldir,lclass,lrate,lceil =  string.find(data,"class htb (%d+):(%w+).*rate (%w+) ceil (%w+)")
            if first then
                if not tc_counters[ldir][lclass] then
                    tc_counters[ldir][lclass] = {}
                end

                tc_counters[ldir][lclass]['r'] = lrate
                tc_counters[ldir][lclass]['c'] = lceil
            end
            data = pp:read('*line')
        end
        pp:close()
    end

    -- pr(tc_counters)


    local limit={}
    local maxup, maxdown, minup, mindown= 0, 0, 0, 0
    local tmp_id
    local host_id_base = CLASS_HIER['child'][2]['id']
    for k,v in pairs(new_ip_mac_map) do
        -- pr(new_ip_mac_map)
        tmp_id = dec2hexstr(host_id_base + v['id']*0x10)
        if tc_counters[up_id][tmp_id] then
            maxup = tc_counters[up_id][tmp_id]['c']
            minup = tc_counters[up_id][tmp_id]['r']
        end

        if tc_counters[down_id][tmp_id] then
            maxdown = tc_counters[down_id][tmp_id]['c']
            mindown = tc_counters[down_id][tmp_id]['r']
        end

        local up,down
        local mac = v['mac']
        local on_flag = 'on'
        if mac and g_group_def[mac] then
            local mx_up = tonumber(g_group_def[mac]['max_grp_uplink'])
            local mx_down = tonumber(g_group_def[mac]['max_grp_downlink'])

            if mx_up < 1 then
                mx_up = math.ceil(cfg.bands.UP * mx_up)
            elseif mx_up == 1 then
                mx_up = 0
            end
            if mx_down < 1 then
                mx_down = math.ceil(cfg.bands.DOWN * mx_down)
            elseif mx_down == 1 then
                mx_down = 0
            end

            up={
                max_per=mx_up,
                min_per=g_group_def[mac]['min_grp_uplink'],
                max_cfg=math.ceil(g_group_def[mac]['max_grp_uplink']),
                max=maxup,
                min_cfg=math.ceil(g_group_def[mac]['min_grp_uplink']),
                min=minup
            }
            down={
                max_per=mx_down,
                min_per=g_group_def[mac]['min_grp_downlink'],
                max_cfg=math.ceil(g_group_def[mac]['max_grp_downlink']),
                max=maxdown,
                min_cfg=math.ceil(g_group_def[mac]['min_grp_downlink']),
                min=mindown
            }
            on_flag = g_group_def[mac].flag or 'on'
        else
            up={max_per=0,min_per=0.5,max_cfg=0, max=maxup,min_cfg=0, min=minup}
            down={max_per=0,min_per=0.5,max_cfg=0, max=maxdown,min_cfg=0,min=mindown}
        end
        limit[k]={MAC=mac,UP=up,DOWN=down,flag=on_flag}
    end

    return limit

end

-- type(mask) must be number
local function if_ip_in_same_subnet(ipa, ipb, mask)
    if ipa==nil or ipb==nil or mask==nil then
        return false
    end

    local cidr_a = lip.IPv4(ipa)
    local cidr_b = lip.IPv4(ipb)

    if cidr_a and cidr_b then
        local neta = lip.cidr.network(cidr_a, mask)
        local netb = lip.cidr.network(cidr_b, mask)
        if neta and netb then
           local eq = lip.cidr.equal(neta, netb)
           return eq
        end
    end

    return false
end

local function get_network(netname)
   local ret = g_ubus:call("network.interface", "status", {interface=netname})
   if ret and table.getn(ret['ipv4-address']) > 0 then
       local addr = table.remove(ret['ipv4-address'])
       return addr.address, addr.mask
   end
   return nil
end

-- 这里假定：
-- 同一mac可以有不同ip，但是所有的ip地址唯一，相同ip地址将被认为是一个设备
local function update_host_list_compact()
    local ret=g_ubus:call("trafficd","hw",{})

    -- 更新new ipmac 表
    for _,v in pairs(ret or {}) do
        local mac=v['hw']
        local wifi='0'
        if v['ifname'] == "wl0" or v['ifname'] == "wl1" then
            wifi = '1'  -- host wifi
        elseif string.find(v['ifname'],"wl",1) then
            wifi = '2'   -- guest wifi, will be skipped later
        end

        for _,ips in pairs(v['ip_list'] or {}) do
            local ip,valid_ip = ips['ip'], false
            local nid=string.split(ip,'.')[4]

            if cfg.lan.ip and cfg.lan.mask then
                local same_subnet = if_ip_in_same_subnet(ip, cfg.lan.ip, tonumber(cfg.lan.mask))
                if same_subnet then
                    -- 检查ip地址的在线状态by ageingtime
                    if wifi == '1' then     -- br-lan wifi, assoc会在掉线后立即变成0
                        -- TODO: 需要讨论下，是否需要设置一个限时值来限制同一mac无线下多个ip的超时问题
                        --if v['assoc'] == 1 and ips['ageing_timer'] <= htb_cfg.online_timeout.wl then
                        if v['assoc'] == 1 then
                            valid_ip = true
                        end
                    elseif wifi == '0' then     -- br-lan 有线， 需要超时判断
                        if ips['ageing_timer'] <= htb_cfg.online_timeout.wi then
                            valid_ip = true
                        end
                    end
               end
            end

            -- 此ip为有效值，先置此ip为'NEW'，后面再更新状态
            if valid_ip and nid then
                new_ip_mac_map[ip]={   -- 维护队列,以ip为key
                    mac=mac,
                    st='S_NEW',
                    id=nid,
                    idle=ips['ageing_timer'],
                }

                if not alive_mac_ips_map[mac] then
                    alive_mac_ips_map[mac] = {}
                end

                table.insert(alive_mac_ips_map[mac],ip)
                -- logger(3,"mac: " .. mac .. ',ip: ' .. ip)
            end
        end
    end

end

-- 按照配置进行带宽分配，计算预留的百分比
local function arrange_bandwidth()

    local total={UP=0,DOWN=0}
    for imac,iips in pairs(alive_mac_ips_map) do
        for _, iip in pairs(iips) do
            local id=imac   -- groupid是以MAC地址为key的
            if not g_group_def[id] then
                id=cfg.group.default
            end

            local tmp_up = tonumber(g_group_def[id]['min_grp_uplink'])     -- 前面读取保证（0,1);且保证未配置时取默认值
            local tmp_down = tonumber(g_group_def[id]['min_grp_downlink'])     -- 前面读取保证（0,1);且保证未配置时取默认值
            total[UP] = total[UP] + tmp_up
            total[DOWN] = total[DOWN] + tmp_down
        end
    end

    -- pr(g_group_def)

    for mac, v in pairs(g_group_def) do
        if alive_mac_ips_map[mac] or mac == cfg.group.default then  -- 此mac对应的group有效
            g_group_def[mac]['each_up_rate'] = v['min_grp_uplink']/ total[UP]
            g_group_def[mac]['each_down_rate'] = v['min_grp_downlink']/ total[DOWN]

            if tonumber(v['max_grp_uplink']) <= 1 then
                g_group_def[mac]['each_up_ceil'] = v['max_grp_uplink']*cfg.bands.UP
            else
                g_group_def[mac]['each_up_ceil'] = v['max_grp_uplink']/1.0
            end

            if tonumber(v['max_grp_downlink']) <= 1 then
                g_group_def[mac]['each_down_ceil'] = v['max_grp_downlink']*cfg.bands.DOWN
            else
                g_group_def[mac]['each_down_ceil'] = v['max_grp_downlink']/1.0
            end

            logger(3, '@mac:' .. mac .. ',[UP]min=' .. g_group_def[mac]['each_up_rate'] .. ',max='..
                    g_group_def[mac]['each_up_ceil'] ..';[DOWN]min=' .. g_group_def[mac]['each_down_rate'] ..
                    ',max='..g_group_def[mac].each_down_ceil)
        end
    end

    -- pr(g_group_def)
end

-- 检测host数量变化，并根据限速规则分配更新每个用户限速值
local function check_host_amount_changed()
    local flag = false
    -- 清空mac-ips表先
    alive_mac_ips_map={}
    cur_ip_mac_map = new_ip_mac_map
    new_ip_mac_map={}
    update_host_list_compact()

    -- 根据new ipmac表和现存的ipmac表更新IP状态记录
    for iip,imac in pairs(new_ip_mac_map or {}) do
        if cur_ip_mac_map[iip] then
            new_ip_mac_map[iip]['st']='S_UPD'

            -- 此ip对应的mac已经变化，那么需要重新计算带宽分配
            if cur_ip_mac_map[iip]['mac'] ~= imac['mac'] then
                flag=true
            end

            cur_ip_mac_map[iip]=nil     -- 相当于此记录转移到了new表中
        else
            -- 新加入的IP
            flag = true
            -- logger(3,'new ip ' .. iip .. ' come in triggered flush.' )
        end
    end

    -- 计算需要删除的host记录
    for iip,imac in pairs(cur_ip_mac_map or {}) do
        if not new_ip_mac_map[iip] then
            cur_ip_mac_map[iip]['st']='S_DEL'
            flag=true
            logger(3,'expired ip ' .. iip .. ' out triggered flush.')
        else
            logger(3,'ERROR: except case; should no any non-del records in such table.')
        end
    end

    return flag
end

-- 'host'模式htb下，每次都返回true，在apply里面进行changed检测
function qdisc_df.changed()
    return true
end

-- 检测host-QoS的因素是否变化
-- whole-change： 1.整体带宽值; 2.guest限速变化,
-- host-change: 1.host数量变化,2.host限速值变化
local function changed_level()
    local flag = '0'  -- no change
    local strlog=''

    -- 优先级低在前判断，高在后判断(因为flag会被覆盖)
    if cfg.group.changed then    -- host限速配置是否变化
        strlog = strlog .. '/group'
        cfg.group.changed=false
        flag= '2'   -- host only change
    end

    if cfg.qos_type.changed then    -- 限速模式是否变化
        strlog = strlog .. '/qos type'
        cfg.qos_type.changed=false
        flag='2'
    end

    if band_reserve_hosts.changed then
        strlog = strlog .. '/band-reserve-hosts'
        band_reserve_hosts.changed = false
        flag='2'
    end

    --Note: 一般情况下，如果有特殊设备加入，都会有host加入从而触发host规则重刷
    if special_host_list.changed then
        strlog = strlog .. '/special host list'
        special_host_list.changed = false
        flag='2'
    end

    if check_host_amount_changed() then     -- host数量是否变化
        strlog = strlog .. '/hosts list'
        flag = '2'  -- host only change
    end

    if cfg.bands.changed then        --整体带宽值变化
        strlog = strlog .. '/bandwidth'
        cfg.bands.changed=flase
        flag = '1'   -- whole change
    end

    if cfg.guest.changed == 1 then       -- guest限速变化
        strlog = strlog .. '/guest'
        cfg.guest.changed = 0
        flag = '1'    -- whole change
    end

    if cfg.supress_host.changed then
        strlog = strlog .. '/supress switch'
        cfg.supress_host.changed =false
        flag = '1'
    end

    if strlog ~= '' then
        logger(3,'CHANGE: ' .. strlog)
    end

    -- 如果host变化，需要重算带宽占比,结果存放在g_group_def中
    if flag ~= '0' then
        arrange_bandwidth()
    end

    return flag
end

-- 生成每个单独设备下的子队列，对应不同的流
local function apply_host_flow_qdisc_class_filter(tblist, dev, dir, flow_id, act, pparent, hostid, rate, ceil, quantum)

    local nCls,expr = #(CLASS_HIER_host_ext),''
    local buffer,cbuffer=get_burst(ceil)

    -- host 处理
    local host_root_id=pparent + hostid*0x10
    if act == 'del' then
        expr=string.format("%s %s dev %s classid %s:%s ",const_tc_class, act, dev, flow_id, dec2hexstr(host_root_id))
        table.insert(tblist,1,expr)    -- insert from backend
    elseif act == 'change' then
        expr = string.format(
            "%s %s dev %s parent %s:%s classid %s:%s htb rate %s%s ceil %s%s burst %d cburst %d quantum %d ",
            const_tc_class, act, dev, flow_id, dec2hexstr(pparent), flow_id, dec2hexstr(host_root_id), rate, UNIT,
            ceil, UNIT, buffer, cbuffer, quantum)
        table.insert(tblist,1,expr)     -- change
    else
        expr = string.format(
            "%s %s dev %s parent %s:%s classid %s:%s htb rate %s%s ceil %s%s burst %d cburst %d quantum %d ",
            const_tc_class, act, dev, flow_id, dec2hexstr(pparent), flow_id, dec2hexstr(host_root_id), rate, UNIT,
            ceil, UNIT, buffer, cbuffer, quantum)
        table.insert(tblist,expr)  -- add
    end

    local default_flow_id=0
    for m=1,nCls do
        local filter_flow_id= hostid*0x10 + m               -- filter 用的id
        local class_flow_id= pparent + filter_flow_id       -- class 用的id

        local cls=CLASS_HIER_host_ext[m]
        if act == 'del' then
            expr=string.format("%s %s dev %s classid %s:%s ", const_tc_class, act, dev, flow_id, dec2hexstr(class_flow_id))
            table.insert(tblist, 1, expr)
        else
            local lrate,lceil=math.ceil(rate*cls.rate),math.ceil(ceil*cls.ceil)
            local buffer,cbuffer=get_burst(lceil)
            local lprio=cls['prio']

            expr = string.format("%s %s dev %s parent %s:%s classid %s:%s htb rate %s%s ceil %s%s prio %s " ..
                    "quantum %s burst %d cburst %d", const_tc_class, act, dev, flow_id, dec2hexstr(host_root_id),
                    flow_id, dec2hexstr(class_flow_id), lrate, UNIT, lceil, UNIT, lprio , quantum, buffer, cbuffer)
            if act == 'change' then
                table.insert(tblist,1,expr)
            else
                table.insert(tblist, expr)
            end

            -- leaf
            apply_leaf_qdisc(tblist,dev,flow_id,dec2hexstr(class_flow_id),lceil)

        end

        if cls.default then
            default_flow_id = class_flow_id
        end

        -- filter
        local fprio='5'
        expr = string.format(" %s %s dev %s parent %s: prio %s handle 0x%s00000/0xfff00000 fw classid %s:%s ",
        const_tc_filter, act, dev, flow_id , fprio, dec2hexstr(filter_flow_id), flow_id, dec2hexstr(class_flow_id))
        if act == 'del' then
            table.insert(tblist, 1, expr)
        elseif act == 'change' then
            -- filter is not changed.
        else
            table.insert(tblist,expr)
        end

    end

    -- add default filter for non-recognized flow
    if default_flow_id ~= 0 then
        local fprio_default='6'
        expr = string.format(" %s %s dev %s parent %s: prio %s handle 0x%s000000/0xff000000 fw classid %s:%s ",
            const_tc_filter, act, dev, flow_id , fprio_default, dec2hexstr(hostid), flow_id, dec2hexstr(default_flow_id))
        if act == 'del' then
            table.insert(tblist, 1, expr)
        elseif act == 'change' then
            -- filter is not changed.
        else
            table.insert(tblist,expr)
        end
    end

    return true
end

-- 生成hosts下子节点的qdisc规则
local function apply_hosts_qdisc_class_filter(tblist, dev, dir, flow_id, rate, ceil, act, parent)

    local expr,lact='','add'

    -- 如果act是change，则原来存在host列表，需要先清除过期的host
    if act ~= 'add' then
        lact='del'
        for k, v in pairs(cur_ip_mac_map or {}) do
            if v['st'] == 'S_DEL' then
                logger(3,'--- del MAC ' .. v['mac'] .. ', IP ' .. k)
                local hostid=tonumber(v['id'])

                if not apply_host_flow_qdisc_class_filter(tblist, dev, dir, flow_id, lact, parent, hostid, 0, 0, 0 ) then
                    logger(3,'gen del host:' .. v['id'] ..' failed.')
                    return false
                end
            end
        end
    end

     -- 在host节点，预先扣减预留带宽
    if dir == DOWN then
        local flag,amount = dec_reserved_bands(new_ip_mac_map,rate)
        if flag then
            rate = rate - amount
        end
    end

    -- 新增或更新host
    for iip, v in pairs(new_ip_mac_map or {}) do
        local lact = 'add'
        if v['st'] ~= 'S_NEW' then
            lact = 'change'
        end

        local mac,hostid=v['mac'],tonumber(v['id'])
        local group= g_group_def[mac] or g_group_def[cfg.group.default]

        local host_rate,host_ceil,ratio,in_quan,tmp_rate,tmp_ceil
        if dir == UP then
            tmp_rate = rate*group['each_up_rate']
            tmp_ceil = group['each_up_ceil'] or 0
            if tmp_ceil > math.ceil(cfg.bands[dir]) then
                tmp_ceil = 0
            end
            ratio=math.ceil(group['min_grp_uplink']*10)
        else
            tmp_rate = rate*group['each_down_rate']
            tmp_ceil = group['each_down_ceil'] or 0
            if tmp_ceil > math.ceil(cfg.bands[dir]) then
                tmp_ceil = 0
            end
            ratio=math.ceil(group['min_grp_downlink']*10)
        end

        if tmp_ceil <= 0 then tmp_ceil = ceil end   -- 如果ceil=0表示未限速
        if tmp_ceil < 40 then tmp_ceil = 40 end   -- 保证不要小于5kb/s

        if tmp_rate > tmp_ceil then tmp_rate = tmp_ceil end
        host_rate,host_ceil=math.ceil(tmp_rate),math.ceil(tmp_ceil)

        if ratio <=0 then ratio = 1 end
        if ratio > 10 then ratio =10 end
        in_quan = math.ceil(cfg.quan * ratio)

        -- 仅仅支持下行预留(简单起见)
        if dir == DOWN then
            for _, type in pairs(band_reserve_type) do
                local res = band_reserve_hosts[type]
                if res[iip] then    -- 如果此ip需要预留
                    if g_debug then
                        logger(3,'reserve band ' .. band_reserve_rule[type]['band'] .. 'kbps for ' .. iip)
                    end
                    host_rate = host_rate + band_reserve_rule[type]['band']
                    break   -- 只能预留一种
                end
            end
        end

        logger(3, '+++ MAC ' .. mac .. ",IP " .. iip .. ', ' .. dir .. ',' .. host_rate .. '-' .. host_ceil ..
                ', id:' .. v['id'] .. ',action:' .. lact)

        if not apply_host_flow_qdisc_class_filter(tblist, dev, dir, flow_id, lact, parent, hostid, host_rate, host_ceil, in_quan) then
            logger(3,'gen ' .. lact ..' host: '.. v['ip'] .. ' failed.')
            return false
        end

    end

    return true
end

-- host根节点数据缓存
local host_root_cache={
    [UP]={
        id=0,
        ceil=0,
    },
    [DOWN]={
        id=0,
        ceil=0,
    },
}

-- 仅仅更新host的规则
local function apply_qdisc_class_filter_for_host(tblist, devs, act, bands, clevel)
    if act ~= 'change' then
        logger(3,'`act` should be `change`. exit.')
        return false
    end

    local expr=''
    for k, v in pairs(devs) do
        local dir,dev,flow_id=k,v['dev'],v['id']
        local cid,lrate,lceil=host_root_cache[k]['id'],host_root_cache[k]['rate'],host_root_cache[k]['ceil']
        if not apply_hosts_qdisc_class_filter(tblist, dev, dir, flow_id, lrate, lceil, act, cid) then
            logger(3,'gen all hosts rules failed.')
            return false
        end
    end
    return true

end

-- 更新整个htb规则树
local function apply_qdisc_class_filter_for_root(tblist, devs, act, bands, clevel)

    local expr=''
    for k, v in pairs(devs) do
        local dir,dev,flow_id=k,v['dev'],v['id']

        -- qdisc 根
        if act == 'add' then
            expr=string.format("%s %s dev %s root handle %s: %s htb default %s ",
                const_tc_qdisc, act, dev, flow_id, get_stab_string(dev), dec2hexstr(CLASS_HIER['dft']))
            table.insert(tblist,expr)
        end

        -- qdisc 类根
        local ratelimit= bands[k]

        local quan_v=math.ceil(CLASS_HIER['quan_v']* CLASS_HIER['root']['quan'])
        local cid=dec2hexstr(CLASS_HIER['root']['id'])
        local buffer,cbuffer = get_burst(tonumber(ratelimit))
        expr = string.format(" %s %s dev %s parent %s: classid %s:%s htb rate %s%s quantum %d burst %d cburst %d",
            const_tc_class, act, dev, flow_id, flow_id, cid, ratelimit, UNIT, quan_v, buffer, cbuffer)
        table.insert(tblist,expr)

        -- 根上的filter,最高优先级不作限速
        expr=string.format(" %s %s dev %s parent %s: prio %s handle %s fw classid %s:%s",
                const_tc_filter, act, dev, flow_id, CLASS_HIER['root']['fprio'], CLASS_HIER['root']['fwmark'], flow_id, '0')
        table.insert(tblist,expr)

        -- PPP control pkt不限速
        apply_ppp_qdisc(tblist,dev,flow_id)

        local pid=cid   -- 父节点id
        -- child 类
        for seq,chd in pairs(CLASS_HIER['child']) do
            local flow_type=chd

            local cid, lprio = chd['id'], chd['prio']
            local lrate, lceil=math.ceil(ratelimit*flow_type['rate']),math.ceil(ratelimit*flow_type['ceil'])

            -- ceil有特殊的配置
            if flow_type['limit'] then
                lceil=tonumber(flow_type['limit'][dir])
                if lceil <= 1 then
                    lceil = math.ceil(bands[dir] * lceil)
                end
            end

            local real_lceil=get_supressed_ceil(lceil, chd['supress'])

            if lrate > real_lceil then lrate = real_lceil end

            local buffer,cbuffer=get_burst(real_lceil)
            local quan_v = math.ceil(chd['quan']* CLASS_HIER['quan_v'])

            -- class
            expr=string.format(' %s %s dev %s parent %s:%s classid %s:%s htb rate %s%s ceil %s%s ' ..
                'prio %s quantum %s burst %d cburst %d', const_tc_class, act, dev, flow_id, pid, flow_id,
                dec2hexstr(cid), lrate, UNIT, real_lceil, UNIT, lprio, quan_v, buffer, cbuffer)
            table.insert(tblist, expr)

            -- highest-prio-filter
            if htb_cfg.qos['small'] and flow_type['highest_prio'] then
                -- arp, 小包 直接进 x:1优先级队列
                apply_arp_small_filter(tblist, dev, 'add', flow_id, dec2hexstr(cid))
            end

            -- filters
            if flow_type['fwmark'] and flow_type['fwmark'] ~= '' then
                if act == 'add' then
                    -- filter
                    expr=string.format(" %s %s dev %s parent %s: prio %s handle %s fw classid %s:%s",
                    const_tc_filter, act, dev, flow_id, flow_type['fprio'], flow_type['fwmark'], flow_id, dec2hexstr(cid))
                    table.insert(tblist,expr)

                    -- leaf, only add
                    apply_leaf_qdisc(tblist,dev,flow_id,dec2hexstr(cid),real_lceil)
                end
            else
                -- 没有fwmark，表示此节点下有子节点
                host_root_cache[k]={
                    id=cid,rate=lrate,ceil=real_lceil,
                }

                if not apply_hosts_qdisc_class_filter(tblist, dev, dir, flow_id, lrate, real_lceil, act, cid) then
                    logger(3,'gen all hosts rules failed.')
                    return false
                end
            end

        end

    end

    return true

end

local function apply_qdisc_class_filter(tblist, devs, act, bands, clevel)
    local ret=false
    if clevel == '2' then
        ret = apply_qdisc_class_filter_for_host(tblist, devs, act, bands, clevel)
    elseif clevel == '1' then
        ret = apply_qdisc_class_filter_for_root(tblist, devs, act, bands, clevel)
    else
        logger(3,'not supported changed-level.')
        return false
    end
    return ret
end

-- htb适用的special rule
local special_rule={
    ['HIGH_PRIO_WITHOUT_LIMIT']={
        ftprio='2',
        flow='0',       -- 优先级最高，不受qos影响
    },
    ['HIGH_PRIO_WITH_BANDLIMIT']={
        ftprio='2',
        flow='2000',    -- 优先级较高
    },
}

-- 更新特殊设备的分流规则，分到高级优先级队列
local function apply_special_host_prio_filter(tblist, devs)

    local tmp_tblist={}
    for k, v in pairs(devs) do
        local dir,dev,flow_id=k,v['dev'],v['id']

        -- 先删除所有已经存在的优先级filter
        for type,rule in pairs(special_rule) do
            local expr=string.format("%s del dev %s parent %s: prio %s ",
                const_tc_filter, dev, flow_id, rule.ftprio)
            table.insert(tmp_tblist,expr)
        end

        -- 为所有的special host增加filter
        for k, v in pairs(special_host_list.host) do
            if special_rule[v] then
                local prio = special_rule[v].ftprio
                local flow = special_rule[v].flow
                local nid=tonumber(string.split(k,'.')[4])
                nid='0x' .. dec2hexstr(nid) .. '000000/0xff000000'
                local expr = string.format(" %s replace dev %s parent %s: prio %s handle %s fw classid %s:%s ",
                const_tc_filter, dev, flow_id, prio, nid, flow_id, flow)
                table.insert(tblist, expr)
            end
        end
    end

    -- 执行删除先,因为删除不需要care结果(注意这里是tmp_tblist)
    exec_cmd(tmp_tblist,1)

    return true
end

-- 当带宽发生变化时，需要重新计算对应预留带宽的值
local function update_reserve_band()

    for type,v in pairs(band_reserve_rule) do
        if v['band'] then
            for k, bands in pairs(v) do
                if k ~= 'band' then
                    if tonumber(cfg.bands.DOWN) > bands['id'] then
                        band_reserve_rule[type]['band'] = bands['band']
                    else
                        break
                    end
                end
            end
        end
    end
end

function qdisc_df.read_qos_config()
    -- 如果band变化了，需要更新预留标准
    if cfg.bands.changed then
        update_reserve_band()
    end

    -- 读取group-host的配置
    if not read_qos_group_config() then
        logger(3,'read_qos_group_config failed.')
        return false
    end

    -- 读取guest的配置
    if not read_qos_guest_xq_config() then
        logger(3,'read_qos_guest_xq_config failed.')
        return false
    end
end

-- dataflow的qdisc规则应用
function qdisc_df.apply(origin_qdisc, bands,devs, clean_flag)

    -- logger(3,'---apply htb host--------.')

    -- origin_qdisc来决定如何处理已经存在的qdisc
    local act,clevel='add','0'
    if not origin_qdisc then    -- origin qdisc空
        -- check changed
        clevel=changed_level()

        clevel = '1'    -- 规则全部重建
        act = 'add'
    elseif not qdisc[origin_qdisc] then     --origin qdisc对应的处理函数空
        logger(3, 'ERROR: qdisc `' .. origin_qdisc .. '` not found. ')
        return false
    elseif clean_flag then      -- 恒定清除
        qdisc_df.clean(devs)
        act = 'add'
    elseif origin_qdisc == THIS_QDISC then      -- 原始qdisc与当前qdisc相同
        -- check changed
        clevel=changed_level()
        if clevel == '0' then   -- 无change，则直接返回,不用更新counter值
            return false
        end
        act = 'change'
    else                                        -- 原始qdisc与当前qdisc不同
        qdisc_df.clean(devs)
        -- check changed
        clevel=changed_level()
        clevel = '1'    -- 规则全部重建
        act = 'add'
    end

    local tblist={}
    if not apply_qdisc_class_filter(tblist,devs,act,bands, clevel) then
        logger(3, 'ERROR: generate host qdisc failed. ')
        return false
    end

    -- apply rule for special devs
    if not apply_special_host_prio_filter(tblist,devs) then
        return false
    end

    if not exec_cmd(tblist, nil) then
        logger(3, 'ERROR: apply host qdisc failed.')
        return false
    end

    return true
end






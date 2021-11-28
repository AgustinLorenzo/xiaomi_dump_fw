#!/usr/bin/lua
--[[
主要功能点：
1. 主网中未设置限速的设备，按照流量服务类型分类，默认按照game,web,video,other顺序分类
2. 当有新设备上线，a:如果设备是被限速的，则新添加一个节点用于这个用户，否则，走数据服务队列
3. 当设备下线后5分钟，将对应设备节点删除
4. guest网络设备不进行服务QoS，只做整体限速
5. 每个队列的预留带宽hardcode

主要适用的场景:
1. 大部分设备都不会被限制最高带宽,这些设备在同时抢占带宽的时候是均分带宽的
2. 少量设备会被限制最高带宽
3. 所有设备的流量的优先级都会按照流量类型优先排序
4. 并非所有设备都会同时占用大量带宽
5. 并不保证同时想占满带宽的设备是平均分配带宽的
--]]

require 'miqos.common'

local THIS_QDISC='wangzhe' -- 流队列的配置

-- 将对应的处理方法加入qdisc表
local qdisc_df ={}
qdisc[THIS_QDISC]= qdisc_df

local lip  = require "luci.ip"

local service_cfg={
    qos={ack=false,syn=true,fin=true,rst=true,icmp=true,small=false},    -- 优先级的包
    online_timeout={wl=5,wi=300},   -- 在线超时时间判断
}

-- layer1
local CLASS_HIER ={
    dft=0x5000,         -- 默认数据走最低优先级队列
    quan_v=1600,        -- quan > MTU,否则可能发不出包
    ['root']={
        id=0x1000,
        quan=2,
        fwmark= '0x00010000/0x000f0000',         -- 最高优先级
        fprio='5'
    },
    ['child']={
        -- speical节点
        ['special']={          -- 优先级队列不再保留其他队列，所有优先处理的都流到这个队列
            id=0x2000,
            prio='1',
            quan=2,
            fwmark='0x00020000/0x000f0000',
            fprio='5',
            rate=0.10,
            ceil=0.50,
            highest_prio=apply_arp_small_filter,  -- 优先级队列的callback --[在有游戏流之后取消小包优先]
        },
        -- 主网节点
        ['host']={
            id=0x3000,
            prio='4',
            quan=2,
            fwmark='0x00030000/0x000f0000',
            fprio='5',      -- 主网数据默认的mark-filter
            rate=0.70,
            ceil=0.98,
            supress=2048,   -- 如果存在游戏的流量,则对host进行带宽压制
        },
        -- guest节点
        ['guest']={
            id=0x4000,
            prio='6',
            quan=1,
            fwmark='0x00040000/0x000f0000',
            fprio='5',
            rate=0.1,
            ceil=0,             --ceil为0,通过limit来控制可配置的ceil限速
            limit=cfg.guest,    -- guest的最高限速
        },
        -- xq节点
        ['xq']={
            id=0x5000,
            prio='7',
            quan=1,
            fwmark='0x00050000/0x000f0000',
            fprio='5',
            rate=0.05,
            ceil=0,
            limit=cfg.xq,        -- xq的最高限速
        },
        -- leteng节点
        --[[
        ['leteng']={
            id=0x6000,
            prio='8',
            quan=1,
            fwmark='0x00060000/0x000f0000',
            fprio='5',
            rate=0.05,
            ceil=0,
            bandlimit=cfg.leteng,        -- leteng的最高限速
        }
        --]]
    }
}

--layer2, host的扩展，以服务区分队列
local CLASS_HIER_host_ext ={
    ['game']={
        id=0x1,
        type='game',
        rate=0.10,
        ceil=0.6,
        mark={
            fwmark='0x00130000/0x00ff0000',
            fprio='4',
        },
    },
    ['web']={
        id=0x2,
        type='web',
        rate=0.35,
        ceil=1.00,
        mark={
            fwmark='0x00230000/0x00ff0000',
            fprio='4',
        },
    },
    ['video']={
        id=0x3,
        type='video',    -- video 需要做稍大预留
        rate=0.45,
        ceil=1.00,
        mark={
            fwmark='0x00330000/0x00ff0000',
            fprio='4',
        },
    },
    ['download']={
        id=0x4,
        type='download',
        rate=0.10,
        ceil=0.95,
        mark={
            fwmark='0x00430000/0x00ff0000',
            fprio='4',
        },
        default=true,
    },
}

-- 在线device列表信息
local device_list={}
local online_device_list={}
--


-- 在清除所有的规则后，需要清除已经记录的设备列表
local function clean_device_list()
    for _ip,_dev in pairs(device_list) do
        device_list[_ip].net = nil
        device_list[_ip].limit = nil
        device_list[_ip] = nil
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

    -- 清除设备列表以便于重建
    clean_device_list()

    cfg.qos_type.changed = true
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


-- 规则后更新device列表信息
local function update_device_list_post_rule()
    for _ip,_dev in pairs(device_list) do
        if _dev.net['new'] == '' then       -- 删除已经下线的设备
            device_list[_ip].net = nil
            device_list[_ip].limit = nil
            device_list[_ip] = nil
        else
            _dev.net['old']=_dev.net['new']
            _dev.net['new']=''
            _dev.limit['changed']=0
        end
    end
end

local function not_wangzhe_dev(ip)
    for _ip,_dev in pairs(cfg.wangzhe.iplist) do
        logger(3,'devip: '.._dev.devip..' ip: '..ip)
        if _dev.devip == ip then
            logger(3,'not wangzhe dev false ')
            return false
        end
    end

    return true
end

-- 规则前更新device列表信息
-- 假定： 同一mac可以有不同ip，但是所有的ip地址唯一，相同ip地址将被认为是一个设备
-- 只留存/更新有限速配置的设备
local function update_device_list_pre_rule()

    local ret=g_ubus:call("trafficd","hw",{})

    -- 更新new ipmac 表
    for _,v in pairs(ret or {}) do
        local mac, wifi=v['hw'], false
        if string.find(v['ifname'],"wl",1) then
            wifi = true  -- wifi device
        end

        for _,ips in pairs(v['ip_list'] or {}) do
            local valid_ip = false
            -- 检查ip地址的在线状态by ageingtime
            if wifi and v['assoc'] == 1 then     -- wifi, assoc会在掉线后立即变成0
                valid_ip = true
            elseif not wifi and ips['ageing_timer'] <= service_cfg.online_timeout.wi then  -- wire
                valid_ip = true
            end

            if valid_ip then
                -- 判断主副网络
                local net_type = 'guest'  -- 默认先划到guest网络
                local ip,valid_ip,nid = ips['ip'], false, string.split(ips['ip'],'.')[4]
                if cfg.lan.ip and cfg.lan.mask then
                    local same_subnet = if_ip_in_same_subnet(ip, cfg.lan.ip, tonumber(cfg.lan.mask))

                    if same_subnet then     -- host网络
                        net_type = 'host'
                    end
                end

                -- 获取设备的maxlimit限速,在cfg.wangzhe.iplist中的设备不做限速
                local max_up,max_down=0,0
                local not_wangzhe = not_wangzhe_dev(ip)

                if not_wangzhe then
                    max_up = cfg.wangzhe.devbands.UP
                    max_down = cfg.wangzhe.devbands.DOWN
                end

                -- 不需要单独做限速的设备(未设置限速，或者限速超出范围)
                if (max_up == 0 ) or (max_down == 0 ) then
                    if device_list[ip] then
                        device_list[ip].net.new = ''   -- 需要删除此节点
                    end
                else
                    -- 更新device状态信息
                    if not device_list[ip] then  -- 新加入的设备
                        device_list[ip]={
                            mac=mac,
                            id=nid,     -- 如果nid为空，则不需要单独进行限速
                            ip=ip,
                            net={old='',new=net_type},  -- 初始化
                            limit={
                                UP=max_up,
                                DOWN=max_down,
                                changed=1,
                            },
                        }
                    else
                        local dev = device_list[ip]
                        dev.net['new'] = net_type
                        if dev.limit.UP ~= max_up or dev.limit.DOWN ~= max_down then
                            logger(3,"limit changed, mac: " .. mac .. ',ip: ' .. ip ..',UP:'
                                ..dev.limit.UP..'->'..max_up..',DOWN:'..dev.limit.DOWN..'->'..max_down)
                            device_list[ip]['limit']={      -- 更新如果最高限速条件改变
                                UP=max_up,
                                DOWN=max_down,
                                changed=1
                            }
                        end
                    end
                end
            end
        end
    end

end

local function get_flow_seq_prio(seq,flow_type)
    local prio_seq=seq_prio[seq] or seq_prio['auto']
    return prio_seq[flow_type] or prio_seq['download']
end

-- 应用每个设备单独的规则
local function apply_rule_for_single_device(tblist, devs, act, parent, device)

    local nCls,expr = #(CLASS_HIER_host_ext),''
    local device_id =device.id
    local host_root_id=parent + device_id*0x10
    local limit = device.limit

    --if math.ceil(limit.UP) > math.ceil(cfg.bands.UP) then limit.UP = cfg.bands.UP end
    --if math.ceil(limit.DOWN) > math.ceil(cfg.bands.DOWN) then limit.DOWN = cfg.bands.DOWN end

    local symbol='*'
    if act == 'add' then symbol = '+' elseif act == 'del' then symbol = '-' end
    logger(3, symbol .. ', ip:'..device.ip..',mac:'..device.mac..', UP:'..device.limit.UP .. ', DOWN:'..device.limit.DOWN)

    local FIX_prio_str=''
    if QOS_VER == 'FIX' then
        FIX_prio_str = ' prio 4 '
    end

    -- 遍历每个限速网卡设备
    for dir,v in pairs(devs) do
        local dev,flow_id = v['dev'],v['id']
        local rate,ceil=limit[dir], limit[dir]
        logger(3, 'rate: '..rate..' ceil: '..ceil)
        local buffer,cbuffer=get_burst(ceil)
        logger(3, 'buffer: '..buffer..' cbuffer: '..cbuffer)
        local quantum= CLASS_HIER['quan_v']*2   -- 假定每个用户2倍的quan

        -- rate should be less then ceil
        if rate > ceil then rate = ceil end

        -- device的主节点
        if act == 'del' then
            expr=string.format("%s %s dev %s classid %s:%s ",const_tc_class, act, dev, flow_id, dec2hexstr(host_root_id))
            table.insert(tblist,1,expr)    -- insert from backend
        elseif act == 'change' then
            expr = string.format(
                "%s %s dev %s parent %s:%s classid %s:%s htb rate %s%s ceil %s%s %s burst %d cburst %d quantum %s",
                const_tc_class, act, dev, flow_id, dec2hexstr(parent), flow_id, dec2hexstr(host_root_id), rate, UNIT,
                ceil, UNIT, FIX_prio_str, buffer, cbuffer, quantum)
            table.insert(tblist,1,expr)     -- change
        else
            expr = string.format(
                "%s %s dev %s parent %s:%s classid %s:%s htb rate %s%s ceil %s%s %s burst %d cburst %d quantum %d ",
                const_tc_class, act, dev, flow_id, dec2hexstr(parent), flow_id, dec2hexstr(host_root_id), rate, UNIT,
                ceil, UNIT, FIX_prio_str, buffer, cbuffer, quantum)
            table.insert(tblist,expr)  -- add
        end

        -- device 的服务分节点
        local default_flow_id=0
        for _type,cls in pairs(CLASS_HIER_host_ext) do
            local filter_flow_id= device_id*0x10 + cls.id  -- filter 用的id
            local class_flow_id= parent + filter_flow_id   -- class 用的id

            if act == 'del' then
                expr=string.format("%s %s dev %s classid %s:%s ", const_tc_class, act, dev, flow_id, dec2hexstr(class_flow_id))
                table.insert(tblist, 1, expr)
            else
                local lrate,lceil=math.ceil(rate*cls.rate),math.ceil(ceil*cls.ceil)
                local buffer,cbuffer=get_burst(lceil)
                local lprio=get_flow_seq_prio(cfg.flow.seq,_type)

                expr = string.format("%s %s dev %s parent %s:%s classid %s:%s htb rate %s%s ceil %s%s prio %s " ..
                    "quantum %s burst %d cburst %d ", const_tc_class, act, dev, flow_id, dec2hexstr(host_root_id),
                    flow_id, dec2hexstr(class_flow_id), lrate, UNIT, lceil, UNIT, lprio , quantum, buffer, cbuffer)
                if act == 'change' then
                    table.insert(tblist, 1, expr)
                else
                    table.insert(tblist, expr)
                    -- add qdisc for leaf node
                    apply_leaf_qdisc(tblist,dev,flow_id,dec2hexstr(class_flow_id),lceil,true)
                end
            end

            -- filter
            local fprio='2'
            expr = string.format("%s %s dev %s parent %s: prio %s handle 0x%s00000/0xfff00000 fw classid %s:%s ",
                const_tc_filter, act, dev, flow_id , fprio, dec2hexstr(filter_flow_id), flow_id, dec2hexstr(class_flow_id))
            if act == 'del' then
                table.insert(tblist, 1, expr)
            elseif act == 'change' then
                -- filter is not changed.
            else
                table.insert(tblist,expr)
            end

            if cls.default then
                default_flow_id = class_flow_id
                -- add default filter for non-recognized flow
                if default_flow_id ~= 0 then
                    local fprio_default='3'
                    expr = string.format("%s %s dev %s parent %s: prio %s handle 0x%s000000/0xff000000 fw classid %s:%s ",
                        const_tc_filter, act, dev, flow_id , fprio_default, dec2hexstr(device_id), flow_id, dec2hexstr(default_flow_id))
                    if act == 'del' then
                        table.insert(tblist, 1, expr)
                    elseif act == 'change' then
                    -- filter is not changed.
                    else
                        table.insert(tblist,expr)
                    end
                end
            end
        end
    end

    return true
end


-- 根据限速规则已有基础规则上更新devices的限速规则（主规则不变）
local function apply_devices_rules(devs, host_net_parent,guest_net_parent)
    local tblist={}
    -- 规则应用前更新设备列表
    update_device_list_pre_rule()

    logger(3,'===================  wangzhe apply device rules ================')
    for _ip,_dev in pairs(device_list) do
        if _dev.net.old == '' then      -- 全新的设备节点
            if _dev.net.new == 'host' then --暂时只支持主网络
                if _dev.limit.UP ~= 0 or _dev.limit.DOWN ~= 0 then  -- 需要进行限速
                    --主网络新增限速节点
                    apply_rule_for_single_device(tblist, devs, 'add', host_net_parent, _dev)
                end
            end
        elseif _dev.net.old == 'host' then      -- 设备以前是在主网络中
            if _dev.net.new == 'guest' then
                -- 1. 主网络删除限速节点
                apply_rule_for_single_device(tblist, devs, 'del', host_net_parent, _dev)
                -- 2. 访客网络增加节点（暂不支持访客网络，TODO）
            elseif _dev.net.new == 'host' then
                if _dev.limit.changed == 1 then     -- 需要更新设备的最高限速值
                    apply_rule_for_single_device(tblist, devs, 'change', host_net_parent, _dev)
                end
            else
                apply_rule_for_single_device(tblist, devs, 'del', host_net_parent, _dev)
            end
        else -- 设备以前是在访客网络中
            if _dev.net.new == 'host' then
                -- 1. 首先从访客网络中删除此节点（TODO）
                -- 2. 然后在添加到主网络中
                apply_rule_for_single_device(tblist, devs, 'add', host_net_parent, _dev)
            else
                -- 修改访客网络中节点的限速值（TOOD）
            end
        end
    end

    -- 规则应用后更新设备列表
    update_device_list_post_rule()

    if not exec_cmd(tblist,nil) then
        logger(3, 'ERROR: apply sigle-device rule failed!')
        return false
    end

    return true
end

function qdisc_df.changed()
    local flag=false
    local strlog=''

    if cfg.wangzhe.changed then
        strlog = strlog .. '/wangzhe'
        --cfg.wangzhe.changed=false
        flag=true
    end

    --[[
    if cfg.leteng.changed == 1 then
        strlog = strlog .. '/leteng'
        cfg.leteng.changed = 0
        flag = true
    end
    --]]

    return flag
end

-- 应用整个HTB规则树（主框架只需要整体清除，然后再添加，所以不需要分步删除，只保留add）
local function apply_service_main_qdisc_class_filter(devs, bands)

    local tblist={}
    local expr, act='','add'
    for dir, v in pairs(devs) do
        local dev,flow_id=v['dev'],v['id']
        local ratelimit= bands[dir]
        local quan_v=math.ceil(CLASS_HIER['quan_v']* CLASS_HIER['root']['quan'])
        local root_class_id=dec2hexstr(CLASS_HIER['root']['id'])
        local buffer,cbuffer=get_burst(ratelimit)

        -- qdisc
        expr=string.format("%s %s dev %s root handle %s: %s htb default %s ",
            const_tc_qdisc, act, dev, flow_id, get_stab_string(dev), dec2hexstr(CLASS_HIER['dft']))
        table.insert(tblist,expr)

        -- class
        expr = string.format("%s %s dev %s parent %s: classid %s:%s htb rate %s%s quantum %d burst %d cburst %d",
            const_tc_class, act, dev, flow_id, flow_id, root_class_id, ratelimit, UNIT, quan_v, buffer, cbuffer)
        table.insert(tblist,expr)

        -- 根上的filter,最高优先级不作限速
        expr=string.format("%s %s dev %s parent %s: prio %s handle %s fw classid %s:%s",
            const_tc_filter, act, dev, flow_id, CLASS_HIER['root']['fprio'], CLASS_HIER['root']['fwmark'], flow_id, '0')
        table.insert(tblist,expr)

        -- PPP的LCP/NCP控制数据包不限速
        apply_ppp_qdisc(tblist,dev,flow_id)

        local parent_class_id=root_class_id   -- 父节点id

        -- 子类（special队列，主网类，访客网，路由）
        for _cls_name, _chd in pairs(CLASS_HIER['child']) do
            local class_id, lprio = _chd['id'], _chd['prio']
            local lrate=math.ceil(ratelimit*_chd['rate'])
            local lceil=math.ceil(ratelimit*_chd['ceil'])

            -- ceil有特殊的配置
            if _chd['limit'] then
                lceil=math.ceil(_chd['limit'][dir])
                if lceil <= 1 then
                    lceil = math.ceil(ratelimit * lceil)
                end
            end

            -- 计算host的压制带宽
            if _cls_name == 'host' then
                lceil = get_supressed_ceil(lceil, _chd['supress'])
            end

            if lrate > lceil then lrate = lceil end

            --[[
            if _cls_name == 'leteng' then
                lceil = tonumber(cfg['leteng'][dir])
                lrate = lceil
            end
            --]]

            if lceil ~= 0 then
                local buffer,cbuffer=get_burst(lceil)
                local quan_v = _chd['quan']* CLASS_HIER['quan_v']

                -- 子类的class
                expr=string.format('%s %s dev %s parent %s:%s classid %s:%s htb rate %s%s ceil %s%s ' ..
                    'prio %s quantum %s burst %d cburst %d', const_tc_class, act, dev, flow_id, parent_class_id, flow_id,
                    dec2hexstr(class_id), lrate, UNIT, lceil, UNIT, lprio, quan_v, buffer, cbuffer)
                table.insert(tblist, expr)

                if _cls_name == 'special' then  -- special队列: arp, 小包 直接进
                    if service_cfg.qos['small'] and _chd['highest_prio'] then
                        _chd['highest_prio'](tblist, dev, act, flow_id, dec2hexstr(class_id))
                    end
                elseif _cls_name == 'host' then  -- 主网络
                    local _parent = class_id
                    local _default_host_classid=''
                    for _service_name, _service in pairs(CLASS_HIER_host_ext) do
                        local _this_class=_parent + _service.id
                        local _this_rate,_this_ceil = math.ceil(lrate*_service.rate),math.ceil(lceil*_service.ceil)


                        if _this_rate > _this_ceil then _this_rate = _this_ceil end

                        local _this_prio=get_flow_seq_prio(cfg.flow.seq,_service_name)  -- TODO
                        expr = string.format("%s %s dev %s parent %s:%s "..
                            "classid %s:%s htb rate %s%s ceil %s%s prio %s "..
                            "quantum %s burst %d cburst %d ", const_tc_class,
                            act, dev, flow_id,  dec2hexstr(_parent),
                            flow_id, dec2hexstr(_this_class), _this_rate, UNIT, _this_ceil, UNIT, _this_prio, quan_v, buffer, cbuffer)
                        table.insert(tblist, expr)

                        -- 叶子节点
                        apply_leaf_qdisc(tblist,dev,flow_id,dec2hexstr(_this_class),_this_ceil,true)

                        -- filter
                        if _service.mark['fwmark'] and _service.mark['fwmark'] ~= '' then
                            expr=string.format("%s %s dev %s parent %s: prio %s handle %s fw classid %s:%s",
                                const_tc_filter, act, dev, flow_id, _service.mark['fprio'], _service.mark['fwmark'], flow_id, dec2hexstr(_this_class))
                            table.insert(tblist, expr)
                        end

                        if _service.default then
                            --默认host的filter
                            expr=string.format("%s %s dev %s parent %s: prio %s handle %s fw classid %s:%s",
                                    const_tc_filter, act, dev, flow_id, _chd['fprio'], _chd['fwmark'], flow_id, dec2hexstr(_this_class))
                            table.insert(tblist, expr)
                        end
                    end


                end

                -- just filter fmark
                if _cls_name ~= 'host' and _cls_name ~= 'leteng' then
                    if _chd['fwmark'] and _chd['fwmark'] ~= '' then
                        expr=string.format("%s %s dev %s parent %s: prio %s handle %s fw classid %s:%s",
                            const_tc_filter, act, dev, flow_id, _chd['fprio'], _chd['fwmark'], flow_id, dec2hexstr(class_id))
                        table.insert(tblist, expr)

                        -- leaf, only add
                        apply_leaf_qdisc(tblist,dev,flow_id,dec2hexstr(class_id),lceil, true)
                    end
                end

                --[[
                if _cls_name == 'leteng' then
                    if _chd['fwmark'] and _chd['fwmark'] ~= '' then
                        expr=string.format("%s %s dev %s parent %s: prio %s handle %s fw classid %s:%s",
                            const_tc_filter, act, dev, flow_id, _chd['fprio'], _chd['fwmark'], flow_id, dec2hexstr(class_id))
                        table.insert(tblist, expr)
                    end
                end
                --]]
            end
        end
    end

    if not exec_cmd(tblist,nil) then
        logger(3, 'ERROR: apply mainframe failed.')
        return false
    end

    return true
end

--[[
local function change_leteng_node_limit(node_name, devs, bands)
    local tblist={}
    local act,expr='change',''
    local flow_id,fprio,fwmark
    if not CLASS_HIER['child'][node_name] then
        logger(3,'ERROR: no such node named ' .. node_name .. ' in mainframe.')
        return false
    end

    local class=CLASS_HIER['child'][node_name]

    for _dir,v in pairs(devs) do
        local dev,flow_id=v['dev'],v['id']
        local class_id, parent_id = class.id, CLASS_HIER['root'].id
        local ratelimit=bands[_dir]
        local lrate=math.ceil(class.rate)

        local lprio=class.prio
        lceil = tonumber(cfg['leteng'][_dir])
        if lceil == 0 then
            logger(3,'ERROR: leteng band is 0 ')
            return false
        end

        lrate = lceil

        local lprio=class.prio
        local buffer,cbuffer=get_burst(lceil)
        local quan_v = class['quan']* CLASS_HIER['quan_v']

        expr=string.format('%s %s dev %s parent %s:%s classid %s:%s htb rate %s%s ceil %s%s ' ..
                'prio %s quantum %s burst %d cburst %d', const_tc_class, act, dev, flow_id, dec2hexstr(parent_id), flow_id,
                dec2hexstr(class_id), lrate, UNIT, lceil, UNIT, lprio, quan_v, buffer, cbuffer)
            table.insert(tblist, expr)
        table.insert(tblist, expr)
    end

    if not exec_cmd(tblist,nil) then
        logger(3, 'ERROR: apply mainframe failed.')
        return false
    end

end

local function check_if_need_update_leteng_network(devs, bands)
    local strlog,flag='', false
    if cfg.leteng.changed == 1 then       -- guest限速变化
        strlog = strlog .. '/guest'
        cfg.leteng.changed = 0
        flag = true
    end

    if strlog ~= '' then
        logger(3,'CHANGE: ' .. strlog)
    end

    if flag then
        change_leteng_node_limit('leteng', devs, bands)
    end
end
--]]

local function check_if_need_update_service_mainframe(devs, bands)
    local flag = true
    logger(3,'CHANGE: wangzhe')

    logger(3,'===================  wangzhe update mainframe ==============')
    qdisc_df.clean(devs)

    apply_service_main_qdisc_class_filter(devs, bands)

    --check_if_need_update_guest_network(devs,bands)
    --check_if_need_update_xq_network(devs,bands)
    --check_if_need_update_leteng_network(devs,bands)

    return flag
end

function qdisc_df.read_qos_config()
    --read_qos_leteng_config()
    return true
end

-- dataflow的qdisc规则应用
-- clean_flag: clean whole rules before applying new rule if true
function qdisc_df.apply(devs, clean_flag)

    logger(3,'===================  wangzhe apply =================')
    -- 更新mainframe框架
    if clean_flag or cfg.wangzhe.bandchanged then
        check_if_need_update_service_mainframe(devs, cfg.wangzhe.bands)
        cfg.wangzhe.cleanflag=false
        cfg.wangzhe.bandchanged=false
    end

    --cfg.wangzhe.changed=false
    -- host_parent节点上刷新devices规则
    apply_devices_rules(devs, CLASS_HIER['child']['host'].id,CLASS_HIER['child']['guest'].id)

    return true
end


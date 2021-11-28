#!/usr/bin/lua
--通过data flow进行队列分流,使用算法prio，默认在qos off的时候启用

require 'miqos.common'

if not qdisc then qdisc = {} end

-- 流队列的配置
local THIS_QDISC='prio'
local FLOW_TYPE={
    high={
        {
        fwmark='0x00010000/0x000f0000',         --messagagent
        fprio='4',
        },
    },
    game={
        {
            fwmark='0x00020000/0x000f0000',     --特殊调整的高优先级
            fprio='4',
        },
        {
            fwmark='0x00130000/0x00ff0000',     --用户的game包
            fprio='5',
        },
    },
    web={
        {
            fwmark='0x00230000/0x00ff0000',     --用户的web包
            fprio='5',
        },
    },
    video={
        {
            fwmark='0x00330000/0x00ff0000',     --用户的video包
            fprio='5',
        },
    },
    other={
        {
            fwmark='0x00430000/0x00ff0000',     --用户的下载包
            fprio='5',
        },
    },
    guest={
        {
            fwmark='0x00040000/0x000f0000',     --guest网络
            fprio='4',
        },
    },
    xq={
        {
            fwmark='0x00050000/0x000f0000',     --小强的所有其他数据
            fprio='4',
        },
    },
    --[[
    leteng={
        {
            fwmark='0x00060000/0x000f0000',     --小强的所有其他数据
            fprio='4',
        },
    }
    --]]
}

local prio_cfg={
    qos={small=false},
}

local CLASS_HIER ={
    dft=0x7000,      -- qdisc默认的队列最低优先级队列
    quan_v=1500,  -- quan 至少必须 > MTU,否则会出现发不出包的情况
    ['root']={
        id=0x1000,
        quan=8,
    },
    ['child']={
        {
            id=1,
            prio='1',
            type='high',
            cid=1,
        },
        {
            id=2,
            prio='2',
            type='game',
            cid=2,
        },
        {
            id=3,
            prio='3',
            type='web',
            cid=3,
        },
        {
            id=4,
            prio='4',
            type='video',
            cid=4,
        },
        {
            id=5,
            prio='5',
            type='other',
            cid=5,
        },
        {
            id=6,
            prio='6',
            type='guest',
            limit=cfg.guest,
            cid=11,
        },
        {
            id=7,
            prio='7',
            type='xq',
            limit=cfg.xq,
            cid=12,
        },
        --[[
        {
            id=8,
            prio='8',
            type='leteng',
            bandlimit=cfg.leteng,
            cid=13,
        },
        --]]
    }
}

-- 将对应的处理方法加入qdisc表
local qdisc_df ={}
qdisc[THIS_QDISC]= qdisc_df

-- 清理qdisc规则
function qdisc_df.clean(devs)
    local tblist={}
    for _,dev in pairs(devs or {}) do
        local expr = string.format("%s del dev %s root ", const_tc_qdisc, dev.dev)
        table.insert(tblist,expr)
    end
    if not exec_cmd(tblist,1) then
        logger(3, 'ERROR: clean qdisc rules for dataflow mode failed!')
    end
end

-- 检测影响prio的因素是否变化
-- 1.整体带宽值;2.guest带宽限制变化
function qdisc_df.changed()
    local flag=false
    local strlog=''
    if cfg.bands.changed then
        strlog = strlog .. '/band'
        cfg.bands.changed=false
        flag=true
    end

    if cfg.guest.changed == 1 then       -- guest限速变化
        strlog = strlog .. '/guest'
        cfg.guest.changed = 0
        flag = true
    end

    --[[
    if cfg.leteng.changed == 1 then
        strlog = strlog .. '/leteng'
        cfg.leteng.changed = 0
        flag = true
    end
    --]]

    if special_host_list.changed then
        strlog = strlog .. '/speical host list'
        special_host_list.changed = false
        flag = true
    end

    if strlog ~= '' then
        logger(3,'CHANGE: ' .. strlog)
    end

    return flag
end

function qdisc_df.read_qos_config()
    --read_qos_leteng_config()
    if not read_qos_guest_xq_config(true) then
        logger(3,'read_qos_config failed.')
        return false
    end
end

-- htb适用的special rule
local special_rule={
    ['HIGH_PRIO_WITHOUT_LIMIT']={
        ftprio='1',
        flow='1',       -- 优先级最高，不受qos影响
    },
    ['HIGH_PRIO_WITH_BANDLIMIT']={
        ftprio='2',
        flow='2',    -- 优先级同在第一等级
    },
}

-- 更新特殊设备的分流规则，分到高级优先级队列
local function apply_special_host_prio_filter(tblist,devs)
    local tmp_tblist={}

    for _, var in pairs(devs) do
        local dev,flow_id=var['dev'],var['id']

        -- 先删除所有已经存在的优先级filter
        for _,rule in pairs(special_rule) do
            local expr=string.format("%s del dev %s parent %s: prio %s ",
                const_tc_filter, dev, flow_id, rule.ftprio)
            table.insert(tmp_tblist,expr)
        end

        -- pr(special_host_list.host)

        -- 为所有的special host增加filter
        for k, v in pairs(special_host_list.host) do
            --logger(3,v)
            if special_rule[v] then     -- 判断类型是否存在
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

    -- 执行删除先,因为删除不需要care结果
    exec_cmd(tmp_tblist,1)

    return true
end


-- 生成qdisc
local function apply_qdisc_class_filter(tblist, devs, act, bands)

    local expr=''
    for dir, v in pairs(devs) do
        local dev,flow_id=v['dev'],v['id']
        local num_of_bands=table.getn(CLASS_HIER.child)
        local ratelimit=bands[dir]

        -- prio 根，only for add
        if act == 'add' then
            -- qdisc 根, 将生成7个优先级队列的bands-class, x:1,x:2,x:3,x:4,x:5,x:6
            expr=string.format(" %s %s dev %s root handle %s: prio bands %d priomap 2 3 3 3 2 3 1 1 2 2 2 2 2 2 2 2 ",
                const_tc_qdisc, act, dev, flow_id, num_of_bands)
            table.insert(tblist,expr)
        end

        local fprio,fwmark
        for cid,cls in pairs(CLASS_HIER['child']) do
            if not cls.type or not FLOW_TYPE[cls['type']] then
                logger(3, 'ERROR: exception case: type NULL or not defined in FLOW_TYPE!')
                return false
            end

            for _,type_data in pairs(FLOW_TYPE[cls['type']]) do

                fprio,fwmark = type_data['fprio'],type_data['fwmark']
                expr=string.format(" %s %s dev %s parent %s: prio %s handle %s fw classid %s:%s ",
                    const_tc_filter, act, dev, flow_id, fprio, fwmark, flow_id, cid)
                table.insert(tblist,expr)

                local band_max = 0
                if cls['limit'] then
                    if cls['limit'][dir] <= 0 then
                        band_max = ratelimit
                    elseif cls['limit'][dir] <= 1 then
                        band_max = math.ceil(ratelimit*cls['limit'][dir])
                    else
                        band_max = math.ceil(cls['limit'][dir])
                    end

                    local t_act='replace'       -- 对于tbf限速，直接用replace好了
                    local buffer=math.ceil(band_max*1024/g_CONFIG_HZ)
                    if buffer < 2000 then buffer = 2000 end

                    expr=string.format(" %s %s dev %s parent %s:%s handle %d: tbf rate %s%s buffer %s latency 10ms",
                        const_tc_qdisc, t_act, dev, flow_id, cid, cls['cid'], band_max, UNIT, buffer)
                    table.insert(tblist,expr)

                end
                if cls['bandlimit'] then
                    if tonumber(cls['bandlimit'][dir]) > 0 then
                        --logger(3, 'leteng bandmax: '..cls['bandlimit'][dir]..' dir:'..dir)
                        band_max = tonumber(cls['bandlimit'][dir])
                        local t_act='replace'       -- 对于tbf限速，直接用replace好了
                        local buffer=math.ceil(band_max*1024/g_CONFIG_HZ)
                        if buffer < 2000 then buffer = 2000 end

                        expr=string.format(" %s %s dev %s parent %s:%s handle %d: tbf rate %s%s buffer %s latency 10ms",
                            const_tc_qdisc, t_act, dev, flow_id, cid, cls['cid'], band_max, UNIT, buffer)
                        table.insert(tblist,expr)
                    end
                end
            end

            -- leaf, only for non-tbf
            if not cls['limit'] and not cls['bandlimit']then
                apply_leaf_qdisc(tblist,dev,flow_id,cls['cid'],0)
            end


        end
        if prio_cfg.qos['small'] then
            -- arp, 小包 直接进 x:1优先级队列
            apply_arp_small_filter(tblist, dev, 'add', flow_id, '1')
        end

    end


    -- apply rule for special devs
    if not apply_special_host_prio_filter(tblist,devs) then
        return false
    end

    return true

end


-- qdisc规则应用
function qdisc_df.apply(origin_qdisc, bands, devs, clean_flag)

    -- origin_qdisc来决定如何处理已经存在的qdisc
    local act='add'
    if not origin_qdisc then    -- origin qdisc空
        act = 'add'
    elseif not qdisc[origin_qdisc] then     --origin qdisc对应的处理函数空
        logger(3, 'ERROR: qdisc `' .. origin_qdisc .. '` not found. ')
        return false
    elseif clean_flag then      -- 恒定清除
        qdisc_df.clean(devs)
        act = 'add'
    elseif origin_qdisc == THIS_QDISC then      -- 原始qdisc与当前qdisc相同
        act = 'change'
    else                                        -- 原始qdisc与当前qdisc不同
        qdisc_df.clean(devs)
        act = 'add'
    end

    local tblist={}
    if not apply_qdisc_class_filter(tblist,devs,act,bands) then
        logger(3, 'ERROR: generate prio qdisc failed.')
        return false
    end

    if not exec_cmd(tblist, nil) then
        logger(3, 'ERROR: apply prio qdisc failed.')
        return false
    end

    return true
end



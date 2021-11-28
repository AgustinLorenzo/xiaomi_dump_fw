#!/usr/bin/lua


local px =  require "posix"
local json= require 'json'
QOS_VER='NOIFB'

module("miqos", package.seeall)

function cmd(action)

    require "miqos.common"
    require "miqos.command"
    require "miqos.rule_by_noifb"

    cur_qdisc='noifb'
    local qos_cmd='/usr/sbin/miqosd noifb'
    local args=string.split(action,' ')
    local res={status=4, data='unkown error.'}
    if lock() then
        logger(3,'[NOIFB_QOS_CMD]: miqos '..action..'')
        read_qos_config()
        if qdisc[cur_qdisc] and qdisc[cur_qdisc].read_qos_config then
            qdisc[cur_qdisc].read_qos_config()
        end
        cfg.qos_type.mode = "noifb"  -- 强制为noifb模式
        res,execflag = process_cmd(unpack(args))

        if execflag then    -- 更新qos规则
            logger(3,'execute cmd: '..qos_cmd)
            os.execute(qos_cmd)
        end
        unlock()

    else
        res={status=2,data='command already in running.'}
    end

    return res
end


#!/usr/bin/lua
-- it's executed after OTA to upgrade cft to new version


local bit=  require "bit"
local px =  require "posix"
local uci=  require 'luci.model.uci'
local io=   require 'io'
local socket= require 'socket'
local json= require 'json'

function find_section(curs, conf, type, name)
    local id
    curs:foreach(
        conf, type,
        function(s)
            if s['name'] == name then
                id = s['.name']
            end
        end)
    return id
end

function set_tbl(curs,from_cfg,to_cfg,from_section,to_section)

    local tbl=curs:get_all(from_cfg,from_section)

    -- px.var_dump(tbl)

    for k,v in pairs(tbl) do

        -- print(k .. ':' ..type(v))
        if string.sub(k,1,1) ~= '.' and not curs:get(to_cfg,to_section,k) then
            if type(v) == 'string' then
                curs:set(to_cfg,to_section,k,v)
                -- print('set ' .. k .. ' = ' .. v)
            elseif type(v) == 'table' then
                curs:set_list(to_cfg,to_section,k,v)
            else
                -- print("** origin " .. k .. ' = ' .. v .. ' (' .. type(v) .. ')')
                curs:set(to_cfg,to_section,k,'0')
                -- print('set ' .. k .. ' = ' .. 0)
            end
        end
    end

end

function merge_tbl(curs,from_cfg,to_cfg,type_name,id_name,clearall)

    -- delete all anonemous type
    curs:delete_all(to_cfg,type_name,
        function(s) return s[".anonymous"] end
    )
    if clearall then
        curs:delete_all(to_cfg,type_name,
        function(s) if s['.name']==id_name then return true else return false end end
        )
    end

    local from_sec_name = find_section(curs,from_cfg,type_name,id_name)
    if not from_sec_name then
        return
    end
    local to_sec_name = find_section(curs,to_cfg,type_name,id_name)

    if not to_sec_name then
        to_sec_name = curs:section(to_cfg,type_name,id_name)
    end

    local to_name = curs:get(to_cfg,to_sec_name,'.name')
    if not to_name or to_name ~= id_name then
        curs:set(to_cfg,to_sec_name, '.name', id_name)
    end

    set_tbl(curs,from_cfg,to_cfg,from_sec_name,to_sec_name)
end


function main()

    local from_cfg='miqos_default'
    local to_cfg='miqos'
    local curs = uci.cursor()


    -- below can be changed by user
    merge_tbl(curs,from_cfg,to_cfg,'miqos','settings',nil)
    merge_tbl(curs,from_cfg,to_cfg,'limit','guest',nil)
    merge_tbl(curs,from_cfg,to_cfg,'limit','xq',nil)
    merge_tbl(curs,from_cfg,to_cfg,'system','param',nil)

    -- below are hold by system, cannot be changed by user
    merge_tbl(curs,from_cfg,to_cfg,'group','00',true)
    merge_tbl(curs,from_cfg,to_cfg,'mode','general',true)
    merge_tbl(curs,from_cfg,to_cfg,'class','p1',true)
    merge_tbl(curs,from_cfg,to_cfg,'class','p2',true)
    merge_tbl(curs,from_cfg,to_cfg,'class','p3',true)
    merge_tbl(curs,from_cfg,to_cfg,'class','p4',true)

    curs:save(to_cfg)
    curs:commit(to_cfg)

end

main()






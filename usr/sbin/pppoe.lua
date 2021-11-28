#!/usr/bin/env lua
local posix = require "posix"
local plog = require "posix.syslog"
local json = require "json"
local ubus = require "ubus"

--[[ pppoe exit code
#define EXIT_OK			0
#define EXIT_FATAL_ERROR	1
#define EXIT_OPTION_ERROR	2
#define EXIT_NOT_ROOT		3
#define EXIT_NO_KERNEL_SUPPORT	4
#define EXIT_USER_REQUEST	5
#define EXIT_LOCK_FAILED	6
#define EXIT_OPEN_FAILED	7
#define EXIT_CONNECT_FAILED	8
#define EXIT_PTYCMD_FAILED	9
#define EXIT_NEGOTIATION_FAILED	10
#define EXIT_PEER_AUTH_FAILED	11
#define EXIT_IDLE_TIMEOUT	12
#define EXIT_CONNECT_TIME	13
#define EXIT_CALLBACK		14
#define EXIT_PEER_DEAD		15
#define EXIT_HANGUP		16
#define EXIT_LOOPBACK		17
#define EXIT_INIT_FAILED	18
#define EXIT_AUTH_TOPEER_FAILED	19
#define EXIT_TRAFFIC_LIMIT	20
#define EXIT_CNID_AUTH_FAILED	21
--]]

-- result begin
-- peer no response
local PPPOE_RESULT = {
  ['PEER_NO_RESP'] =  {
    code = 531,
    vcode = 678,
    ppp_exit = '10',
  },
  ['NO_MORE_SESSION'] = {
    code = 530,
    vcode = 633,
    ppp_exit = '20'
  },
  ['AUTH_FAILD'] = {
    code = 507,
    vcode = 691,
    ppp_exit = { ['11'] = true, ['19'] = true}
  }
}

local PPPOE_OTHER_ERROR = {
  [678] = 532,
  [691] = 508
}

-- result end



local config = { last_error = '/tmp/state/pppoe_last_error',
		 debug = nil,
		 check_interval = 2
	      }

LOG = { debug = plog.LOG_DEBUG,
	info = plog.LOG_INFO,
	warning = plog.LOG_WARNING,
	error = plog.LOG_ERR }

function log(level, fmt, ...)
   logstr = string.format(fmt, unpack(arg))
   plog.syslog(level, logstr)
   if config.debug then
      print(logstr)
   end
end

function uconn_read_status(uconn)
   return uconn:call("network.interface", "status", {interface="wan"})
end

function get_if_status(uconn)
   ifst = uconn_read_status(uconn)
   if not ifst then
      uconn:call("network", "reload", {})
      log(LOG.debug, "ubus call network reload")
      posix.sleep(1) -- wait reload
      ifst = uconn_read_status(uconn)
   end
   return ifst
end

function print_usage(proc)
   proc = proc or "pppoe.lua"
   print(string.format("usage: %s <up|down|status>", proc))
   os.exit(1)
end

function action_up(ifst, uconn)
   if ifst.autostart then
      log(LOG.warning, "already start, skip ifup")
      os.exit(1)
   end
   log(LOG.debug, "ifup wan")
   os.execute("ifup wan")
   os.exit(0)
end

function action_down(ifst)
   if ifst.autostart then
      os.execute("ifdown wan")
      log(LOG.info, "put ifdown wan")
      os.exit(0)
   else
      log(LOG.warning, "already down, skip ifdown")
      os.exit(1)
   end
end

function match_pattern(exit_code)
   for key, pattern in pairs(PPPOE_RESULT) do
      local p = pattern.ppp_exit
      if type(p) == 'table' then
	 if p[exit_code] then return pattern end
      else
	 if p == exit_code then return pattern end
      end
   end
   return nil
end

function get_last_error()
   local logfd = io.open(config.last_error)
   if not logfd then return nil end
   local exit_code = logfd:read("*all")
   logfd:close()
   local res = match_pattern(exit_code:gsub('\n*',''))
   if res then
      return { code = res.code, msg = res.vcode }
   else
      return { code = 0, msg = ""}
   end
end

function get_profile_record()
  local uci = require("luci.model.uci").cursor()
  local crypto = require("xiaoqiang.util.XQCryptoUtil")
  local name = uci:get("network", "wan", "username")
  local password = uci:get("network", "wan", "password")

  if not name or not password then
    return 0
  end
  local key = crypto.md5Str(name..password)
  local value = uci:get_all("xiaoqiang", key)
  if value and value.status then
    local num_status = tonumber(value.status)
    return num_status or 0
  end
  return 0
end

function action_status(ifst)
   local status = get_last_error()
   if not status then status = {} end
   if ifst.up then
      status.process = "up"
   elseif ifst.pending then
      status.process = "connecting"
   else
      status.process = "down"
   end
   print(json.encode(status))
   os.exit(0)
end

local status, err = pcall(
   function ()
      local proc = arg[0]
      local action = arg[1]
      if not action then
	 print_usage(proc)
      end
      if action == "up" and action == "down" then
	 posix.daemonize()
      end
      plog.openlog(proc, plog.LOG_PID, plog.LOG_LOCAL7)
      local uconn = ubus.connect()
      local cursor = require("luci.model.uci").cursor()
      local ifst = get_if_status(uconn)
      local proto = cursor:get("network", "wan", "proto")
      if proto ~= "pppoe" then
	 log(LOG.error, "wan proto is not pppoe but %s", proto)
	 os.exit(1)
      end
      if action == "up" then
	 action_up(ifst, uconn)
      elseif action == "down" then
	 action_down(ifst)
      elseif action == "status" then
	 action_status(ifst)
      else
	 print_usage(proc)
	 os.exit(1)
      end
   end
)

if not status then
   log(LOG.error, err)
end

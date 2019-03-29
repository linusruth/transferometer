#!/usr/bin/env lua

-- Copyright (C) 2019 Linus Ruth
--
-- This is free software, licensed under the Apache License, Version 2.0.

local host = {}
local label = {}
local transfer = {}

function Host (table)
  if table.ip then
    host[table.ip] = {
      mac = table.mac,
      keep = false
    }
  end
end

function Label (table)
  if table.mac then
    label[table.mac] = {
      name = table.name,
      tags = table.tags
    }
  end
end

function Transfer (table)
  if table.date then
    transfer[table.date] = {
      bytes_in = table.bytes_in,
      bytes_out = table.bytes_out,
      bytes_total = table.bytes_total
    }
  end
end

local function file_exists (path)
  local file = io.open(path, 'r')
  if file then return file:close() end
  return false
end

local function command_result (command)
  local file = assert(io.popen(command, 'r'))
  local result = file:read('*a')
  file:close()
  return result
end

local function command_result_array (command)
  local file = assert(io.popen(command, 'r'))
  local result = {}
  for line in file:lines() do
    table.insert(result, line)
  end
  file:close()
  return result
end

-- Only one instance of Transferometer should ever be running at any given time.
-- Since the 'mkdir' command is atomic and ubiquitous, a lock directory is used
-- to prevent multiple instances of Transferometer from running simultaneously.
-- The following two functions manage the lock directory.
local function create_lock_directory (lock_directory_path)
  command = 'mkdir ' .. lock_directory_path .. ' 2>/dev/null; printf $?'
  exit_code = command_result(command)
  if exit_code ~= '0' then
    print('Error creating lock directory: ' .. lock_directory_path)
    os.exit(1)
  end
end

local function delete_lock_directory (lock_directory_path)
  command = 'rmdir ' .. lock_directory_path .. ' 2>/dev/null; printf $?'
  exit_code = command_result(command)
  if exit_code ~= '0' then
    print('Error deleting lock directory: ' .. lock_directory_path)
    os.exit(1)
  end
end

-- Create an accounting chain (ex. TRANSFEROMETER_INPUT) for a built-in chain
-- (ex. INPUT) to contain rules for logging host data throughput.
local function create_accounting_chain (built_in_chain)
  os.execute('iptables -t mangle -N TRANSFEROMETER_' .. built_in_chain ..
    ' 1>/dev/null 2>&1')
end

-- Delete an accounting chain (ex. TRANSFEROMETER_INPUT) for a built-in chain
-- (ex. INPUT) including any rules it may contain.
local function delete_accounting_chain (built_in_chain)
  os.execute('iptables -t mangle -F TRANSFEROMETER_' .. built_in_chain ..
    ' 1>/dev/null 2>&1')
  os.execute('iptables -t mangle -X TRANSFEROMETER_' .. built_in_chain ..
    ' 1>/dev/null 2>&1')
end

-- Insert rule necessary to divert packets from a built-in chain
-- (ex. INPUT) to a corresponding accounting chain (ex. TRANSFEROMETER_INPUT).
-- It must be evaluated first, so it will be inserted at the head of the chain.
local function insert_diversion_rule (built_in_chain)
  os.execute('iptables -t mangle -I ' .. built_in_chain ..
    ' -j TRANSFEROMETER_' .. built_in_chain .. ' 1>/dev/null 2>&1')
end

-- Delete rule necessary to divert packets from a built-in chain
-- (ex. INPUT) to a corresponding accounting chain (ex. TRANSFEROMETER_INPUT),
-- including any duplicates of the rule which may exist.
local function delete_diversion_rule (built_in_chain)
  local command = 'iptables -t mangle -D ' .. built_in_chain ..
    ' -j TRANSFEROMETER_' .. built_in_chain .. ' 2>&1'
  repeat until string.match(command_result(command), "%S+")
end

-- Verifies that the rule necessary to divert packets from a built-in chain
-- (ex. INPUT) to a corresponding accounting chain (ex. TRANSFEROMETER_INPUT),
-- exists at the head of the built-in chain, and is unique within it.
-- If either condition is false, then all diversion rules will be deleted
-- and a new diversion rule will be inserted at the head of the built-in chain.
local function maintain_diversion_rule (built_in_chain)
  local command = 'iptables -t mangle -n --line-numbers -L ' ..
    built_in_chain .. ' 2>&1'
  local output = command_result(command)
  local accounting_chain = 'TRANSFEROMETER_' .. built_in_chain

  local rules = {}
  for rule_number in string.gmatch(output, "(%d+)%s*" .. accounting_chain) do
    table.insert(rules, rule_number)
  end

  if rules[1] ~= '1' or #rules ~= 1 then
    delete_diversion_rule(built_in_chain)
    insert_diversion_rule(built_in_chain)
  end
end

-- Processes on the router itself (ping, etc.) send packets
-- via the WAN interface.  The following three functions
-- return information on the WAN interface.
local function wan_interface_name ()
  local command = 'uci get network.wan.ifname'
  local output = command_result(command)
  output = output:gsub('[%c%s]', '')
  return output
end

local function wan_interface_mac_address ()
  local command = 'cat /sys/class/net/' .. wan_interface_name() .. '/address'
  local output = command_result(command)
  output = output:gsub('[%c%s]', '')
  return output
end

local function wan_interface_ip_address ()
  local command = 'ip -4 address show ' .. wan_interface_name() ..
    ' | grep -o inet[^/]* | cut -d \' \' -f 2'
  local output = command_result(command)
  output = output:gsub('[%c%s]', '')
  return output
end

local function insert_interface_rule (built_in_chain, interface_name)
  if built_in_chain == 'OUTPUT' then
    os.execute('iptables -t mangle -o ' .. interface_name ..
      ' -j RETURN -C TRANSFEROMETER_OUTPUT 2>/dev/null')
    os.execute('iptables -t mangle -o ' .. interface_name ..
      ' -j RETURN -A TRANSFEROMETER_OUTPUT')
  elseif built_in_chain == 'INPUT' then
    os.execute('iptables -t mangle -i ' .. interface_name ..
      ' -j RETURN -C TRANSFEROMETER_INPUT 2>/dev/null')
    os.execute('iptables -t mangle -i ' .. interface_name ..
      ' -j RETURN -A TRANSFEROMETER_INPUT')
  end
end

local function insert_host_rule (built_in_chain, host_ip)
  if built_in_chain == 'FORWARD' then
    os.execute('iptables -t mangle -j RETURN -s ' .. host_ip ..
      ' -C TRANSFEROMETER_FORWARD 2>/dev/null')
    os.execute('iptables -t mangle -j RETURN -s ' .. host_ip ..
      ' -A TRANSFEROMETER_FORWARD')
    os.execute('iptables -t mangle -j RETURN -d ' .. host_ip ..
      ' -C TRANSFEROMETER_FORWARD 2>/dev/null')
    os.execute('iptables -t mangle -j RETURN -d ' .. host_ip ..
      ' -A TRANSFEROMETER_FORWARD')
  end
end

local function demo ()
  print 'Host DB:'
  local host_db = io.read()
  if file_exists(host_db) then
    dofile(host_db)
  else
    print 'File not found!'
    os.exit()
  end


  print 'Label DB:'
  local label_db = io.read()
  if file_exists(label_db) then
    dofile(label_db)
  else
    print 'File not found!'
    os.exit()
  end

  print 'Transfer DB:'
  local transfer_db = io.read()
  if file_exists(transfer_db) then
    dofile(transfer_db)
  else
    print 'File not found!'
    os.exit()
  end

  for k, v in pairs(transfer) do
    print('Date: ' .. k)
    for k, v in pairs(v.bytes_total) do
      print('\tMAC: ' .. k, 'Name: ' .. label[k].name, '\tBytes Total: ' .. v)
    end
  end
end

local function test ()
  create_lock_directory('/tmp/~transferometer')
  create_accounting_chain('INPUT')
  insert_diversion_rule('INPUT')
  insert_diversion_rule('INPUT')
  insert_diversion_rule('INPUT')
  insert_diversion_rule('INPUT')
  insert_diversion_rule('INPUT')
  maintain_diversion_rule('INPUT')
  delete_diversion_rule('INPUT')
  delete_accounting_chain('INPUT')
  delete_lock_directory('/tmp/~transferometer')
end

test()

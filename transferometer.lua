#!/usr/bin/env lua

-- Copyright (C) 2017 Linus Ruth
--
-- This is free software, licensed under the Apache License, Version 2.0.

local label = {}
local transfer = {}

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
      bytes_in    = table.bytes_in,
      bytes_out   = table.bytes_out,
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

-- Add the rule necessary to divert packets from a built-in chain
-- (ex. INPUT) to a corresponding accounting chain (ex. TRANSFEROMETER_INPUT).
-- It must be evaluated first, so it will be placed at the head of the chain.
local function add_diversion_rule_to_chain (built_in_chain)
  os.execute('iptables -t mangle -I ' .. built_in_chain ..
             ' -j TRANSFEROMETER_' .. built_in_chain .. ' 1>/dev/null 2>&1')
end

-- Remove the rule necessary to divert packets from a built-in chain
-- (ex. INPUT) to a corresponding accounting chain (ex. TRANSFEROMETER_INPUT),
-- including any duplicates of the rule which may exist.
local function remove_diversion_rule_from_chain (built_in_chain)
  local command = 'iptables -t mangle -D ' .. built_in_chain ..
                  ' -j TRANSFEROMETER_' .. built_in_chain .. ' 2>&1'
  repeat until string.match(command_result(command), "%S+")
end

-- Verifies that the rule necessary to divert packets from a built-in chain
-- (ex. INPUT) to a corresponding accounting chain (ex. TRANSFEROMETER_INPUT),
-- exists at the head of the chain, and is unique within the chain.
local function verify_diversion_rule_in_chain (built_in_chain)
  local command = 'iptables -t mangle -L ' .. built_in_chain .. ' 1 2>&1'
  local accounting_chain = 'TRANSFEROMETER_' .. built_in_chain
  if string.match(command_result(command), accounting_chain) then
    print 'Under construction!'
  end
end

print 'MAC Label DB:'
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

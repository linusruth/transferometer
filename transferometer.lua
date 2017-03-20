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
  local output = file:read('*a')
  file:close()
  return output
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

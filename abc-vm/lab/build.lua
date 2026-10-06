#!/usr/bin/env luajit
local here=(arg[0]:match('^(.*)/') or '.')
local function read_file(name)local f=assert(io.open(here..'/'..name,'rb'));local s=assert(f:read('*a'));f:close();return s end
local template=read_file('template.html'):gsub('/%*CORE%*/',function()return read_file('core.js')end):gsub('/%*UI%*/',function()return read_file('ui.js')end)
local out=assert(io.open(here..'/abc_vm_lab.html','wb'));assert(out:write(template));assert(out:close());print('wrote '..here..'/abc_vm_lab.html')

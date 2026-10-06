local M = {}
local source = debug.getinfo(1,'S').source:sub(2)
M.directory = source:match('^(.*)/[^/]*$') or '.'
M.runtime = M.directory..'/abc-runtime'
function M.quote(value) return "'"..tostring(value):gsub("'", "'\\''").."'" end
function M.command(args)
    local out={}
    for _,a in ipairs(args) do out[#out+1]=M.quote(a) end
    return table.concat(out,' ')
end
function M.read(path)
    local file,err=io.open(path,'rb'); if not file then error(err,0) end
    local text=file:read('*a'); file:close(); return text
end
function M.write(path,text)
    local file,err=io.open(path,'wb'); if not file then error(err,0) end
    local ok,why=file:write(text); local closed,reason=file:close()
    if not ok or not closed then error(why or reason,0) end
end
function M.capture(args)
    local output,errors=os.tmpname(),os.tmpname()
    local code=os.execute(M.command(args)..' >'..M.quote(output)..' 2>'..M.quote(errors))
    local text,err=M.read(output),M.read(errors)
    os.remove(output); os.remove(errors)
    return code==0,text,err
end
function M.publish(image,path,verify)
    -- Reserve with O_EXCL next to the destination, then verify before rename.
    local ffi=require('ffi')
    ffi.cdef[[int open(const char *, int, ...); int close(int); int getpid(void);]]
    local temporary
    for i=1,1000 do
        local candidate=path..'.abc-tmp-'..tonumber(ffi.C.getpid())..'-'..i
        local fd=ffi.C.open(candidate,193,ffi.new('int',384)) -- Linux O_WRONLY|O_CREAT|O_EXCL, 0600
        if fd>=0 then ffi.C.close(fd); temporary=candidate; break end
    end
    if not temporary then error('cannot reserve output temporary file',0) end
    local ok,err=pcall(function()
        M.write(temporary,image)
        if verify~=false then
            local valid,_,message=M.capture({M.runtime,'check',temporary})
            if not valid then error(message:gsub('%s+$',''),0) end
        end
        local renamed,why=os.rename(temporary,path)
        if not renamed then error(why,0) end
    end)
    os.remove(temporary)
    if not ok then error(err,0) end
end
function M.copy(t) local out={} for k,v in pairs(t) do out[k]=v end return out end
function M.slice(t,start) local out={} for i=start or 1,#t do out[#out+1]=t[i] end return out end
function M.sorted(t) local out={} for key in pairs(t) do out[#out+1]=key end table.sort(out); return out end
return M


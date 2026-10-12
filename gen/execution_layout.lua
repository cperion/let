-- Emit the shared form-addressing contract without generating either backend.
local root=(arg[0]:match('^(.*)/[^/]+$') or '.')
package.path=root..'/?.lua;'..package.path
local forms=require('execution_forms')
local path=assert(arg[1],'output header required')
local out=assert(io.open(path..'.tmp','wb'))
assert(out:write(forms.header()))
assert(out:close())
assert(os.rename(path..'.tmp',path))

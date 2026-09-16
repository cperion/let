-- Views (§12.4). A view is a value that points into storage something else owns: a `Text` over a
-- pointer and a length, or a borrowed `CString`. A view of a Let value holds that value borrowed
-- for as long as the view lives, so moving, freeing or writing the owner while the view is live is
-- a conflicting borrow. A view of a literal or a temporary views storage Let never owned, so there
-- is nothing to hold -- and a view of a non-Copy temporary is rejected, because the temporary dies
-- at the end of the statement.
--
-- Three things this does not claim, and they are the whole boundary:
--
--   * a foreign side that invalidates the bytes is beyond any check;
--   * a host that writes through a `Read` borrow is invisible -- `c.store_byte` declares a read
--     borrow while storing, so it does not conflict with a live view. Declaring `Mut` on the
--     storing helpers would close that, at the cost of every call site writing `mut buffer`;
--   * the hold ends with the scope that made the view, so a view that escapes that scope is no
--     longer held.
package.path='./?.lua;./?/init.lua;'..package.path
local V=require('let')
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function eq(actual,expected,message)
    assert(actual==expected,('%s: expected %s, got %s'):format(message or 'value',tostring(expected),tostring(actual)))
    checks=checks+1
end

local options={dictionary={c={members=V.libc.members}},resources={CAlloc=V.libc.resources.CAlloc}}

-- The rejection *reason* is the point as much as the rejection is, so it is matched by substring.
local function accepts(name,source)
    local ok,err=pcall(function()
        local program=V.parse(source,name..'.let'):build(options)
        V.print(program:emit(options))
    end)
    check(ok,('%s: expected it to build, but it failed with %s'):format(name,tostring(err)))
end
local function rejects(name,source,fragment)
    local ok,err=pcall(function() V.parse(source,name..'.let'):build(options) end)
    check(not ok,('%s: expected it to be rejected, but it built'):format(name))
    if not ok then
        check(tostring(err):find(fragment,1,true)~=nil,
            ('%s: expected %q in %q'):format(name,fragment,tostring(err)))
    end
end

-- A literal views storage Let never owned, so there is nothing to hold.
accepts('literal',[[
let run = do : Int return c.puts(c.string("hi")) end
let started = run()
]])

-- Reads do not conflict with reads, so one owner can back several views.
accepts('two views',[[
let run = do : Int
    let buffer = c.malloc(16);
    let a = c.text_of(buffer, 4);
    let b = c.text_of(buffer, 4);
    return c.byte_length(a) + c.byte_length(b)
end
let started = run()
]])

-- Moving the owner takes the storage out from under the view.
rejects('move the owner',[[
let run = do : Int
    let buffer = c.malloc(16);
    let view = c.text_of(buffer, 4);
    let gone = move buffer;
    return c.byte_length(view)
end
let started = run()
]],'conflicting borrow of buffer')

-- Handing the owner to an owning stage frees it while the view is still live. This is the shape
-- that was accepted before views were held, and it was a genuine use-after-free.
rejects('consume the owner',[[
let consume = let p own : CAlloc do : Int return 0 end
let run = do : Int
    let buffer = c.malloc(16);
    let view = c.text_of(buffer, 4);
    let n = consume(move buffer);
    return c.byte_length(view)
end
let started = run()
]],'conflicting borrow of buffer')

-- Replacing the owner's storage leaves the view pointing into what was there before.
rejects('write the owner',[[
let run = do : Int
    let buffer mut = c.malloc(16);
    let view = c.text_of(buffer, 4);
    buffer = c.malloc(32);
    return c.byte_length(view)
end
let started = run()
]],'conflicting borrow of buffer')

-- A non-Copy temporary dies at the end of the statement, so a view of it could never be used.
rejects('view of a temporary',[[
let run = do : Int
    let view = c.text_of(c.malloc(16), 4);
    return c.byte_length(view)
end
let started = run()
]],'a view of a temporary cannot outlive it')

-- The hold ends with the scope that made the view, so an owner is movable once the view is gone.
accepts('view gone, owner moves',[[
let look = let b : CAlloc do : Int
    let view = c.text_of(b, 4);
    return c.byte_length(view)
end
let eat = let p own : CAlloc do : Int return 0 end
let run = do : Int
    let buffer = c.malloc(16);
    let n = look(buffer);
    let gone = eat(move buffer);
    return n
end
let started = run()
]])

-- A view of a view is held against the original owner, because the second one reads the same bytes.
rejects('view of a view',[[
let run = do : Int
    let buffer = c.malloc(16);
    let inner = c.text_of(buffer, 4);
    let outer = c.string(inner);
    let gone = move buffer;
    return c.byte_length(inner)
end
let started = run()
]],'conflicting borrow of buffer')

print(('passed %d view checks'):format(checks))

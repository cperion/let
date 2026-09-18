package.path='./?.lua;./?/init.lua;' .. package.path
local V=require('let'); local A,B,L=V.AST,V.Belt,V.List
local execute=require('test.execute')
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function eq(actual,expected,message)
    assert(actual==expected,('%s: expected %s, got %s'):format(message or 'value',tostring(expected),tostring(actual))); checks=checks+1
end

local box=B.Named('Box')
local options={
    hosts={open={symbol='open',phase='runtime',purity='ordered',
        signature=B.Signature(L{B.Parameter(B.Int,A.Read)},L{box})}},
    resources={Box={destroy='close'}},
}
local events={}
local host_functions={open=function(n) events[#events+1]='open:'..tonumber(n); return n end,
                      close=function(b) events[#events+1]='close:'..tonumber(b) end}

-- A file table stands in for the filesystem; the resolver is the embedding's business.
local files={}
local function resolver(path) local text=files[path]; if text then return {text=text,file=path} end end
local function run(main)
    local build_options={}
    for key,value in pairs(options) do build_options[key]=value end
    build_options.resolve=resolver
    local program=V.parse(files[main],main):build(build_options)
    program:verify_flow(build_options.hosts)
    local namespace=execute(program.functions[1],{},host_functions,100000,program.functions)
    return namespace.fields[#namespace.fields],program
end
local function rejects(main,pattern,description)
    local build_options={}
    for key,value in pairs(options) do build_options[key]=value end
    build_options.resolve=resolver
    local ok,err=pcall(function() V.parse(files[main],main):build(build_options) end)
    check(not ok and tostring(err):find(pattern),
        ('%s: expected %q, got %s'):format(description or 'rejection',pattern,tostring(err):gsub('\n.*','')))
end

-- §15.1 A file with no written terminal exposes its prelude bindings, in source order.
files['plain.let']='let a = 1\nlet b = a + 1'
files['main.let']='let m = import "plain.let"\nlet r = m.a + m.b'
eq(run('main.let'),3,'the implicit namespace is the named record of the preludes')

-- A written terminal chooses the export surface, so internal bindings stay internal.
files['exports.let']='let internal = 40;\n{ let answer = internal + 2 }'
files['use.let']='let m = import "exports.let"\nlet r = m.answer'
eq(run('use.let'),42,'a written terminal replaces the namespace')

-- §15.2 A file with stages is an ordinary word: the import arguments configure it.
files['codec.let']='let scale : Int\nlet factor = scale * 2;\n{ let encode = factor }'
files['configure.let']='let codec = import "codec.let" 21\nlet r = codec.encode'
eq(run('configure.let'),42,'a configurable file is specialized at the import site')

-- A file that exposes words is projected and invoked like any aggregate (§8.3, §6).
files['math.let']='let add = let x : Int let y : Int do : Int return x + y end\nlet negate = let x : Int do : Int return -x end'
files['usemath.let']='let m = import "math.let"\nlet r = m.add(40, 2) + m.negate(7)'
eq(run('usemath.let'),35,'word members of an imported namespace are invoked normally')

-- The same import twice is two specializations, so §5.2 makes the state independent.
files['res.let']='let size : Int\nlet buffer = open(size);\n{ let handle = move buffer }'
files['two.let']='let first = import "res.let" 1\nlet second = import "res.let" 2'
events={}
run('two.let')
eq(table.concat(events,','),'open:1,open:2','two imports are two independent instances')

-- An owned resource enters the namespace by being moved into it, and the namespace owns it
-- for as long as the binding lives: inside a body that is the body's scope.
files['body.let']='let run = do : Int\n    let res = import "res.let" 7;\n    return 0\nend\nlet r = run()'
events={}
run('body.let')
eq(table.concat(events,','),'open:7,close:7','a namespace owned by a local is destroyed once, at scope exit')

-- A `do` terminal makes the file an executable word, which the importer invokes explicitly.
files['word.let']='let base : Int\ndo : Int\n    return base + 1\nend'
files['useword.let']='let w = import "word.let" 41\nlet r = w()'
eq(run('useword.let'),42,'a do-terminal file yields a word the importer invokes')

-- Imports are a construction cycle when they close on themselves.
files['a.let']='let a = import "b.let"\nlet x = 1'
files['b.let']='let b = import "a.let"\nlet y = 2'
rejects('a.let','import cycle','a self-closing import graph is diagnosed')

-- The path is a constant Text, and the resolver decides what it names.
files['bad1.let']='let x = import 5'
rejects('bad1.let','constant Text','a non-Text import path is rejected')
files['bad2.let']='let x = import "missing.let"'
rejects('bad2.let','cannot resolve import','an unresolvable path is diagnosed')

-- Without a resolver the language has no file access, so an import is a construction error
-- rather than a silent attempt to read something.
local no_resolver=V.parse('let x = import "y.let"','nr.let')
local ok,err=pcall(function() no_resolver:build{} end)
check(not ok and tostring(err):find('no import resolver'),'an import without a resolver is diagnosed')

-- The path slot is a dictionary entry, so an ordinary binding of that name still wins.
files['shadow.let']='let import = 5\nlet r = import + 1'
eq(run('shadow.let'),6,'a lexical binding of `import` shadows the dictionary entry')

print(('passed %d import/file-chain checks'):format(checks))

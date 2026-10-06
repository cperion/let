-- Frontend entry point for the real Let compiler. This layer owns source-profile
-- selection and profile-neutral source ingestion; user computation never runs in Lua.
local D = require("let.diag")
local Parse = require("let.parse")
local Walk = require("let.walk")
local ABC = require("let.abc")
local Semantic = require("let.semantic")

local M = {}

local PROFILES = {
    let = { name = "let", extension = ".let", dynamic = true, managed = true },
    slet = { name = "slet", extension = ".slet", dynamic = false, managed = false },
}
M.profiles = PROFILES

local function profile(name)
    local selected = PROFILES[name]
    if not selected then
        D.reject("source-profile", "Expected source profile `let` or `slet`, not " .. tostring(name))
    end
    return selected
end

function M.profileForPath(path)
    if type(path) ~= "string" then D.reject("compile-input", "A source path must be a string") end
    if path:match("%.slet$") then return PROFILES.slet end
    if path:match("%.let$") then return PROFILES.let end
    D.reject("source-profile", "A Let source path must end in `.let` or `.slet`")
end

local function addBinding(bindings, order, name, node)
    local previous = bindings[name]
    if previous then
        D.reject("duplicate-name", "Module name `" .. name .. "` is declared more than once", node.span)
    end
    bindings[name] = node
    order[#order + 1] = name
end

local function indexDeclarations(ast)
    local bindings, order = {}, {}
    for _, declaration in ipairs(ast.declarations) do
        local kind = declaration.kind
        if kind == "WordDecl" or kind == "ForeignDecl" then
            addBinding(bindings, order, declaration.def.name.text, declaration)
        elseif kind == "ValueDecl" then
            for _, binder in ipairs(declaration.def.binders) do
                addBinding(bindings, order, binder.name.text, declaration)
            end
        elseif kind == "UseDecl" then
            addBinding(bindings, order, declaration.path:match("([^.]+)$"), declaration)
        else
            D.bug("ast-declaration", "Unknown top-level declaration " .. tostring(kind), declaration.span)
        end
    end
    return bindings, order
end

local function verifySLet(ast)
    Walk.walk(ast, {
        enter = function(node)
            if node.kind == "Reference" and node.name.text == "any" then
                D.reject("slet-forbidden", "SLet does not define `any`; use `.let` for dynamic values", node.span)
            end
        end,
    })
end

-- Parse and index one source unit. Later compiler phases attach resolved names,
-- semantic types and typed IR to this object. The profile is mandatory here:
-- only the host interprets a filename; the parser and VM never do.
function M.source(options)
    if type(options) ~= "table" then D.reject("compile-input", "Compiler options must be a table") end
    if type(options.source) ~= "string" then D.reject("compile-input", "Compiler options need a `source` string") end
    local selected = profile(options.profile)
    local name = options.name or "<source>"
    local ast = Parse.source(options.source, name)
    if selected == PROFILES.slet then verifySLet(ast) end
    local bindings, order = indexDeclarations(ast)
    return {
        phase = "parsed",
        profile = selected,
        name = name,
        ast = ast,
        bindings = bindings,
        declarationOrder = order,
    }
end

local function read(path)
    local file, err = io.open(path, "rb")
    if not file then D.reject("compile-input", "Cannot read " .. path .. ": " .. tostring(err)) end
    local source, why = file:read("*a")
    local closed, closeWhy = file:close()
    if not source or not closed then D.reject("compile-input", "Cannot read " .. path .. ": " .. tostring(why or closeWhy)) end
    return source
end

function M.file(path)
    return M.source { source = read(path), name = path, profile = M.profileForPath(path).name }
end

-- Resolve and type a parsed source unit into structurally verified ASDL Ir.Fn nodes.
function M.typed(input)
    local unit = input and input.phase and input or M.source(input)
    return Semantic.build(unit)
end

-- Production source compilation: parsing, semantic construction, checked IR verification and the
-- shared ABC lowering path. No source computation executes in Lua.
function M.compile(options)
    local unit = M.typed(options)
    local lowerOptions = {}
    for key, value in pairs(options or {}) do lowerOptions[key] = value end
    lowerOptions.profile = unit.profile.name
    if lowerOptions.exports == nil then lowerOptions.exports = Semantic.exports(unit) end
    local artifact = ABC.lower(unit.functions, lowerOptions)
    artifact.sourceUnit = unit
    return artifact
end

local function exists(path) local f=io.open(path,"rb");if f then f:close();return true end return false end
local function directory(path) return path:match("^(.*)[/\\][^/\\]+$") or "." end
local function importPath(owner, dotted, importer)
    local base=directory(owner).."/"..dotted:gsub("%.","/")
    if dotted:match("%.slet$") or dotted:match("%.let$") then
        if importer=="slet" and dotted:match("%.let$") then D.reject("slet-import","SLet cannot import a Let module") end
        if not exists(base) then D.reject("import-input","Cannot find imported module "..dotted) end
        return base
    end
    if importer=="slet" then
        local path=base..".slet";if not exists(path) then
            if exists(base..".let") then D.reject("slet-import","SLet cannot import Let module "..dotted) end
            D.reject("import-input","Cannot find imported SLet module "..dotted)
        end;return path
    end
    local dynamic,static=base..".let",base..".slet";local hasDynamic,hasStatic=exists(dynamic),exists(static)
    if hasDynamic and hasStatic then D.reject("import-ambiguous","Both Let and SLet modules match import "..dotted) end
    if not hasDynamic and not hasStatic then D.reject("import-input","Cannot find imported module "..dotted) end
    return hasDynamic and dynamic or static
end

-- Compile a file and its profile-checked import graph. Imported functions receive private,
-- deterministic IDs; only the entry module's declared exports remain public.
function M.compileFile(path, options)
    options=options or {};local cache,active,nextModule={},{},0
    local function load(modulePath, root)
        if active[modulePath] then D.reject("import-cycle","Module import cycle reaches "..modulePath) end
        if cache[modulePath] then return cache[modulePath] end
        active[modulePath]=true
        local selected=M.profileForPath(modulePath);local unit=M.source{source=read(modulePath),name=modulePath,profile=selected.name}
        local imports,dependencies,seen={},{},{}
        for _,decl in ipairs(unit.ast.declarations) do if decl.kind=="UseDecl" then
            local child=load(importPath(modulePath,decl.path,selected.name),false)
            local namespace=decl.path:match("([^.]+)$"):gsub("%.s?let$","")
            for member,entry in pairs(child.exports) do imports[namespace.."."..member]=entry end
            for _,fn in ipairs(child.functions) do if not seen[fn.id] then seen[fn.id]=true;dependencies[#dependencies+1]=fn end end
        end end
        local prefix="";if not root then nextModule=nextModule+1;prefix="__let_module_"..nextModule.."_" end
        Semantic.build(unit,{prefix=prefix,imports=imports,dependencies=dependencies,importsResolved=true})
        local functions={} for _,fn in ipairs(dependencies) do functions[#functions+1]=fn end
        for _,fn in ipairs(unit.functions) do functions[#functions+1]=fn end
        local exported={} for _,item in ipairs(unit.ast.export.functions) do
            if item.kind~="ExportName" then D.todo("semantic-todo","Computed export aliases are not implemented",item.span) end
            local entry=unit.signatures[item.name.text];if not entry then D.reject("unknown-name","Unknown exported word `"..item.name.text.."`",item.name.span) end
            exported[item.name.text]=entry
        end
        local loaded={unit=unit,functions=functions,exports=exported};cache[modulePath]=loaded;active[modulePath]=nil;return loaded
    end
    local loaded=load(path,true);local lowerOptions={} for key,value in pairs(options) do lowerOptions[key]=value end
    lowerOptions.profile=M.profileForPath(path).name
    if lowerOptions.exports==nil then lowerOptions.exports=Semantic.exports(loaded.unit) end
    local artifact=ABC.lower(loaded.functions,lowerOptions);artifact.sourceUnit=loaded.unit;artifact.modules=cache;return artifact
end


-- The semantic frontend supplies verified ASDL Ir.Fn nodes to this shared backend.
function M.lower(functions, options)
    return ABC.lower(functions, options)
end

-- Canonical ABC optimization is implemented once in C. LuaJIT callers use FFI
-- rather than reproducing symbolic execution or bytecode scheduling in Lua.
function M.optimize(moduleBytes)
    return require("let.optimize").optimize(moduleBytes)
end

-- Build a residual entry around VM-produced known values, then run the shared C optimizer.
function M.specialize(functions, options)
    return require("let.specialize").specialize(functions, options)
end

-- Execute a saturated known typed function during compilation. The host must choose
-- the VM policy explicitly. Lowering is shared with residual code; let.stage only
-- assembles, verifies, invokes abc_vm, and decodes raw result cells.
function M.stage(functions, options)
    if type(options) ~= "table" then D.reject("compile-input", "Static execution options must be a table") end
    local entry = options.entry or "main"
    local lowerOptions = {}
    for key, value in pairs(options) do lowerOptions[key] = value end
    lowerOptions.exports = {}
    local found = false
    for _, name in ipairs(options.exports or {}) do
        lowerOptions.exports[#lowerOptions.exports + 1] = name
        if name == entry then found = true end
    end
    if not found then lowerOptions.exports[#lowerOptions.exports + 1] = entry end
    local artifact = M.lower(functions, lowerOptions)
    return require("let.stage").execute(artifact, functions, options)
end

return M

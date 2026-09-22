-- Trusted build configuration. Paths are relative to this file.
-- Replace entry and add a cli/compiler modules once those actually exist.
return {
    entry = "wordletkit",
    output = "dist/wordletkit.lua",
    licenses = {"LICENSE", "vendor/LICENSE"},
    modules = {
        ["wordletkit"] = "wordletkit.lua",
        ["wordletkit.u32"] = "wordletkit/u32.lua",
        ["vendor.asdl"] = "vendor/asdl.lua",
        ["vendor.terralist"] = "vendor/terralist.lua",
    },
    external = {"bit"}, -- built into LuaJIT
}

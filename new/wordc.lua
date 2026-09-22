local source = debug.getinfo(1, "S").source
local script = source:sub(1, 1) == "@" and source:sub(2) or source
local root = script:match("^(.*[/])") or "./"
package.path = root .. "?.lua;" .. root .. "?/init.lua;" .. package.path

local Word = require("word")
local run = require("word.cli")

-- Loading wordc.lua as a module returns the embedding API. Only the file selected
-- as arg[0] owns process exit and command-line output.
if arg and arg[0] == script then os.exit(run(Word, arg)) end
return Word

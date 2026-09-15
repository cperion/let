local Parser = require('let.parser')
require('let.program')
require('let.evaluate')
require('let.codegen')
local M = {}
function M.parse(text, file) return Parser.new(text, file):parse() end
function M.compile(text, file, options)
    local residual, manifest, report = M.parse(text, file):check(options):compile()
    local source, statistics = residual:emit()
    statistics.partial_evaluation = report
    return source, manifest, residual, statistics
end
return M


-- LSP base protocol: Content-Length framed JSON messages over a byte stream.
--
-- The header block ends at an empty line; `Content-Length` counts the bytes of the JSON
-- body. `io` streams are binary-safe for a fixed byte count, so the body needs no decoding
-- beyond JSON. A host supplies the streams, which is what makes the server testable
-- without a subprocess.

local json = require('ide.lsp.json')

local M = {}

-- Read one message, or nil at end of input.
function M.read(stream)
    local length
    while true do
        local line = stream:read('*l')
        if not line then return nil end
        line = line:gsub('\r$', '')
        if line == '' then break end
        local name, value = line:match('^([^:]+):%s*(.-)%s*$')
        if name and name:lower() == 'content-length' then length = tonumber(value) end
    end
    if not length then return nil end
    local body = stream:read(length)
    if not body or #body < length then return nil end
    return json.decode(body)
end

-- Write one message. The body length is measured in bytes, as the protocol requires.
function M.write(stream, message)
    local body = json.encode(message)
    stream:write(('Content-Length: %d\r\n\r\n'):format(#body), body)
    stream:flush()
end

return M

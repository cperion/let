-- Minimal JSON for the Language Server Protocol.
--
-- LSP frames are UTF-8 JSON. This encodes Lua values and decodes JSON text; it is
-- deliberately small: no options, no streaming, no pretty printing. The one LSP-specific
-- concern it handles explicitly is the empty container. An empty Lua table is ambiguous,
-- so it encodes as `[]` because a list is the common case in a response, and
-- `json.object()` marks an empty object. A decoded object carries that mark too, so
-- decoding and re-encoding a message keeps `{}` an object.

local json = {}
local object_mt = {}

json.null = setmetatable({}, {__tostring = function() return 'null' end})

function json.object(value)
    return setmetatable(value or {}, object_mt)
end

local escapes = {
    ['"'] = '\\"', ['\\'] = '\\\\', ['/'] = '\\/', ['\b'] = '\\b', ['\f'] = '\\f',
    ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

-- Decoding is the inverse; its keys are the JSON marker characters, not the characters
-- they stand for, which is why it cannot share the table above.
local unescapes = {['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'}

local function escape(character)
    return escapes[character] or ('\\u%04x'):format(character:byte())
end

local function encode_string(value)
    return '"' .. value:gsub('[%z\1-\31\\"]', escape) .. '"'
end

-- A table is a list when every key is a positive integer and they are dense from 1.
local function is_array(value)
    local count = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 then return false end
        count = count + 1
    end
    return count == #value
end

local encode_value

local function encode_object(value)
    local parts = {}
    for key, item in pairs(value) do
        parts[#parts + 1] = encode_string(tostring(key)) .. ':' .. encode_value(item)
    end
    return '{' .. table.concat(parts, ',') .. '}'
end

local function encode_array(value)
    local parts = {}
    for index = 1, #value do parts[index] = encode_value(value[index]) end
    return '[' .. table.concat(parts, ',') .. ']'
end

encode_value = function(value)
    local kind = type(value)
    if value == nil or value == json.null then return 'null' end
    if kind == 'boolean' then return value and 'true' or 'false' end
    if kind == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then return 'null' end
        if value % 1 == 0 and value >= -9007199254740992 and value <= 9007199254740992 then
            return ('%d'):format(value)
        end
        return ('%.17g'):format(value)
    end
    if kind == 'string' then return encode_string(value) end
    if kind ~= 'table' then error('cannot encode a ' .. kind .. ' as JSON', 0) end
    if getmetatable(value) == object_mt then return encode_object(value) end
    if is_array(value) then return encode_array(value) end
    return encode_object(value)
end

function json.encode(value) return encode_value(value) end

-- Decoding. Positions are 1-based byte indices into the JSON text.

local decode_value

local function skip(text, position)
    local stop = text:find('[^ \t\r\n]', position)
    return stop or (#text + 1)
end

local function utf8_char(code)
    if code < 0x80 then return string.char(code) end
    if code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    end
    if code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 0x1000),
            0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
    end
    return string.char(0xF0 + math.floor(code / 0x40000),
        0x80 + math.floor(code / 0x1000) % 0x40,
        0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local function decode_string(text, position)
    local out, i = {}, position + 1
    while true do
        local stop = text:find('["\\]', i, false)
        if not stop then error('json: unterminated string', 0) end
        if stop > i then out[#out + 1] = text:sub(i, stop - 1) end
        if text:sub(stop, stop) == '"' then return table.concat(out), stop + 1 end
        local marker = text:sub(stop + 1, stop + 1)
        if marker == 'u' then
            local hex = text:sub(stop + 2, stop + 5)
            local code = #hex == 4 and tonumber(hex, 16)
            if not code then error('json: bad \\u escape', 0) end
            i = stop + 6
            if code >= 0xD800 and code <= 0xDBFF and text:sub(i, i + 1) == '\\u' then
                local low = tonumber(text:sub(i + 2, i + 5), 16)
                if low and low >= 0xDC00 and low <= 0xDFFF then
                    code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
                    i = i + 6
                end
            end
            out[#out + 1] = utf8_char(code)
        else
            local mapped = unescapes[marker]
            if not mapped then error('json: bad escape \\' .. marker, 0) end
            out[#out + 1] = mapped
            i = stop + 2
        end
    end
end

local function decode_number(text, position)
    local rest = text:sub(position)
    local number = rest:match('^-?%d+%.?%d*[eE][+-]?%d+')
        or rest:match('^-?%d+%.?%d*')
    if not number then error('json: bad number', 0) end
    return tonumber(number), position + #number
end

decode_value = function(text, position, depth)
    if depth > 200 then error('json: nested too deeply', 0) end
    position = skip(text, position)
    local character = text:sub(position, position)
    if character == '"' then return decode_string(text, position) end
    if character == '{' then
        local object = json.object()
        position = skip(text, position + 1)
        if text:sub(position, position) == '}' then return object, position + 1 end
        while true do
            position = skip(text, position)
            local key
            key, position = decode_string(text, position)
            position = skip(text, position)
            if text:sub(position, position) ~= ':' then error('json: expected :', 0) end
            object[key], position = decode_value(text, position + 1, depth + 1)
            position = skip(text, position)
            local next_ = text:sub(position, position)
            if next_ == ',' then position = position + 1
            elseif next_ == '}' then return object, position + 1
            else error('json: expected , or }', 0) end
        end
    end
    if character == '[' then
        local list, index = {}, 0
        position = skip(text, position + 1)
        if text:sub(position, position) == ']' then return list, position + 1 end
        while true do
            local value
            value, position = decode_value(text, position, depth + 1)
            index = index + 1
            list[index] = value
            position = skip(text, position)
            local next_ = text:sub(position, position)
            if next_ == ',' then position = position + 1
            elseif next_ == ']' then return list, position + 1
            else error('json: expected , or ]', 0) end
        end
    end
    if text:sub(position, position + 3) == 'true' then return true, position + 4 end
    if text:sub(position, position + 4) == 'false' then return false, position + 5 end
    if text:sub(position, position + 3) == 'null' then return json.null, position + 4 end
    if character:match('%d') or character == '-' then return decode_number(text, position) end
    error('json: unexpected character at ' .. position, 0)
end

function json.decode(source)
    local value, position = decode_value(source, 1, 0)
    position = skip(source, position)
    if position <= #source then error('json: trailing text', 0) end
    return value
end

return json

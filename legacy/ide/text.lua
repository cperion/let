-- Byte offsets and LSP positions for Let source.
--
-- The compiler's Source.Span counts 1-based lines and 1-based Unicode scalars within a
-- line, with CRLF treated as one break and a tab as one column (let/lex.lua). LSP counts
-- 0-based lines and UTF-16 code units by default. This module is the one conversion
-- between the two, so neither the scanner nor any consumer has to know both.
--
-- Tokens carry their exact source spelling, so a token's byte extent needs no decoding:
-- `byte_column` finds where the token starts and `#spelling` is its byte length. Only
-- positions reported back to an editor (ranges, diagnostics, extmarks) need mapping.

local M = {}
local Text = {}
Text.__index = Text

-- Scalar width from a lead byte. A continuation or invalid lead byte advances one byte,
-- so a buffer that is momentarily not valid UTF-8 still yields a monotone map.
local function width(byte)
    if byte < 0x80 then return 1 end
    if byte >= 0xC0 and byte < 0xE0 then return 2 end
    if byte >= 0xE0 and byte < 0xF0 then return 3 end
    if byte >= 0xF0 and byte < 0xF8 then return 4 end
    return 1
end

-- Split on LF, CRLF, and a lone CR, exactly as the scanner treats a line break.
function M.new(text)
    local self = setmetatable({text = text or '', lines = {}, maps = {}}, Text)
    local n = #self.text
    local start, i = 1, 1
    while i <= n do
        local byte = self.text:byte(i)
        if byte == 10 then
            self.lines[#self.lines + 1] = {start = start, stop = i}
            i = i + 1; start = i
        elseif byte == 13 then
            self.lines[#self.lines + 1] = {start = start, stop = i}
            i = (self.text:byte(i + 1) == 10) and i + 2 or i + 1
            start = i
        else
            i = i + 1
        end
    end
    self.lines[#self.lines + 1] = {start = start, stop = n + 1}
    return self
end

-- For line `line` (1-based, matching Source.Span), build the two arrays a conversion
-- needs: `bytes[k+1]` is the byte offset after k scalars, and `utf16[k+1]` is the number
-- of UTF-16 code units in those k scalars. Built once per line and cached.
function Text:line_map(line)
    local cached = self.maps[line]
    if cached then return cached end
    local info = self.lines[line]
    if not info then return nil end
    local content = self.text:sub(info.start, info.stop - 1)
    local bytes, utf16 = {0}, {0}
    local offset, scalars, i, n = 0, 0, 1, #content
    while i <= n do
        local length = width(content:byte(i))
        if i + length - 1 > n then length = n - i + 1 end
        offset = offset + length
        scalars = scalars + 1
        bytes[scalars + 1] = offset
        utf16[scalars + 1] = utf16[scalars] + (length == 4 and 2 or 1)
        i = i + length
    end
    local map = {content = content, bytes = bytes, utf16 = utf16, start = info.start}
    self.maps[line] = map
    return map
end

function Text:line_count() return #self.lines end

function Text:line_text(line)
    local info = self.lines[line]
    if not info then return '' end
    return self.text:sub(info.start, info.stop - 1)
end

-- Byte column (0-based) of a span within its line.
function Text:byte_column(span)
    local map = self:line_map(span.line)
    if not map then return 0 end
    local index = math.min(math.max(span.column, 1), #map.bytes)
    return map.bytes[index]
end

-- UTF-16 column (0-based) of a span within its line.
function Text:utf16_column(span)
    local map = self:line_map(span.line)
    if not map then return 0 end
    local index = math.min(math.max(span.column, 1), #map.utf16)
    return map.utf16[index]
end

-- UTF-16 column (0-based) of a byte column within a 1-based line.
function Text:utf16_at_byte(line, byte_column)
    local map = self:line_map(line)
    if not map then return 0 end
    local k = 0
    for index = 2, #map.bytes do
        if map.bytes[index] <= byte_column then k = index - 1 else break end
    end
    return map.utf16[k + 1]
end

-- Byte offset (0-based) of a span within the whole text.
function Text:offset(span)
    local info = self.lines[span.line]
    if not info then return #self.text end
    return (info.start - 1) + self:byte_column(span)
end

-- LSP position (0-based line, UTF-16 character) of a span.
function Text:position(span)
    return {line = span.line - 1, character = self:utf16_column(span)}
end

-- LSP position (0-based line, UTF-16 character) of a byte offset.
function Text:position_at(offset)
    local count = #self.lines
    local line = count
    for index = 1, count do
        if (self.lines[index].start - 1) > offset then line = index - 1; break end
    end
    if line < 1 then line = 1 end
    local within = offset - (self.lines[line].start - 1)
    return {line = line - 1, character = self:utf16_at_byte(line, within)}
end

-- Byte offset (0-based) of an LSP position. `character` is a UTF-16 column.
function Text:offset_at(position)
    local line = position.line + 1
    local map = self:line_map(line)
    if not map then return #self.text end
    local character = position.character
    local last = map.utf16[#map.utf16]
    if character > last then character = last end
    local k = 0
    for index = 2, #map.utf16 do
        if map.utf16[index] <= character then k = index - 1 else break end
    end
    return (self.lines[line].start - 1) + map.bytes[k + 1]
end

-- LSP range between two spans. `stop` is exclusive.
function Text:range(start_span, stop_span)
    return {start = self:position(start_span), ['end'] = self:position(stop_span)}
end

-- LSP range of a token given its start span and byte length.
function Text:token_range(span, byte_length)
    local column = self:byte_column(span)
    return {
        start = self:position(span),
        ['end'] = {line = span.line - 1, character = self:utf16_at_byte(span.line, column + byte_length)},
    }
end

return M

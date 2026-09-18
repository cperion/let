-- Text -> Source.Token list (spec §2.1, §2.2).
--
-- Whitespace is insignificant, so the lexer emits no separator token: a top-level binding ends
-- where the next `let` begins, which the parser decides. `#` starts a comment to end of line.
--
-- Spans carry file, line and column, because a diagnostic is a value with a position (DESIGN §13)
-- and the position must be the one the reader sees.
return function(V)
    local Source, L = V.Source, V.List

    -- `do` and `end` are Lua keywords, so the table keys are bracketed.
    local KEYWORDS = { ['let'] = 'let', ['mut'] = 'mut', ['own'] = 'own', ['move'] = 'move',
                      ['return'] = 'return', ['if'] = 'if', ['else'] = 'else', ['while'] = 'while',
                      ['break'] = 'break', ['continue'] = 'continue',
                      ['do'] = 'do', ['end'] = 'end',
                      -- §3.4's word operators, and `switch`/`case`, which are forms rather than
                      -- expressions but are still reserved.
                      ['and'] = 'and', ['or'] = 'or', ['not'] = 'not',
                      ['switch'] = 'switch', ['case'] = 'case', ['as'] = 'as',
                      -- A foreign word is declared, not registered (§3.6): `extern` introduces it.
                      ['extern'] = 'extern', ['pure'] = 'pure', ['host'] = 'host',
                      ['borrows'] = 'borrows', ['with'] = 'with' }

    -- §3.4's operator tokens. The two-character forms are tried FIRST, and that is not an
    -- optimisation: `<` and `<=` differ only by the next character, so a lexer that preferred the
    -- shorter match would never produce `<=` at all.
    local OPERATORS = {
        ['=='] = '==', ['!='] = '!=', ['<='] = '<=', ['>='] = '>=',
        ['<<'] = '<<', ['>>'] = '>>', ['->'] = '->',
        ['+'] = '+', ['-'] = '-', ['*'] = '*', ['/'] = '/', ['%'] = '%',
        ['<'] = '<', ['>'] = '>', ['&'] = '&', ['|'] = '|', ['^'] = '^', ['~'] = '~',
    }
    local PUNCT = {
        ['='] = '=', [';'] = ';', [':'] = ':', [','] = ',',
        ['('] = '(', [')'] = ')', ['{'] = '{', ['}'] = '}',
        ['.'] = '.', ['['] = '[', [']'] = ']',
    }

    return function(text, file)
        local tokens = L()
        local i, line, col, n = 1, 1, 1, #text

        local function push(kind, spelling, value, span)
            tokens:insert(Source.Token(kind, spelling, value, span))
        end

        while i <= n do
            local c = text:sub(i, i)
            if c == '\n' then
                i, line, col = i + 1, line + 1, 1
            elseif c:match('%s') then
                i, col = i + 1, col + 1
            elseif c == '#' then
                while i <= n and text:sub(i, i) ~= '\n' do i = i + 1 end
            else
                local span = Source.Span(file, line, col)
                local two, one = text:sub(i, i + 1), text:sub(i, i)
                if OPERATORS[two] then
                    push(OPERATORS[two], two, nil, span)
                    i, col = i + 2, col + 2
                elseif OPERATORS[one] then
                    push(OPERATORS[one], one, nil, span)
                    i, col = i + 1, col + 1
                elseif c == '"' then
                    -- §11.3: Text is an immutable MODULE-LIFETIME literal, so a string literal is
                    -- a value with static storage and not a view. The escapes are the ones that
                    -- change the meaning of the bytes; the token's `value` slot carries the
                    -- unescaped text, which is what makes the spelling and the value separable --
                    -- and that separation is what makes two labels collide by VALUE rather than by
                    local scan, value = i + 1, {}
                    while true do
                        local ch = text:sub(scan, scan)
                        if ch == '' then
                            error(('%s:%d:%d: unterminated text'):format(file, line, col), 0)
                        end
                        if ch == '"' then break end
                        if ch == '\\' then
                            local escape = text:sub(scan + 1, scan + 1)
                            local unescaped = ({ n = '\n', t = '\t', r = '\r', ['0'] = '\0' })[escape]
                            if not unescaped and escape ~= '\\' and escape ~= '"' then
                                error(('%s:%d:%d: unknown escape \\%s'):format(file, line, col, escape), 0)
                            end
                            value[#value + 1] = unescaped or escape
                            scan = scan + 2
                        else
                            value[#value + 1] = ch
                            scan = scan + 1
                        end
                    end
                    local spelling = text:sub(i, scan)
                    push('text', spelling, table.concat(value), span)
                    i, col = scan + 1, col + #spelling
                else
                    local name = text:match('^[A-Za-z_][A-Za-z0-9_]*', i)
                    -- §2.2's integer literals. Hex and binary are matched before decimal, because
                    -- `0x10` begins with a digit and a decimal-first match would take the zero.
                    -- §11.3's `Float`. A float is matched BEFORE the decimal integer, or `1.5` would be
                    -- the integer `1` and then a projection. A leading digit is required: `.` is the
                    -- postfix projection, so `.5` is not a literal in this language -- which is a
                    -- choice, and the one that keeps `a.b` unambiguous.
                    local float = text:match('^%d[%d_]*%.[%d_]*[eE][+-]?%d+', i)
                        or text:match('^%d[%d_]*%.[%d_]*', i)
                        or text:match('^%d[%d_]*[eE][+-]?%d+', i)
                    local int = text:match('^0[xX][%x_]+', i) or text:match('^0[bB][01_]+', i)
                        or text:match('^%d[%d_]*', i)
                    if name then
                        push(KEYWORDS[name] or 'name', name, name, span)
                        i, col = i + #name, col + #name
                    elseif float then
                        push('float', float, float:gsub('_', ''), span)
                        i, col = i + #float, col + #float
                    elseif int then
                        push('int', int, int:gsub('_', ''), span)
                        i, col = i + #int, col + #int
                    elseif PUNCT[c] then
                        push(PUNCT[c], c, nil, span)
                        i, col = i + 1, col + 1
                    else
                        error(('%s:%d:%d: unexpected character %q'):format(file, line, col, c), 0)
                    end
                end
            end
        end
        push('eof', '', nil, Source.Span(file, line, col))
        return tokens
    end
end

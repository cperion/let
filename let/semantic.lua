-- The semantic vocabulary: the choices every other layer names.
--
-- This layer sits below Syntax and below Belt and references nothing above it. It owns the
-- shared choices (capability, purity, phase because Chain names them), the operators, and the
-- type word. `Type.Word` names a template by *number* rather than by `Chain.Template`, so that
-- Semantic never references Chain; that asymmetry is what keeps the layers acyclic.
--
-- `Copy` is deliberately absent: it is derived from the type (a method, not a constructor), and
-- `Access` is absent because a call-site use of a place is *syntax* (Syntax.Expr.Move/Borrow).
return function(context)
    context:Define [[
module Semantic {
    Capability = Read | Mut | Own | OwnMut
    Purity     = Pure | Ordered
    Phase      = Runtime | Construction

    UnaryOp    = Negate | Not | BitNot
    BinaryOp   = Add | Subtract | Multiply | Divide | Remainder
               | Equal | NotEqual | Less | LessEqual | Greater | GreaterEqual
               | BitAnd | BitOr | BitXor | ShiftLeft | ShiftRight
               | And | Or
    Conversion = ToFloat | ToInt | ToU8 | ToU32 | ToF32 | ToCString | ToText | TextSize | IsNull

    Field      = (string? name, Type type, boolean mutable)
    Type       = Int | U8 | U32 | Float | Float32 | Bool | Unit | Text | Effect
               | CString | CPointer
               | Named(string name)
               | Aggregate(Field* fields, string? name)
               | Sum(Type* alternatives)
               | Arrow(Type from, Type to)
               | Do(Type result)
               | TypeWord
               | Word(number template, number prefix)
}
    ]]

    local S = context.Semantic

    -- §11.2: "Conversions are their own choice ... because `ToFloat` and friends are DICTIONARY
    -- words, not operators." So each is a one-stage word, and this table IS its declaration: the
    -- type it reads and the type it produces. It lives in `Semantic` because it is the shared
    -- meaning of a name, and both `Resolve` (which builds the word) and `Contract` (which types it)
    -- must agree about it.
    --
    -- `ToText` is deliberately absent. A `Text` has a known length and no terminator guarantee,
    -- while a `CString` is terminated and borrowed, so going the other way needs a length that the
    -- source does not have -- which is a representation question and not a table entry.
    S.conversions = {
        ToInt = { from = S.Float, to = S.Int },
        ToFloat = { from = S.Int, to = S.Float },
        ToU8 = { from = S.Int, to = S.U8 },
        ToU32 = { from = S.Int, to = S.U32 },
        ToF32 = { from = S.Float, to = S.Float32 },
        ToCString = { from = S.Text, to = S.CString },
        TextSize = { from = S.Text, to = S.Int },
        IsNull = { from = S.CPointer, to = S.Bool },
    }

    -- What an integer literal DENOTES, which is not what it is spelled as: `0x10`, `0b10000` and
    -- `16` are one value, and label identity depends on that -- two labels collide by VALUE,
    -- numerically equal spellings such as 1 and 0x1". It lives here because the belt carries only
    -- the SPELLING (`Belt.IntegerLiteral(string spelling)`), so the conversion is needed below
    -- Syntax as well as inside it, and two copies of a base conversion is two chances to disagree
    -- about underscores.
    -- §S38: one owner of a literal's value, and this is the float half of it. Underscores are the
    -- spelling's business (`1_0.5` is one number), so they go before the conversion.
    function S.float_value(spelling) return tonumber((spelling:gsub('_', ''))) end

    function S.integer_value(spelling)
        local digits = spelling:gsub('_', '')
        if digits:match('^0[xX]') then return tonumber(digits:sub(3), 16) end
        if digits:match('^0[bB]') then return tonumber(digits:sub(3), 2) end
        return tonumber(digits)
    end


    -- **Copy is derived, never stored** (DESIGN §2.5). A type answers whether it is Copy, and the
    -- rules are §11.3 (primitive), §2.5 (a record, and its `mut` members), §11.5 (a sum) and
    -- §12.4 (the two foreign views, which are Copy). A record with a `mut` member is *not* Copy
    -- even when every member is, because interior mutability is observable state -- which is what
    -- makes `{ let x mut = 1 }` the first non-Copy value this compiler can build.
    --
    -- `word` is deliberately `false`: whether a word is Copy depends on the packet its template
    -- produces, which is a fact about a template and not about the type word. That needs the
    -- interface as a lookup, and it arrives with the first word-valued member.
    local COPYABLE = {}
    for _, name in ipairs{'Int', 'U8', 'U32', 'Float', 'Float32', 'Bool', 'Unit', 'Text',
                         'CString', 'CPointer'} do
        COPYABLE[S[name]] = true
    end

    -- §12.2 says Contract "checks rather than infers", and a check needs EQUALITY. Scalars are
    -- unique classes so identity is right for them; everything structural compares by structure; a
    -- `Named` type is interned so identity is right for it too. This is the same shape as `copyable`
    -- -- a derived property as a method -- and it exists for the same reason: a type is a WORD, so
    -- two occurrences of one type word are one type, and `==` on two tables says they are not.
    function S.Type:equals(other) return self == other end

    function S.Aggregate:equals(other)
        if not S.Aggregate:isclassof(other) or #self.fields ~= #other.fields then return false end
        for index, field in ipairs(self.fields) do
            local peer = other.fields[index]
            if field.mutable ~= peer.mutable or field.name ~= peer.name then return false end
            if not field.type:equals(peer.type) then return false end
        end
        return true
    end

    -- §3.5's construction rule, as a derived method: which alternative does this type select?
    -- Returns the index AND how many alternatives matched, because "none" and "more than one" are
    -- different errors -- one says the value is not a member, the other says the sum cannot say
    -- which member it is -- and a caller that only got nil could not tell them apart.
    --
    -- It is derived rather than chosen: the alternative is the one whose type the value ALREADY has,
    -- so there is nothing to coerce. Two alternatives of one type make a sum no value can inhabit
    -- implicitly, which is honest rather than a limitation to work around.
    -- Nominal means identified by name -- that is the whole content of §S3's nominality, and it is
    -- why interning was never the real rule: two `Named('Handle')` values ARE one type because they
    -- name one type, not because a table happened to hand back the same object.
    function S.Named:equals(other)
        return S.Named:isclassof(other) and self.name == other.name
    end

    function S.Sum:alternative(type_)
        local found, count = nil, 0
        for index, alternative in ipairs(self.alternatives) do
            if alternative:equals(type_) then
                found, count = index - 1, count + 1
            end
        end
        return found, count
    end

    function S.Sum:equals(other)
        if not S.Sum:isclassof(other) or #self.alternatives ~= #other.alternatives then return false end
        for index, alternative in ipairs(self.alternatives) do
            if not alternative:equals(other.alternatives[index]) then return false end
        end
        return true
    end

    function S.Arrow:equals(other)
        return S.Arrow:isclassof(other) and self.from:equals(other.from) and self.to:equals(other.to)
    end

    function S.Do:equals(other)
        return S.Do:isclassof(other) and self.result:equals(other.result)
    end

    -- §S3's nominality is a NUMBER and a PREFIX, so two mentions of one word are ONE type -- and
    -- `Word` is the member of this closed set that never got an `equals`. `S.Type:equals` is
    -- identity, which is right for a scalar (one instance) and for an interned `Named`, so
    -- `let f : square = square` compared two equal-valued `Word(1, 0)`s, called them different
    -- types, and refused a program in which the annotation and the value disagreed about nothing.
    -- A rule that has to hold for every member of a set is a rule about the SET: the tell for a
    -- missing member is a comparison that succeeds on values and fails on types.
    function S.Word:equals(other)
        return S.Word:isclassof(other) and self.template == other.template
            and self.prefix == other.prefix
    end

    -- §11.3's scalar type words, BY NAME. This is a semantic fact -- the name of a type word -- and it
    -- lives here because two layers need the same answer: `Resolve` to make a type name an expression
    -- (§2.4) and `Contract` to know that `s.Int` names the `Int` alternative (§S54). Two copies of a
    -- name table is two chances to disagree about which names are type words.
    S.primitive = {
        Int = S.Int, U8 = S.U8, U32 = S.U32, Float = S.Float, Float32 = S.Float32,
        Bool = S.Bool, Unit = S.Unit, Text = S.Text,
        CString = S.CString, CPointer = S.CPointer,
    }

    function S.Type:copyable() return COPYABLE[self] or false end

    -- §3.7: a `mut` member is INTERIOR MUTABILITY -- the value is writable through a binding whatever
    -- the binding's own mutability says -- so writability is a property of the TYPE rather than of the
    -- name that holds it. Derived beside `copyable` for the same reason: nothing declares it twice. It
    -- is recursive, because `r.inner.x` reaches a `mut` member through a record that is not itself
    -- mutable: what has to be addressable is the storage the path STARTS in, so one `mut` step
    -- anywhere below it is enough.
    function S.Type:interior_mutability() return false end

    function S.Aggregate:interior_mutability()
        for _, field in ipairs(self.fields) do
            if field.mutable or field.type:interior_mutability() then return true end
        end
        return false
    end

    function S.Sum:interior_mutability()
        for _, alternative in ipairs(self.alternatives) do
            if alternative:interior_mutability() then return true end
        end
        return false
    end

    function S.Aggregate:copyable()
        for _, field in ipairs(self.fields) do
            if field.mutable or not field.type:copyable() then return false end
        end
        return true
    end

    function S.Sum:copyable()
        for _, alternative in ipairs(self.alternatives) do
            if not alternative:copyable() then return false end
        end
        return true
    end
end

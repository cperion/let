-- The chain vocabulary: the one construct.
--
-- A template interleaves prelude *groups* and *stages*. `Group(at, preludes)` marks the preludes
-- that run before stage `at` and names their definitions: a group is not just "here", it says
-- *which* preludes, because the preludes are declarations with their own ids and the group is what
-- orders them.
--
-- `Residual(template, prefix)` names the record after `prefix` stable stages. `prefix <=
-- transient_from`, because a `mut` stage cannot be stored and a chain is transient from its first
-- one (spec §5.3, DESIGN §2.2).
--
-- `Terminal` is Data, Do, or a Form. The first two make the chain a value word or a type word; the
-- third makes it a construction word, whose operations the compiler executes.
return function(context)
    context:Define [[
module Chain {
    Terminal = Data | Do | Form(Dict.Form form) | Host(string symbol)
             | Convert(Semantic.Conversion kind)
    Capture  = (number binder, string name, Semantic.Capability mode)

    Item     = Group(number at, number* preludes)
             | Stage(number index, Semantic.Capability capability,
                     Semantic.Type type, number binder)

    Template = (string name, Item* items, number stages, number transient_from,
                Terminal terminal, Semantic.Type? result, Capture* captures,
                Semantic.Phase phase, Semantic.Purity purity)
    Residual = (Template template, number prefix)
}
    ]]

    local Chain = context.Chain

    -- §2.2: `R(t,k) = captures + stage values 0…k-1 + prelude bindings of groups 0…k`. The layout is a
    -- fact about the TEMPLATE, so it is asked OF the template, and it lives here rather than in a phase
    -- because two phases need it for two different questions -- `Lower` for what a name's slot holds,
    -- `Contract` for what a value's type is -- and the members are this vocabulary's fields.
    function Chain.Template:members(k)
        local members = {}
        for _, capture in ipairs(self.captures or {}) do
            members[#members + 1] = capture.binder
        end
        for _, item in ipairs(self.items) do
            if Chain.Group:isclassof(item) then
                if item.at <= k then
                    for _, id in ipairs(item.preludes) do members[#members + 1] = id end
                end
            elseif item.index < k then
                members[#members + 1] = item.binder
            end
        end
        return members
    end
end

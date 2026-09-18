-- The dictionary vocabulary: a construction word's source form.
--
-- A dictionary entry *is* a chain (Chain.Template), carrying a phase and a purity. This module
-- exists only for the entries whose terminal is a form: the construction words with bespoke
-- syntax, `if`, `while` and `switch` (spec §12.3). Their behaviour lives in Lower.
return function(context)
    context:Define [[
module Dict {
    Form = (string name, Slot* slots)
    Slot = Expression | Region
}
    ]]
end

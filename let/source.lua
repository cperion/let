-- The source vocabulary: positions and tokens. It references nothing.
return function(context)
    context:Define [[
module Source {
    Span  = (string file, number line, number column)
    Range = (Span start, Span stop)
    Token = (string kind, string spelling, string? value, Span span)
}
    ]]
end

local affine = word(U32, U32, U32, function(scale, offset, x)
    return scale * x + offset
end)

return {
    affine = affine,
    transform = affine:of(3, 7),
}

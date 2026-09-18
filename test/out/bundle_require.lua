local V = dofile("test/out/let-bundle.lua")
print(V.Semantic ~= nil and V.Belt ~= nil and V.Report ~= nil)

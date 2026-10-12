-- PINK DOT LOCK: verified public payload pinned to a specific commit.
local rawURL = "https://raw.githubusercontent.com/sedonkkk/sedon-/837ef39140063c4576a7aa9166cda4cf2e4ceec3/PinkDotLock.lua"
assert(type(loadstring)=="function", "This authorized host must provide loadstring")
local ok, source = pcall(function() return game:HttpGet(rawURL) end)
assert(ok and type(source)=="string", "Unable to retrieve the public PinkDotLock payload")
local chunk, problem = loadstring(source, "PinkDotLock")
assert(chunk, problem)
return chunk()

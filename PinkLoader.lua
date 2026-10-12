-- SEDWARE: verified public payload pinned to a specific commit.
local rawURL = "https://raw.githubusercontent.com/sedonkkk/sedon-/02e0e72f1ec0a66e23ae490e5c15819fe2f20cf7/PinkDotLock.lua"
print("[SEDWARE][Loader][START] Retrieving the verified payload")
assert(type(loadstring)=="function", "[SEDWARE][Loader][FAIL] Host must provide a Luau-compatible loadstring")
local ok, source = pcall(function() return game:HttpGet(rawURL) end)
assert(ok, "[SEDWARE][Loader][HTTP FAIL] "..tostring(source))
assert(type(source)=="string", "[SEDWARE][Loader][HTTP FAIL] Expected script text")
local chunk, problem = loadstring(source, "PinkDotLock")
assert(chunk, "[SEDWARE][Loader][COMPILE FAIL] "..tostring(problem))
local ran, result = xpcall(chunk,function(err) return debug and debug.traceback and debug.traceback(tostring(err),2) or tostring(err) end)
assert(ran, "[SEDWARE][Loader][EXECUTION FAIL] "..tostring(result))
return result

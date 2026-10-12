-- SEDWARE CAM LOCK: verified public payload pinned to a specific commit.
local rawURL = "https://raw.githubusercontent.com/sedonkkk/sedon-/ed6faa918328294d1ca8d865343f865a1b6fad78/SedwareCamLock.lua"
print("[SEDWARE][CamLoader][START] Retrieving the verified payload")
assert(type(loadstring)=="function", "[SEDWARE][CamLoader][FAIL] Host must provide a Luau-compatible loadstring")
local ok, source = pcall(function() return game:HttpGet(rawURL) end)
assert(ok, "[SEDWARE][CamLoader][HTTP FAIL] "..tostring(source))
assert(type(source)=="string", "[SEDWARE][CamLoader][HTTP FAIL] Expected script text")
local chunk, problem = loadstring(source, "SedwareCamLock")
assert(chunk, "[SEDWARE][CamLoader][COMPILE FAIL] "..tostring(problem))
local ran, result = xpcall(chunk,function(err) return debug and debug.traceback and debug.traceback(tostring(err),2) or tostring(err) end)
assert(ran, "[SEDWARE][CamLoader][EXECUTION FAIL] "..tostring(result))
return result

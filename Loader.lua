-- Paste the actual GitHub Raw URL; this template deliberately has no URL.
local URL_RAW_DEL_SCRIPT = "https://raw.githubusercontent.com/sedonkkk/sedon-/47a278a38ae3b7ce48fa2184bcf7ff0bd12bcedf/DaHoodPrediction.lua"
assert(URL_RAW_DEL_SCRIPT ~= "", "Set the real GitHub Raw URL before running this loader")
assert(type(loadstring) == "function", "This runtime does not provide loadstring; run the complete LocalScript instead")
local ok, source = pcall(function() return game:HttpGet(URL_RAW_DEL_SCRIPT) end)
assert(ok and type(source) == "string", "HTTP download failed or this runtime does not provide game:HttpGet")
local chunk, compileError = loadstring(source, "DH PREDICTION LAB")
assert(chunk, compileError)
return chunk()

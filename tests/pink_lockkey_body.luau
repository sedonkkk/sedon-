--!nonstrict
-- Run the actual standalone bundle against explicit native API doubles.
-- Enum membership, diagnostics and C events are simulated; this is not a
-- Roblox engine or Da Hood integration test.
return function(reloadBundle)
	local Mock = require("./PinkMock")
	local tests, checks, failures = 0, 0, 0
	local function check(condition, message)
		checks += 1
		assert(condition, message or ("assertion failed at line " .. tostring(debug.info(2, "l"))))
	end
	local function contains(text, fragment)
		return type(text) == "string" and string.find(text, fragment, 1, true) ~= nil
	end
	local function cleanup(mock)
		for _, node in ipairs(mock.playerGui:GetChildren()) do
			if node.Name == "PinkDotLock_Owner_v1" and node:IsA("BindableEvent") then node:Fire() end
		end
		for _, node in ipairs(mock.playerGui:GetChildren()) do node:Destroy() end
	end
	local function test(name, body)
		tests += 1
		local mock = Mock.new()
		local ok, problem = pcall(body, mock)
		cleanup(mock)
		if not ok then
			failures += 1
			print("FAIL SEDWARE LOCKKEY " .. name .. ": " .. tostring(problem))
		elseif mock:countConnections() ~= 0 then
			failures += 1
			print("FAIL SEDWARE LOCKKEY " .. name .. ": cleanup left connected listeners")
		end
	end
	local function config(mock, key)
		local api = reloadBundle(mock.env)
		return api.Modules.Config.new({LockKey = key})
	end
	local function rejected(mock, key)
		local value, problem = config(mock, key)
		check(value == nil, "invalid key was accepted")
		check(contains(problem, "LockKey"), "rejection omitted the configuration field: " .. tostring(problem))
	end
	local function canonical(mock, key)
		local value, problem = config(mock, key)
		check(value ~= nil, "valid key was rejected: " .. tostring(problem))
		check(rawequal(value.LockKey, mock.env.Enum.KeyCode.C), "key lost native canonical identity")
		check(value.PredictionX == 0.1205 and value.PredictionY == 0.0800)
		return value
	end
	local function press(mock, key)
		mock.services.UserInputService.InputBegan:Fire(mock:input("Keyboard", 0, 0, key), false)
	end

	test("mock exposes finite canonical native KeyCode members", function(mock)
		check(tostring(mock.env.Enum.KeyCode) == "KeyCode", "the old nonnative tostring result hides the real regression")
		local group = mock.env.Enum.KeyCode
		local items = group:GetEnumItems()
		local count = 0
		for _, item in ipairs(items) do
			if rawequal(item, group.C) then count += 1 end
			check(rawequal(item.EnumType, group))
		end
		check(count == 1)
		check(not pcall(function() return group.SedwareDoesNotExist end), "mock invented an invalid native key")
	end)
	test("text C normalizes to native Enum.KeyCode.C", function(mock)
		canonical(mock, "C")
	end)
	test("native Enum.KeyCode.C preserves identity", function(mock)
		canonical(mock, mock.env.Enum.KeyCode.C)
	end)
	test("default Config.new also validates and normalizes C", function(mock)
		local api = reloadBundle(mock.env)
		local value, problem = api.Modules.Config.new()
		check(value ~= nil, tostring(problem))
		check(rawequal(value.LockKey, mock.env.Enum.KeyCode.C))
	end)
	test("editable standalone header uses text C and autostarts normally", function(mock)
		mock.env.PINK_DOT_NO_AUTOSTART = false
		local api = reloadBundle(mock.env)
		check(api.session ~= nil, mock:logText())
		check(rawequal(api.session.config.LockKey, mock.env.Enum.KeyCode.C))
		check(api.session.overlay.title.Text == "SEDWARE")
		check(api.session.overlay.body.Text == "Successfully Loaded | Press C to Lock")
		check(mock:hasLog("[Session][ACTIVE]"))
	end)
	test("a valid different native key normalizes without changing its identity", function(mock)
		local value, problem = config(mock, "V")
		check(value ~= nil, tostring(problem))
		check(rawequal(value.LockKey, mock.env.Enum.KeyCode.V))
	end)
	test("another native enum is rejected", function(mock)
		rejected(mock, mock.env.Enum.HumanoidStateType.Running)
	end)
	test("KeyCode.Unknown is rejected", function(mock)
		rejected(mock, mock.env.Enum.KeyCode.Unknown)
		rejected(mock, "Unknown")
		rejected(mock, mock.env.Enum.KeyCode.None)
		rejected(mock, "None")
	end)
	test("nonexistent and malformed text keys are rejected", function(mock)
		for _, key in ipairs({"SedwareDoesNotExist", "", "c", " C ", "Enum.KeyCode.C", "C\n", "C!"}) do
			rejected(mock, key)
		end
	end)
	test("numbers booleans and functions are rejected", function(mock)
		for _, key in ipairs({123, 0, false, true, function() return "C" end}) do rejected(mock, key) end
	end)
	test("enum-shaped table with textual EnumType is rejected", function(mock)
		rejected(mock, {Name = "C", EnumType = "KeyCode"})
	end)
	test("enum-shaped table with actual EnumType is rejected", function(mock)
		rejected(mock, {Name = "C", EnumType = mock.env.Enum.KeyCode, _mockType = "EnumItem"})
	end)
	test("cloned native item is rejected by canonical membership", function(mock)
		rejected(mock, table.clone(mock.env.Enum.KeyCode.C))
	end)
	test("overloaded equality cannot impersonate native enum identity", function(mock)
		local native = mock.env.Enum.KeyCode.C
		local nativeMeta = getmetatable(native)
		local oldEquality = nativeMeta.__eq
		local counterfeit = setmetatable({Name = "C", EnumType = mock.env.Enum.KeyCode, _mockType = "EnumItem"}, nativeMeta)
		nativeMeta.__eq = function() return true end
		local ok, problem = pcall(function() rejected(mock, counterfeit) end)
		nativeMeta.__eq = oldEquality
		check(ok, tostring(problem))
	end)
	test("throwing enum-shaped object fails safely", function(mock)
		local counterfeit = setmetatable({}, {__index = function() error("counterfeit property error") end})
		local ok, value, problem = pcall(config, mock, counterfeit)
		check(ok, "malicious object escaped the validation boundary")
		check(value == nil and contains(problem, "LockKey"))
	end)
	for _, enumType in ipairs({"userdata", "table", "EnumItem"}) do
		test("normalization is independent of typeof enum = " .. enumType, function(mock)
			local base = mock.env.typeof
			mock.env.typeof = function(value)
				if type(value) == "table" and rawget(value, "_mockType") == "EnumItem" then return enumType end
				return base(value)
			end
			canonical(mock, "C")
			canonical(mock, mock.env.Enum.KeyCode.C)
			rejected(mock, {Name = "C", EnumType = mock.env.Enum.KeyCode, _mockType = "EnumItem"})
		end)
	end
	test("throwing typeof on enum does not reject a canonical key", function(mock)
		local base = mock.env.typeof
		mock.env.typeof = function(value)
			if type(value) == "table" and rawget(value, "_mockType") == "EnumItem" then error("host typeof EnumItem exception") end
			return base(value)
		end
		canonical(mock, "C")
		canonical(mock, mock.env.Enum.KeyCode.C)
	end)
	test("absent typeof can normalize configuration independently of runtime compatibility", function(mock)
		mock.env.typeof = nil
		local inherited = getfenv()
		setmetatable(mock.env, {__index = function(_, name)
			if name == "typeof" then return nil end
			return inherited[name]
		end})
		local api = reloadBundle(mock.env)
		for _, key in ipairs({"C", mock.env.Enum.KeyCode.C}) do
			local value, problem = api.Modules.Config.normalizeLockKey(key)
			check(rawequal(value, mock.env.Enum.KeyCode.C), tostring(problem))
		end
	end)
	test("altered tostring(EnumType) does not affect key validation", function(mock)
		getmetatable(mock.env.Enum.KeyCode).__tostring = function() return "Host-specific enum rendering" end
		canonical(mock, "C")
		canonical(mock, mock.env.Enum.KeyCode.C)
	end)
	test("throwing tostring(EnumType) does not affect key validation", function(mock)
		getmetatable(mock.env.Enum.KeyCode).__tostring = function() error("host enum tostring exception") end
		canonical(mock, "C")
		canonical(mock, mock.env.Enum.KeyCode.C)
	end)
	test("altered global tostring does not affect canonical membership", function(mock)
		local nativeToString = tostring
		mock.env.tostring = function(value)
			if rawequal(value, mock.env.Enum.KeyCode) then return "Changed formatting" end
			return nativeToString(value)
		end
		canonical(mock, "C")
		canonical(mock, mock.env.Enum.KeyCode.C)
	end)
	test("Enum unavailable permits validated CLI name without pretending to initialize", function(mock)
		mock.env.Enum = nil
		local inherited = getfenv()
		setmetatable(mock.env, {__index = function(_, name)
			if name == "Enum" then return nil end
			return inherited[name]
		end})
		local value, problem = config(mock, "C")
		check(value ~= nil and value.LockKey == "C", tostring(problem))
		rejected(mock, "SedwareDoesNotExist")
		rejected(mock, {Name = "C", EnumType = "KeyCode"})
	end)
	test("unreadable native Enum membership fails with a concrete validation error", function(mock)
		mock.env.Enum.KeyCode.GetEnumItems = function() error("controlled enum membership API failure") end
		local value, problem = config(mock, "C")
		check(value == nil, "membership API failure silently used unverified enum values")
		check(contains(problem, "LockKey"))
	end)
	for _, form in ipairs({"text", "native"}) do
		test("InputBegan C locks and unlocks after " .. form .. " key configuration", function(mock)
			local api = reloadBundle(mock.env)
			mock:setPointer(640, 396)
			local target = mock:addPlayer("LockKeyTarget", mock.env.Vector3.new(0, 0, -50))
			local key = if form == "text" then "C" else mock.env.Enum.KeyCode.C
			local session, report = api.tryInit({LockKey = key, LockMode = "FirstPerson", DebugMode = true})
			check(session ~= nil and report.ready, mock:logText())
			check(mock:countSignalConnections(mock.services.UserInputService.InputBegan) == 1)
			press(mock, "V")
			check(session:GetLockedTarget() == nil, "a different key triggered selection")
			press(mock, "C")
			check(session:GetLockedTarget() == target, "the normalized C key did not lock")
			check(mock:hasLog("[Input][KEY]"), "C diagnostic did not run")
			press(mock, "C")
			check(session:GetLockedTarget() == nil, "C did not unlock")
			session:destroy()
			check(mock:countConnections() == 0)
			mock:resetCounters(); press(mock, "C")
			check(mock.counters.candidateScans == 0, "a destroyed C connection survived")
		end)
	end
	test("fully configured session preserves native C when typeof reports table", function(mock)
		local base = mock.env.typeof
		mock.env.typeof = function(value)
			if type(value) == "table" and rawget(value, "_mockType") == "EnumItem" then return "table" end
			return base(value)
		end
		local api = reloadBundle(mock.env)
		local full, problem = api.Modules.Config.new(api.Modules.Config.defaults())
		check(full ~= nil, tostring(problem))
		check(rawequal(full.LockKey, mock.env.Enum.KeyCode.C))
		full.LockMode = "FirstPerson"
		local target = mock:addPlayer("RoundTripC", mock.env.Vector3.new(0, 0, -50))
		-- Bootstrap and Session each validate the complete config, so this catches
		-- accidental table-copying of the canonical key during either merge.
		local session, report = api.tryInit(full)
		check(session ~= nil and report.ready, mock:logText())
		check(rawequal(session.config.LockKey, mock.env.Enum.KeyCode.C))
		check(session.overlay.body.Text == "Successfully Loaded | Press C to Lock", "welcome derived the wrong key from typeof")
		press(mock, "C"); check(session:GetLockedTarget() == target)
		press(mock, "C"); check(session:GetLockedTarget() == nil)
		session:destroy(); check(mock:countConnections() == 0)
	end)
	test("wrong native enum reports configuration failure in console and notification", function(mock)
		local api = reloadBundle(mock.env)
		local session, report = api.tryInit({LockKey = mock.env.Enum.HumanoidStateType.Running})
		check(session == nil and report.ready == false)
		check(mock:hasLog("[Configuration][FAIL]") and mock:hasLog("LockKey"))
		check(not mock:hasLog("[Session][ACTIVE]"))
		local toast = mock.playerGui:FindFirstChild("PinkDotLock_LoadFailure")
		check(toast ~= nil)
		check(toast:FindFirstChild("Title", true).Text == "SEDWARE | Load Failed")
		check(contains(toast:FindFirstChild("Body", true).Text, "LockKey"))
		check(mock:countConnections() == 0)
	end)
	test("normalization does not mask failure in a later critical startup phase", function(mock)
		local api = reloadBundle(mock.env)
		mock.services.UserInputService.InputBegan.Connect = function() error("controlled C connection failure") end
		local session, report = api.tryInit({LockKey = "C"})
		check(session == nil and report.ready == false)
		check(mock:hasLog("controlled C connection failure"))
		check(not mock:hasLog("[Session][ACTIVE]"))
		local toast = mock.playerGui:FindFirstChild("PinkDotLock_LoadFailure")
		check(toast ~= nil and contains(toast:FindFirstChild("Body", true).Text, "controlled C connection failure"))
		check(mock:countConnections() == 0)
	end)

	print(string.format("SEDWARE LockKey doubles: %d tests, %d assertions, %d failures", tests, checks, failures))
	assert(failures == 0, "SEDWARE LockKey tests failed")
	return {tests = tests, checks = checks}
end

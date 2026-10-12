--!nonstrict
-- Actual standalone bundle, deterministic native-client API doubles. These
-- tests verify startup and diagnostics, not Roblox rendering or Da Hood.
return function(reloadBundle)
	local Mock = require("./PinkMock")
	local tests, assertions, failures = 0, 0, 0
	local function check(condition, message)
		assertions += 1
		assert(condition, message or ("assertion failed at line " .. tostring(debug.info(2, "l"))))
	end
	local function contains(text, fragment)
		return type(text) == "string" and string.find(text, fragment, 1, true) ~= nil
	end
	local function errorText(api, report)
		return api.Modules.Runtime.errorMessage(report)
	end
	local function phaseIndex(report, phase, status)
		for index, event in ipairs(report.events or {}) do
			if string.lower(tostring(event.phase)) == string.lower(phase)
				and (not status or string.upper(tostring(event.status)) == status) then return index end
		end
		return nil
	end
	local function active(report)
		return phaseIndex(report, "Session", "ACTIVE") ~= nil
	end
	local function failureToast(mock)
		return mock.playerGui:FindFirstChild("PinkDotLock_LoadFailure")
	end
	local function noSuccess(mock)
		for _, node in ipairs(mock.playerGui:GetDescendants()) do
			check(node.Text ~= "Successfully Loaded | Press C to Lock", "success was announced after a critical failure")
		end
	end
	local function failResult(mock, api, report, fragment)
		check(report and report.ready == false, "failure returned a ready report")
		check(not active(report), "failure was marked ACTIVE")
		check(contains(errorText(api, report), fragment), "missing error detail: " .. tostring(errorText(api, report)))
		check(mock:hasLog(fragment), "error detail not logged: " .. mock:logText())
		check(mock:hasLog("[SEDWARE]"), "failure lacked a SEDWARE console prefix")
		noSuccess(mock)
		check(mock:countConnections() == 0, "failure leaked listeners")
	end
	local function pressC(mock, processed)
		mock.services.UserInputService.InputBegan:Fire(mock:input("Keyboard", 0, 0, "C"), processed == true)
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
		local api = reloadBundle(mock.env)
		local ok, problem = pcall(body, mock, api)
		cleanup(mock)
		if not ok then
			failures += 1
			print("FAIL SEDWARE STARTUP " .. name .. ": " .. tostring(problem))
		elseif mock:countConnections() ~= 0 then
			failures += 1
			print("FAIL SEDWARE STARTUP " .. name .. ": cleanup left connected listeners")
		end
	end
	local shortWait = {InitializationTimeout = 0.3, InitializationPollInterval = 0.05}

	test("normal startup traces critical phases and then welcomes", function(mock, api)
		local start = mock:getTime()
		local session, report = api.tryInit()
		check(session ~= nil and report.ready == true)
		check(mock:getTime() == start, "ready clients were unnecessarily delayed")
		for _, phase in ipairs({"Execution", "Modules", "Configuration", "Services", "LocalPlayer", "PlayerGui", "CurrentCamera", "Graphics", "Input", "Session"}) do
			check(phaseIndex(report, phase) ~= nil, "missing startup phase " .. phase)
			check(mock:hasLog("[" .. phase .. "]"), "missing console phase " .. phase)
		end
		check(active(report))
		check(phaseIndex(report, "Graphics") < phaseIndex(report, "Input"))
		check(phaseIndex(report, "Input") < phaseIndex(report, "Session", "ACTIVE"))
		check(session.overlay.title.Text == "SEDWARE")
		check(session.overlay.body.Text == "Successfully Loaded | Press C to Lock")
		check(session.overlay.toast.Visible)
		check(mock:countSignalConnections(mock.services.UserInputService.InputBegan) == 1)
		check(session.config.PredictionX == 0.1205 and session.config.PredictionY == 0.0800)
		session:destroy()
		check(mock:countConnections() == 0)
	end)

	test("temporary PlayerGui absence waits before creating graphics", function(mock, api)
		mock.playerGui.Parent = nil
		local start = mock:getTime()
		mock:schedule(0.05, function()
			check(not mock:hasLog("[Session][ACTIVE]"), "session activated while PlayerGui was absent")
			check(mock:countConnections() == 0)
		end)
		mock:schedule(0.15, function() mock.playerGui.Parent = mock.services.Players.LocalPlayer end)
		local session, report = api.tryInit(shortWait)
		check(session ~= nil and report.ready == true)
		check(mock:getTime() - start >= 0.15 and mock:getTime() - start <= 0.3)
		check(phaseIndex(report, "PlayerGui", "WAIT") ~= nil)
		check(session.overlay.gui.Parent == mock.playerGui)
		check(session.overlay.title.Text == "SEDWARE" and active(report))
	end)

	test("temporary CurrentCamera absence waits and resumes", function(mock, api)
		mock.world.CurrentCamera = nil
		mock:schedule(0.05, function()
			check(mock.playerGui:FindFirstChild("PinkDotLock") == nil)
			check(mock:countConnections() == 0)
		end)
		mock:schedule(0.15, function() mock.world.CurrentCamera = mock.camera end)
		local session, report = api.tryInit(shortWait)
		check(session ~= nil and report.ready == true)
		check(phaseIndex(report, "CurrentCamera", "WAIT") ~= nil)
		check(active(report) and session.overlay.body.Text == "Successfully Loaded | Press C to Lock")
	end)

	test("temporary LocalPlayer absence waits", function(mock, api)
		local player = mock.services.Players.LocalPlayer
		mock.services.Players.LocalPlayer = nil
		mock:schedule(0.15, function() mock.services.Players.LocalPlayer = player end)
		local session, report = api.tryInit(shortWait)
		check(session ~= nil and report.ready == true)
		check(phaseIndex(report, "LocalPlayer", "WAIT") ~= nil)
		check(session.player == player)
	end)

	test("zero viewport is transient readiness rather than a successful load", function(mock, api)
		mock.camera.ViewportSize = mock.Vector2.new(0, 0)
		mock:schedule(0.05, function()
			check(mock.playerGui:FindFirstChild("PinkDotLock") == nil)
			check(not mock:hasLog("[Session][ACTIVE]"))
		end)
		mock:schedule(0.15, function() mock.camera.ViewportSize = mock.Vector2.new(1280, 720) end)
		local session, report = api.tryInit(shortWait)
		check(session ~= nil and report.ready == true)
		check(phaseIndex(report, "CurrentCamera", "WAIT") ~= nil)
		check(active(report))
	end)

	test("PlayerGui timeout is bounded and console reports the resource", function(mock, api)
		mock.playerGui.Parent = nil
		local start = mock:getTime()
		local session, report = api.tryInit({InitializationTimeout = 0.2, InitializationPollInterval = 0.05})
		check(session == nil and report.timedOut == true)
		check(mock:getTime() - start >= 0.2 - 1e-7 and mock:getTime() - start <= 0.25)
		failResult(mock, api, report, "PlayerGui")
		check(failureToast(mock) == nil, "a toast was attached to an unavailable PlayerGui")
	end)

	test("camera timeout reports its reason in a brief visible failure toast", function(mock, api)
		mock.world.CurrentCamera = nil
		local session, report = api.tryInit({InitializationTimeout = 0.2, InitializationPollInterval = 0.05})
		check(session == nil and report.timedOut == true)
		failResult(mock, api, report, "CurrentCamera")
		local toast = failureToast(mock)
		check(toast ~= nil)
		check(toast:FindFirstChild("Title", true).Text == "SEDWARE | Load Failed")
		check(contains(toast:FindFirstChild("Body", true).Text, "CurrentCamera"))
		mock:advance(2.1)
		check(failureToast(mock) == nil)
	end)

	test("readiness timeout is one shared deadline across resources", function(mock, api)
		mock.playerGui.Parent = nil
		mock.world.CurrentCamera = nil
		local start = mock:getTime()
		mock:schedule(0.15, function() mock.playerGui.Parent = mock.services.Players.LocalPlayer end)
		mock:schedule(0.4, function() mock.world.CurrentCamera = mock.camera end)
		local session, report = api.tryInit({InitializationTimeout = 0.2, InitializationPollInterval = 0.05})
		check(session == nil and report.timedOut == true)
		check(mock:getTime() - start <= 0.25, "each resource started another timeout")
		failResult(mock, api, report, "CurrentCamera")
		check(failureToast(mock) ~= nil, "prepared PlayerGui did not receive the timeout error")
	end)

	test("unsupported required API fails immediately rather than waiting", function(mock, api)
		mock.services.GuiService.GetGuiInset = nil
		local start = mock:getTime()
		local session, report = api.tryInit(shortWait)
		check(session == nil and mock:getTime() == start)
		failResult(mock, api, report, "GetGuiInset")
	end)

	test("server execution context is explicitly rejected", function(mock, api)
		mock.services.RunService.IsClient = function() return false end
		local start = mock:getTime()
		local session, report = api.tryInit(shortWait)
		check(session == nil and mock:getTime() == start)
		failResult(mock, api, report, "IsClient")
	end)

	test("GetService exceptions identify the denied service and original error", function(mock, api)
		local getService = mock.env.game.GetService
		mock.env.game.GetService = function(game, name)
			if name == "RunService" then error("controlled RunService permission failure") end
			return getService(game, name)
		end
		local session, report = api.tryInit(shortWait)
		check(session == nil)
		failResult(mock, api, report, "controlled RunService permission failure")
	end)

	test("invalid native GUI inset is a critical failure with its concrete reason", function(mock, api)
		mock.services.GuiService.GetGuiInset = function() return nil end
		local session, report = api.tryInit()
		check(session == nil)
		failResult(mock, api, report, "GUI inset")
	end)

	test("invalid editable configuration fails visibly", function(mock, api)
		local session, report = api.tryInit({PredictionX = -1})
		check(session == nil)
		failResult(mock, api, report, "PredictionX")
		check(phaseIndex(report, "Configuration") ~= nil)
		check(failureToast(mock) ~= nil)
	end)

	test("exceptions during configuration validation retain the original reason", function(mock, api)
		local module = api.Modules.Config
		module.new = function() error("controlled configuration exception") end
		local ok, session, report = pcall(api.tryInit)
		check(ok and session == nil, "tryInit propagated a configuration exception")
		failResult(mock, api, report, "controlled configuration exception")
	end)

	test("unexpected runtime audit errors retain useful details", function(mock, api)
		api.Modules.Runtime.check = function() error("controlled runtime audit exception") end
		local ok, session, report = pcall(api.tryInit)
		check(ok and session == nil, "tryInit propagated a runtime audit exception")
		failResult(mock, api, report, "controlled runtime audit exception")
	end)

	test("GUI creation error produces an independent minimal failure notification", function(mock, api)
		local new = mock.env.Instance.new
		mock.env.Instance.new = function(className)
			if className == "CanvasGroup" then error("controlled CanvasGroup construction failure") end
			return new(className)
		end
		local session, report = api.tryInit()
		check(session == nil)
		failResult(mock, api, report, "controlled CanvasGroup construction failure")
		check(mock.playerGui:FindFirstChild("PinkDotLock") == nil)
		local toast = failureToast(mock)
		check(toast ~= nil, "failure notification retried the failing full overlay")
		check(contains(toast:FindFirstChild("Body", true).Text, "CanvasGroup"))
	end)

	test("failure notification errors are also logged without leaked resources", function(mock, api)
		local new = mock.env.Instance.new
		mock.env.Instance.new = function(className)
			if className == "Frame" then error("controlled Frame construction denial") end
			return new(className)
		end
		local ok, session, report = pcall(api.tryInit)
		check(ok and session == nil)
		failResult(mock, api, report, "controlled Frame construction denial")
		check(failureToast(mock) == nil)
		check(mock:hasLog("FailureNotification"))
	end)

	test("InputBegan connection errors never announce a successful session", function(mock, api)
		mock.services.UserInputService.InputBegan.Connect = function() error("controlled InputBegan connection failure") end
		local session, report = api.tryInit()
		check(session == nil)
		failResult(mock, api, report, "controlled InputBegan connection failure")
		check(mock.playerGui:FindFirstChild("PinkDotLock") == nil)
	end)

	test("disconnected InputBegan return value is rejected", function(mock, api)
		mock.services.UserInputService.InputBegan.Connect = function()
			return {Connected = false, Disconnect = function() end}
		end
		local session, report = api.tryInit()
		check(session == nil)
		failResult(mock, api, report, "InputBegan")
	end)

	test("render event registration failure cleans up the registered C listener", function(mock, api)
		mock.services.RunService.RenderStepped.Connect = function() error("controlled render connection failure") end
		local session, report = api.tryInit()
		check(session == nil)
		failResult(mock, api, report, "controlled render connection failure")
		check(mock:countSignalConnections(mock.services.UserInputService.InputBegan) == 0)
	end)

	test("C without candidates reports its diagnostics and visible result", function(mock, api)
		local session, report = api.tryInit({DebugMode = true, LockMode = "ThirdPerson"})
		check(session ~= nil and active(report))
		table.clear(mock.logs)
		pressC(mock)
		check(session:GetLockedTarget() == nil)
		check(session.overlay.title.Text == "SEDWARE")
		check(session.overlay.body.Text == "No valid target")
		check(session.overlay.toast.Visible)
		for _, fragment in ipairs({"[Input]", "C", "mode=ThirdPerson", "reference=", "evaluated=", "valid=0", "rejections=", "selected="}) do
			check(mock:hasLog(fragment), "C diagnostic missing " .. fragment .. ": " .. mock:logText())
		end
		check(mock.counters.candidateScans == 1)
	end)

	test("C with mixed candidates logs rejection reasons and the selected target", function(mock, api)
		local V = mock.env.Vector3
		local winner = mock:addPlayer("Winner", V.new(5, 0, -50))
		local dead = mock:addPlayer("Dead", V.new(0, 0, -50)); mock:kill(dead)
		local outside = mock:addPlayer("Outside", V.new(500, 0, -50))
		local blocked = mock:addPlayer("Blocked", V.new(0, 0, -50)); mock:setOccluded(blocked, true)
		local session = api.init({DebugMode = true, LockMode = "FirstPerson"})
		table.clear(mock.logs)
		pressC(mock)
		check(session:GetLockedTarget() == winner)
		check(session.overlay.dot.Visible)
		for _, fragment in ipairs({"mode=FirstPerson", "reference=", "evaluated=", "valid=1", "rejections=", "Dead", "Outside", "Blocked", "selected=Winner"}) do
			check(mock:hasLog(fragment), "selection diagnostic missing " .. fragment .. ": " .. mock:logText())
		end
		mock:resetCounters()
		mock:advance(0.1)
		check(mock.counters.cameraWrites == 0 and mock.counters.mouseWrites == 0)
	end)

	test("debug mode explains ignored C input while Roblox processes it", function(mock, api)
		local session = api.init({DebugMode = true})
		table.clear(mock.logs)
		pressC(mock, true)
		check(session:GetLockedTarget() == nil and mock.counters.candidateScans == 0)
		check(mock:hasLog("[Input]") and mock:hasLog("processed"))
	end)

	test("debug mode explains C ignored while typing", function(mock, api)
		local session = api.init({DebugMode = true})
		local box = mock.env.Instance.new("TextBox"); box:CaptureFocus()
		table.clear(mock.logs)
		pressC(mock)
		check(session:GetLockedTarget() == nil and mock.counters.candidateScans == 0)
		check(mock:hasLog("[Input]") and mock:hasLog("TextBox"))
		box:ReleaseFocus(); box:Destroy()
	end)

	test("C input guard exceptions are logged and release the failed session", function(mock, api)
		local session = api.init({DebugMode = true})
		table.clear(mock.logs)
		mock.services.UserInputService.GetFocusedTextBox = function() error("controlled input focus API failure") end
		local ok, problem = pcall(pressC, mock)
		check(ok, "native input callback propagated an error: " .. tostring(problem))
		check(session.destroyed)
		check(mock:hasLog("controlled input focus API failure"))
		check(mock:countConnections() == 0)
		check(failureToast(mock) ~= nil)
	end)

	test("restart leaves one owner and exactly one C listener", function(mock, api)
		local target = mock:addPlayer("RestartTarget", mock.env.Vector3.new(0, 0, -50))
		mock:setPointer(640, 360)
		local first = api.init()
		pressC(mock)
		check(first:GetLockedTarget() == target)
		local otherApi = reloadBundle(mock.env)
		local second, report = otherApi.tryInit()
		check(second ~= nil and active(report))
		check(first.destroyed and first.overlay.destroyed and #first.connections == 0 and #first.targetConnections == 0)
		check(mock:countSignalConnections(mock.services.UserInputService.InputBegan) == 1)
		local owners, overlays = 0, 0
		for _, child in ipairs(mock.playerGui:GetChildren()) do
			if child.Name == "PinkDotLock_Owner_v1" then owners += 1 end
			if child.Name == "PinkDotLock" then overlays += 1 end
		end
		check(owners == 1 and overlays == 1)
		mock:resetCounters(); pressC(mock)
		check(second:GetLockedTarget() == target and mock.counters.candidateScans == 1)
		second:destroy()
		check(mock:countConnections() == 0)
		mock:resetCounters(); pressC(mock)
		check(mock.counters.candidateScans == 0)
	end)

	test("failed replacement preserves a working session and its C connection", function(mock, api)
		local first = api.init()
		local connections = mock:countConnections()
		local new = mock.env.Instance.new
		mock.env.Instance.new = function(className)
			if className == "CanvasGroup" then error("controlled replacement construction failure") end
			return new(className)
		end
		local other = reloadBundle(mock.env)
		local second, report = other.tryInit()
		check(second == nil and report.ready == false and not active(report))
		check(not first.destroyed and first.overlay.gui.Parent == mock.playerGui)
		check(mock:countConnections() == connections)
		check(mock:countSignalConnections(mock.services.UserInputService.InputBegan) == 1)
		check(failureToast(mock) ~= nil)
	end)

	test("a newer reentrant init cancels the pending init without removing its session", function(mock, api)
		mock.playerGui.Parent = nil
		local second, secondReport
		mock:schedule(0.05, function() second, secondReport = api.tryInit(shortWait) end)
		mock:schedule(0.15, function() mock.playerGui.Parent = mock.services.Players.LocalPlayer end)
		local first, firstReport = api.tryInit(shortWait)
		check(first == nil and firstReport.ready == false and firstReport.cancelled == true)
		check(not active(firstReport), "superseded init was marked active")
		check(second ~= nil and active(secondReport) and not second.destroyed)
		check(api.session == second)
		check(api.compatibility == secondReport, "cancelled init overwrote the active session's diagnostic report")
		check(failureToast(mock) == nil, "normal supersession was announced as a load failure")
		check(mock:countSignalConnections(mock.services.UserInputService.InputBegan) == 1)
		local owners, overlays = 0, 0
		for _, child in ipairs(mock.playerGui:GetChildren()) do
			if child.Name == "PinkDotLock_Owner_v1" then owners += 1 end
			if child.Name == "PinkDotLock" then overlays += 1 end
		end
		check(owners == 1 and overlays == 1)
	end)

	test("missing task.wait cannot create an infinite readiness wait", function(mock, api)
		mock.world.CurrentCamera = nil
		mock.env.task.wait = nil
		local start = mock:getTime()
		local session, report = api.tryInit(shortWait)
		check(session == nil and mock:getTime() == start)
		failResult(mock, api, report, "task.wait")
	end)

	test("task.wait exceptions are logged and bounded", function(mock, api)
		mock.world.CurrentCamera = nil
		mock.env.task.wait = function() error("controlled readiness wait exception") end
		local session, report = api.tryInit(shortWait)
		check(session == nil)
		failResult(mock, api, report, "controlled readiness wait exception")
	end)

	test("frozen clocks still stop readiness after the iteration bound", function(mock, api)
		mock.world.CurrentCamera = nil
		local calls = 0
		mock.env.task.wait = function() calls += 1; return 0 end
		local session, report = api.tryInit({InitializationTimeout = 0.2, InitializationPollInterval = 0.05})
		check(session == nil and calls > 0 and calls <= 6)
		failResult(mock, api, report, "CurrentCamera")
	end)

	test("autostart failure reports once and never emits a welcome", function(mock, api)
		mock.world.CurrentCamera = nil
		mock.env.PINK_DOT_NO_AUTOSTART = false
		local automaticallyLoaded = reloadBundle(mock.env)
		check(automaticallyLoaded.session == nil)
		check(automaticallyLoaded.compatibility.ready == false)
		check(failureToast(mock) ~= nil)
		noSuccess(mock)
		local failuresLogged = 0
		for _, entry in ipairs(mock.logs) do
			if contains(entry.text, "[SEDWARE][Load Failed]") then failuresLogged += 1 end
		end
		check(failuresLogged == 1, "expected one Load Failed summary, got " .. tostring(failuresLogged))
		check(mock:countConnections() == 0)
	end)

	test("editable header constructor errors are caught after execution begins", function(mock, api)
		mock.env.Color3.fromRGB = function() error("controlled editable colour construction failure") end
		mock.env.PINK_DOT_NO_AUTOSTART = false
		local ok, failed = pcall(reloadBundle, mock.env)
		check(ok, "editable header construction propagated out of the bundle")
		check(failed.session == nil and failed.compatibility.ready == false)
		check(mock:hasLog("[Execution][START]"))
		check(mock:hasLog("[Configuration][FAIL]"))
		check(mock:hasLog("controlled editable colour construction failure"))
		check(mock.playerGui:FindFirstChild("PinkDotLock") == nil)
		check(mock:countConnections() == 0)
		noSuccess(mock)
	end)

	test("autostart without Roblox game reports an unsupported runtime", function(mock, api)
		mock.env.game = nil
		mock.env.workspace = nil
		mock.env.PINK_DOT_NO_AUTOSTART = false
		local ok, failed = pcall(reloadBundle, mock.env)
		check(ok, "missing native game unexpectedly propagated out of the bundle")
		check(failed.session == nil and failed.compatibility.ready == false)
		check(mock:hasLog("[Execution][START]"))
		check(mock:hasLog("game:GetService"))
		check(mock:hasLog("[Services][FAIL]"))
		check(mock:countConnections() == 0)
		noSuccess(mock)
	end)

	print(string.format("SEDWARE startup doubles: %d tests, %d assertions, %d failures", tests, assertions, failures))
	assert(failures == 0, "SEDWARE startup tests failed")
	return {tests = tests, checks = assertions}
end

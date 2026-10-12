--!nonstrict
-- Executed by scripts/check.py with the actual bundled Interface loaded inside
-- RobloxMock's environment. Verifies control events and connection cleanup only.
-- Engine layout, pixels, input dispatch and replication still require Studio.
return function(mock, bundle, reloadBundle)
	local Interface = bundle.Modules.Interface
	local C = bundle.Modules.Configuration
	local tests, failures, checks = 0, 0, 0
	local fixtures = {}
	local function check(condition, message)
		checks += 1
		assert(condition, message or ("assertion failed at line " .. tostring(debug.info(2, "l"))))
	end
	local function near(actual, expected, tolerance)
		check(type(actual) == "number" and math.abs(actual - expected) <= (tolerance or 1e-9),
			"expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
	local function test(name, body)
		tests += 1
		local ok, err = pcall(body)
		if not ok then failures += 1; print("FAIL GUI " .. name .. ": " .. tostring(err)) end
		-- Always clean up a failed fixture too, so leaked listeners cannot make a
		-- later test pass by mutating stale configuration through old callbacks.
		for _, fixture in ipairs(fixtures) do fixture.ui:destroy() end
		table.clear(fixtures)
	end
	local function applyPath(config, path, value)
		local segments = string.split(path, ".")
		local node = config
		for index = 1, #segments - 1 do
			local segment = segments[index]
			if segment == "profile" and node == config then node = config.profiles[config.activeProfile]
			else node = node[segment] end
		end
		node[segments[#segments]] = value
	end
	local function fixture(initial)
		local current = initial or C.new()
		local calls, last = {}, {}
		local ui
		local http = mock.services.HttpService
		local function invoked(name, value)
			calls[name] = (calls[name] or 0) + 1
			last[name] = value
		end
		ui = Interface.new(current, {
			onChange = function(path, value)
				invoked("change", {path = path, value = value})
				local candidate = C.createSnapshot(current)
				applyPath(candidate, path, value)
				local accepted, message = C.validate(candidate)
				if not accepted then return false, message end
				current = candidate
				ui:setConfig(current)
				return true
			end,
			onSave = function()
				invoked("save")
				return http:JSONEncode(C.toEnvelope(current))
			end,
			onLoad = function(text)
				invoked("load", text)
				local ok, envelope = pcall(http.JSONDecode, http, text)
				if not ok then return false, "JSON no válido." end
				local loaded, message = C.fromEnvelope(envelope)
				if not loaded then return false, message end
				current = loaded
				ui:setConfig(current)
				return true
			end,
			onReset = function() invoked("reset"); current = C.new(); ui:setConfig(current) end,
			onUnload = function() invoked("unload"); ui:destroy() end,
			onFire = function() invoked("fire") end,
			onClearMeasurements = function() invoked("clear") end,
			onExportMeasurements = function()
				invoked("export")
				return http:JSONEncode({schemaVersion = 1, measurements = {{errorStuds = 1.5}}})
			end,
			onApplyCalibration = function() invoked("apply"); return true, "Sugerencia aplicada." end,
		})
		local result = {ui = ui, calls = calls, last = last, config = function() return current end}
		function result:button(name)
			local control = mock:find(name, ui.gui)
			check(control ~= nil, "missing control " .. name)
			return control
		end
		function result:control(path, kind)
			for _, control in ipairs(ui.controls) do
				if control.path == path and (kind == nil or control.kind == kind) then return control.instance end
			end
			error("missing " .. tostring(kind) .. " control " .. path)
		end
		function result:click(name) self:button(name).Activated:Fire() end
		table.insert(fixtures, result)
		return result
	end

	test("real tab and dropdown events change visibility and selection", function()
		local f = fixture()
		check(f.ui.gui.Name == "DHPredictionLab")
		check(f.ui.pages.MAIN.Visible)
		for _, name in ipairs({"PREDICTION", "WEAPONS", "DIAGNOSTICS", "SETTINGS", "MAIN"}) do
			f.ui.tabs[name].Activated:Fire()
			for pageName, page in pairs(f.ui.pages) do check(page.Visible == (pageName == name)) end
		end
		f:control("core.memoryTracking", "dropdown").Activated:Fire()
		check(f.ui.dropdowns[1].options.Visible)
		f:click("Velocity")
		check(f.config().core.memoryTracking == false)
		check(f.ui.dropdowns[1].options.Visible == false)
		check(f:control("core.memoryTracking", "dropdown").Text == "Velocity  ▾")
		f:click("Memory")
		check(f.config().core.memoryTracking == true)
		f:control("activeProfile", "dropdown").Activated:Fire()
		f:click("Custom")
		check(f.config().activeProfile == "Custom")
		f:control("targetMode", "dropdown").Activated:Fire()
		f:click("OwnCharacters")
		check(f.config().targetMode == "OwnCharacters")
		f:control("activeProfile", "dropdown").Activated:Fire()
		f.ui.tabs.PREDICTION.Activated:Fire()
		for _, dropdown in ipairs(f.ui.dropdowns) do check(not dropdown.options.Visible) end
	end)

	test("toggle events map to actual configuration fields and refresh labels", function()
		local f = fixture()
		for _, path in ipairs({"core.enabled", "core.autoPrediction", "pingCompensation", "core.velocityPrediction",
			"core.distancePrediction", "core.memoryTracking", "core.accelerationPrediction", "adaptiveCalibration", "useSimulatedPing"}) do
			local button = f:control(path, "toggle")
			local original = f.ui:_value(path)
			button.Activated:Fire()
			check(f.ui:_value(path) == not original, "toggle did not change " .. path)
			check(button.Text == (not original and "ON" or "OFF"))
			check(f.last.change.path == path)
			button.Activated:Fire()
			check(f.ui:_value(path) == original)
		end
		near(f.calls.change, 18)
	end)

	test("number inputs validate bounds and preserve separate profile settings", function()
		local f = fixture()
		local manual = f:control("profile.manualDelaySeconds", "number")
		manual.Text = "0.151"
		manual.FocusLost:Fire()
		near(f.config().profiles.Revolver.manualDelaySeconds, 0.151)
		check(manual.Text == "0.151")
		f:click("Custom")
		check(manual.Text == "0.080")
		manual.Text = "0.213"
		manual.FocusLost:Fire()
		near(f.config().profiles.Custom.manualDelaySeconds, 0.213)
		near(f.config().profiles.Revolver.manualDelaySeconds, 0.151)
		local number = f:control("core.fovPixels", "number")
		local original, priorCalls = f.config().core.fovPixels, f.calls.change
		for _, bad in ipairs({"not a number", "-1", "1001", "1e309"}) do
			number.Text = bad
			number.FocusLost:Fire()
			near(f.config().core.fovPixels, original)
			near(f.calls.change, priorCalls)
		end
		-- Zero is in the numeric widget's broad bounds, but the real schema must
		-- reject a projectile with no speed and retain its prior valid value.
		local speed = f:control("profile.speed", "number")
		speed.Text = "0"
		speed.FocusLost:Fire()
		near(f.config().profiles.Custom.speed, 180)
		check(string.find(f.ui.status.Text, "positiva") ~= nil)
		number:CaptureFocus()
		number.Text = "275"
		f.ui:refreshControls()
		check(number.Text == "275", "refresh overwrote active editing")
		number:ReleaseFocus()
		near(f.config().core.fovPixels, 275)
	end)

	test("save and load events transport validated snapshots and reject invalid imports atomically", function()
		local f = fixture()
		local manual = f:control("profile.manualDelaySeconds", "number")
		manual.Text = "0.177"
		manual.FocusLost:Fire()
		f:click("SaveConfiguration")
		check(f.calls.save == 1 and f.ui.editor.Text ~= "")
		check(f.ui.pages.SETTINGS.Visible and f.ui.pendingEditorScroll)
		local saved = f.ui.editor.Text
		local envelope = mock.services.HttpService:JSONDecode(saved)
		check(envelope.schemaVersion == 1 and C.validate(envelope.configuration))
		near(envelope.configuration.profiles.Revolver.manualDelaySeconds, 0.177)
		-- Supply a measured editor position; UIListLayout itself belongs to the
		-- engine and is deliberately not emulated by these event doubles.
		f.ui.editorRow.Position = mock.env.UDim2.fromOffset(0, 240)
		f.ui:update({})
		check(f.ui.pendingEditorScroll == false)
		check(f.ui.pages.SETTINGS.CanvasPosition.Y > 0)
		manual.Text = "0.052"
		manual.FocusLost:Fire()
		f.ui.editor.Text = saved
		f:click("LoadConfiguration")
		check(f.calls.load == 1 and f.last.load == saved)
		near(f.config().profiles.Revolver.manualDelaySeconds, 0.177)
		for _, invalid in ipairs({"not-json", mock.services.HttpService:JSONEncode({schemaVersion = 2, configuration = {}}),
			mock.services.HttpService:JSONEncode({schemaVersion = 1, configuration = {core = {enabled = "true"}}})}) do
			f.ui.editor.Text = invalid
			f:click("LoadConfiguration")
			near(f.config().profiles.Revolver.manualDelaySeconds, 0.177)
			check(C.validate(f.config()))
		end
		f:click("ResetConfiguration")
		near(f.calls.reset, 1)
		near(f.config().profiles.Revolver.manualDelaySeconds, 0.08)
		f:click("ClearMeasurements")
		f:click("ApplyCalibration")
		f:click("Fire")
		near(f.calls.clear, 1)
		near(f.calls.apply, 1)
		near(f.calls.fire, 1)
		f:click("ExportMeasurements")
		near(f.calls.export, 1)
		check(mock.services.HttpService:JSONDecode(f.ui.editor.Text).measurements[1].errorStuds == 1.5)
	end)

	test("hide restore minimize and pointer guards follow actual button events", function()
		local f = fixture()
		f:click("Hide")
		check(not f.ui.panel.Visible and f.ui.restore.Visible)
		mock:setPointer(50, 60)
		check(not f.ui:isPointerOver(), "hidden panel still intercepted the pointer")
		mock:setPointer(20, 680)
		check(f.ui:isPointerOver(), "restore control failed its pointer guard")
		f:click("RestoreMenu")
		check(f.ui.panel.Visible and not f.ui.restore.Visible)
		mock:setPointer(50, 60)
		check(f.ui:isPointerOver())
		f:click("Minimize")
		check(f.ui.collapsed and not f.ui.content.Visible and not f.ui.fireButton.Visible)
		near(f.ui.panel.Size.Y.Offset, 54)
		f:click("Minimize")
		check(not f.ui.collapsed and f.ui.content.Visible and f.ui.fireButton.Visible)
		near(f.ui.panel.Size.Y.Offset, 670)
		f:click("HideMenu")
		check(not f.ui.panel.Visible and f.ui.restore.Visible)
		f:click("RestoreMenu")
		f.ui.gui.Enabled = false
		check(not f.ui:isPointerOver())
	end)

	test("mouse and touch drag use connected input events and viewport clamps", function()
		local f = fixture()
		local input = mock.services.UserInputService
		local drag = f:button("DragHandle")
		local start = mock:input("MouseButton1", 50, 60)
		local initialX, initialY = f.ui.panel.Position.X.Offset, f.ui.panel.Position.Y.Offset
		drag.InputBegan:Fire(start)
		input.InputChanged:Fire(mock:input("MouseMovement", 150, 160))
		near(f.ui.panel.Position.X.Offset, initialX + 100)
		-- A full-height panel starts at the viewport's lower margin and clamps.
		check(f.ui.panel.Position.Y.Offset <= 720 - f.ui.panel.AbsoluteSize.Y)
		input.InputEnded:Fire(start)
		local stoppedX, stoppedY = f.ui.panel.Position.X.Offset, f.ui.panel.Position.Y.Offset
		input.InputChanged:Fire(mock:input("MouseMovement", 500, 500))
		near(f.ui.panel.Position.X.Offset, stoppedX)
		near(f.ui.panel.Position.Y.Offset, stoppedY)
		local touch = mock:input("Touch", 10, 10)
		drag.InputBegan:Fire(touch)
		touch.Position = mock.env.Vector3.new(-1000, -1000, 0)
		input.InputChanged:Fire(touch)
		near(f.ui.panel.Position.X.Offset, 0)
		near(f.ui.panel.Position.Y.Offset, 0)
		input.InputEnded:Fire(touch)
		mock.camera.ViewportSize = mock.Vector2.new(375, 667)
		f.ui:update({})
		near(f.ui.scale.Scale, math.min((375 - 24) / 620, (667 - 32) / 670))
		check(f.ui.panel.AbsoluteSize.X <= 375 and f.ui.panel.AbsoluteSize.Y <= 667)
		local replacement = mock.env.Instance.new("Camera")
		replacement.ViewportSize = mock.Vector2.new(1920, 1080)
		mock.world.CurrentCamera = replacement
		near(f.ui.scale.Scale, 1)
		mock.world.CurrentCamera = mock.camera
		mock.camera.ViewportSize = mock.Vector2.new(1280, 720)
	end)

	test("updates reach repeated metrics and destroyed controls disconnect all listeners", function()
		local f = fixture()
		local baseline = mock:countConnections()
		check(baseline > 40, "mock did not connect the actual interface events")
		f.ui:update({delay = "81 ms", predicted = "1,2,3", status = "Ready"})
		for _, key in ipairs({"delay", "predicted", "status"}) do
			check(#f.ui.metrics[key] == 2)
			for _, metric in ipairs(f.ui.metrics[key]) do
				check(metric.Text == ({delay = "81 ms", predicted = "1,2,3", status = "Ready"})[key])
			end
		end
		local fire = f:button("Fire")
		f:click("Unload")
		near(f.calls.unload, 1)
		check(f.ui.destroyed and f.ui.gui.Parent == nil)
		near(#f.ui.connections, 0)
		near(mock:countConnections(), 0)
		fire.Activated:Fire()
		check(f.calls.fire == nil, "destroyed control's callback remained connected")
		f.ui:destroy()
		f.ui:update({status = "after destroy"})
		check(not f.ui:isPointerOver())
		local nextFixture = fixture()
		nextFixture:click("Close")
		near(nextFixture.calls.unload, 1)
		near(mock:countConnections(), 0)
	end)

	test("callback errors and unavailable actions become visible status without breaking the GUI", function()
		local ui = Interface.new(C.new(), {onSave = function() error("controlled failure") end})
		table.insert(fixtures, {ui = ui})
		mock:find("SaveConfiguration", ui.gui).Activated:Fire()
		check(string.find(ui.status.Text, "controlled failure") ~= nil)
		mock:find("Fire", ui.gui).Activated:Fire()
		check(string.find(ui.status.Text, "onFire") ~= nil)
		mock:find("Close", ui.gui).Activated:Fire()
		check(ui.destroyed)
		near(mock:countConnections(), 0)
	end)

	-- No Character is spawned in these lifecycle tests. They cover Session's
	-- real callbacks and ownership of events; target geometry and firing physics
	-- are exercised separately in numerical tests and must be run in Studio.
	local function newSession(options)
		local session = bundle.init(options)
		table.insert(fixtures, {ui = session.ui})
		return session
	end
	test("Session callbacks load snapshots reject invalid imports and reset tracking atomically", function()
		mock:setTime(1)
		mock:setPointer(1300, 0)
		local session = newSession()
		check(session.predictor.settings == session.config.core)
		check(session.autoPredictor.tracks == session.predictor.tracks)
		check(session.manualPredictor.tracks == session.predictor.tracks)
		local enabled = mock:find("core.enabled", session.ui.gui)
		enabled.Activated:Fire()
		check(session.config.core.enabled == false)
		check(session.predictor.settings == session.config.core)
		enabled.Activated:Fire()
		local manual
		for _, control in ipairs(session.ui.controls) do
			if control.path == "profile.manualDelaySeconds" then manual = control.instance; break end
		end
		manual.Text = "0.173"
		manual.FocusLost:Fire()
		mock:find("SaveConfiguration", session.ui.gui).Activated:Fire()
		local saved = session.ui.editor.Text
		near(mock.services.HttpService:JSONDecode(saved).configuration.profiles.Revolver.manualDelaySeconds, 0.173)
		manual.Text = "0.091"
		manual.FocusLost:Fire()
		session.ui.editor.Text = saved
		mock:find("LoadConfiguration", session.ui.gui).Activated:Fire()
		near(session.config.profiles.Revolver.manualDelaySeconds, 0.173)
		check(session.predictor.settings == session.config.core)
		local unchanged = session.config
		for _, invalid in ipairs({string.rep("x", 65537), "malformed-json",
			mock.services.HttpService:JSONEncode({schemaVersion = 1, configuration = {core = {enabled = "true"}}})}) do
			session.ui.editor.Text = invalid
			mock:find("LoadConfiguration", session.ui.gui).Activated:Fire()
			check(session.config == unchanged)
			near(session.config.profiles.Revolver.manualDelaySeconds, 0.173)
		end
		local oldPredictor = session.predictor
		session.pending[1] = {old = true}
		session.shots[1] = {old = true}
		local projectilePart = mock.env.Instance.new("Part")
		projectilePart.Parent = session.world
		session.projectiles[1] = {part = projectilePart}
		for _, control in ipairs(session.ui.controls) do
			if control.path == "core.memoryTracking" and control.kind == "toggle" then control.instance.Activated:Fire(); break end
		end
		check(session.predictor ~= oldPredictor)
		check(session.config.core.memoryTracking == false)
		near(#session.pending, 0)
		near(#session.shots, 0)
		near(#session.projectiles, 0)
		check(projectilePart._destroyed)
		check(session.autoPredictor.tracks == session.predictor.tracks)
		mock:find("ResetConfiguration", session.ui.gui).Activated:Fire()
		near(session.config.profiles.Revolver.manualDelaySeconds, 0.08)
		check(session.config.core.memoryTracking)
		mock:find("Fire", session.ui.gui).Activated:Fire()
		check(string.find(session.ui.status.Text, "blanco") ~= nil)
		session:destroy()
		near(mock:countConnections(), 0)
	end)

	test("Session steps convert RTT milliseconds once and ping control preserves automatic mode", function()
		for index, rtt in ipairs({8, 60, 150, 180}) do
			local session = newSession({configuration = {simulatedRTTMilliseconds = rtt}})
			local stamp = 10 + index
			mock:setTime(stamp)
			session:step(0.1, stamp)
			near(session.rtt, rtt / 1000)
			near(session.actualOneWay, rtt / 2000)
			near(session.predictor.latency.raw, rtt / 2000)
			near(session.autoPredictor.latency.raw, rtt / 2000)
			near(session.manualPredictor.latency.raw, rtt / 2000)
			check(session.config.core.autoPrediction)
			mock:find("pingCompensation", session.ui.gui).Activated:Fire()
			mock:setTime(stamp + 0.3)
			session:step(0.1, stamp + 0.3)
			near(session.actualOneWay, rtt / 2000)
			near(session.predictor.latency.raw, 0)
			check(session.config.core.autoPrediction, "ping toggle changed prediction mode")
			session:destroy()
			near(mock:countConnections(), 0)
		end
	end)

	test("Session measurement truth uses physical transport time independently of configured prediction lead", function()
		mock:setTime(10)
		local session = newSession()
		local zero = mock.env.Vector3.new(0, 0, 0)
		local result = {targetPosition = zero, position = zero, velocity = mock.env.Vector3.new(0, 0, 3.6),
			state = "running", sampleTime = 9.95, range = "close", flightSeconds = 0,
			delaySeconds = 0.35, predictionHorizonSeconds = 0.6}
		local spec = {base = zero, width = 0, epoch = 10, phase = 0, period = 4.5}
		session.selected = "known-motion"
		session.targets[session.selected] = {spec = spec}
		session.solution = result
		session.actualOneWay = 0.09
		session._origin = function() return zero end
		-- Stub ONLY the predictions being queued. The actual Session scheduling,
		-- analytical reference trajectory and diagnostic recording all execute.
		for _, predictor in ipairs({session.predictor, session.autoPredictor, session.manualPredictor}) do
			predictor.predict = function() return result end
		end
		session:_queueMeasurements(10)
		near(#session.pending, 3)
		for _, pending in ipairs(session.pending) do near(pending.due, 10.09) end
		local due = session.pending[1].due
		session:_measure(due)
		near(#session.pending, 0)
		-- A target moves during the real 90 ms transport. A zero-position
		-- prediction therefore has measurable error even though its configured
		-- horizon could claim it predicts much further into the future.
		local expectedError = math.abs(4 * math.sin((due - spec.epoch) * 0.9))
		check(expectedError > 0)
		near(session.lastError, expectedError)
		local diagnostics = session.diagnostics:summary()
		near(diagnostics.predictionCount, 1)
		near(diagnostics.predictionRMSEStuds, expectedError)
		local calibration = session.calibration:summary("Revolver", "close", due)
		near(calibration.autoCount, 1)
		near(calibration.manualCount, 1)
		near(calibration.autoRMSEStuds, expectedError)
		near(calibration.manualRMSEStuds, expectedError)
		near(calibration.confidenceSamples, 1)
		result.predictionHorizonSeconds = 0.9
		result.delaySeconds = 0.5
		session:_queueMeasurements(10)
		near(#session.pending, 3)
		for _, pending in ipairs(session.pending) do near(pending.due, due) end
		-- Flight is physical elapsed time, so it adds to the reference time.
		table.clear(session.pending)
		result.flightSeconds = 0.2
		session:_queueMeasurements(10)
		for _, pending in ipairs(session.pending) do near(pending.due, 10.29) end
		session:destroy()
		near(mock:countConnections(), 0)
	end)

	test("changing the target source clears previous laboratory truth and calibration confidence", function()
		local session = newSession()
		check(session.diagnostics:recordPrediction({errorStuds = 2, weapon = "Revolver", range = "close"}))
		check(session.calibration:record({weapon = "Revolver", range = "close", mode = "auto", now = 1,
			errorStuds = 1, residual = mock.env.Vector3.new(1, 0, 0), velocity = mock.env.Vector3.new(10, 0, 0)}))
		session.pending[1] = {old = true}
		session.lastError = 2
		local changed, message = session:_change("targetMode", "OwnCharacters")
		check(changed, message)
		check(session.config.targetMode == "OwnCharacters")
		near(#session.pending, 0)
		check(session.lastError == nil)
		near(session.diagnostics:summary().predictionCount, 0)
		local summary = session.calibration:summary("Revolver", "close")
		near(summary.autoCount, 0)
		near(summary.manualCount, 0)
		near(summary.confidenceSamples, 0)
		near(summary.suggestedOffsetSeconds, 0)
		session:destroy()
		near(mock:countConnections(), 0)
	end)

	test("Session reruns preserve one owner and unload disconnects global input and render events", function()
		mock:setPointer(1300, 0)
		local first = newSession()
		local firstWorld = first.world
		local baseline = mock:countConnections()
		check(baseline > 40)
		local invalid, message = pcall(bundle.init, {configuration = {activeProfile = "Unknown"}})
		check(not invalid and type(message) == "string")
		check(not first.destroyed, "invalid rerun destroyed the working session")
		check(first.ui.gui.Parent == mock.playerGui)
		near(mock:countConnections(), baseline)
		local input = mock.services.UserInputService
		input.InputBegan:Fire(mock:input("MouseButton2", 1300, 0), false)
		check(first.rightMouse)
		input.WindowFocusReleased:Fire()
		check(not first.rightMouse)
		input.InputBegan:Fire(mock:input("MouseButton2", 1300, 0), true)
		check(not first.rightMouse)
		input.InputBegan:Fire(mock:input("MouseButton2", 1300, 0), false)
		input.InputEnded:Fire(mock:input("MouseButton2", 1300, 0))
		check(not first.rightMouse)
		local second = newSession()
		check(first.destroyed and firstWorld._destroyed and first.ui.destroyed)
		near(mock:countConnections(), baseline)
		local menus, worlds = 0, 0
		for _, child in ipairs(mock.playerGui:GetChildren()) do if child.Name == "DHPredictionLab" then menus += 1 end end
		for _, child in ipairs(mock.world:GetChildren()) do if child.Name == "DHPredictionLabLocal" then worlds += 1 end end
		near(menus, 1)
		near(worlds, 1)
		second.ui.stopEvent:Fire()
		check(second.destroyed and second.ui.destroyed and second.world._destroyed)
		near(mock:countConnections(), 0)
		input.InputBegan:Fire(mock:input("MouseButton2", 1300, 0), false)
		check(not second.rightMouse)
		mock.services.RunService.RenderStepped:Fire(0.1)
		near(#second.pending, 0)
		second:destroy()
		near(mock:countConnections(), 0)
	end)

	local function withPatch(object, key, value, body)
		local previous = object[key]
		object[key] = value
		local ok, message = pcall(body)
		object[key] = previous
		assert(ok, message)
	end
	local function containsText(items, fragment)
		for _, item in ipairs(items or {}) do
			if string.find(tostring(item), fragment, 1, true) then return true end
		end
		return false
	end
	test("compatibility audit is read-only and distinguishes optional capabilities", function()
		local instances, listeners = #mock.instances, mock:countConnections()
		local report = bundle.checkCompatibility()
		check(report.ready, table.concat(report.missing or {}, ", "))
		near(#mock.instances, instances)
		near(mock:countConnections(), listeners)
		check(report.services.Players == mock.services.Players)
		check(report.player == mock.services.Players.LocalPlayer)
		check(report.playerGui == mock.playerGui and report.world == mock.world)
		check(report.capabilities.spherecast == false)
		check(report.capabilities.networkPing == false)
		check(#report.warnings > 0)
		withPatch(mock.world, "CurrentCamera", nil, function()
			local noCamera = bundle.checkCompatibility()
			check(noCamera.ready)
			check(noCamera.capabilities.camera == false)
			check(#noCamera.warnings > 0)
		end)
		local invoked = 0
		withPatch(mock.world, "Spherecast", function() invoked += 1; error("audit invoked cast") end, function()
			withPatch(mock.services.Players.LocalPlayer, "GetNetworkPing", function() invoked += 1; error("audit invoked ping") end, function()
				local capable = bundle.checkCompatibility()
				check(capable.ready and capable.capabilities.spherecast and capable.capabilities.networkPing)
				near(invoked, 0)
			end)
		end)
	end)

	test("required missing APIs and player GUI produce descriptive compatibility reports", function()
		withPatch(mock.services.RunService, "IsClient", function() return false end, function()
			local report = bundle.checkCompatibility()
			check(not report.ready and #report.missing > 0)
			check(type(bundle.Modules.Runtime.errorMessage(report)) == "string")
		end)
		withPatch(mock.env, "CFrame", nil, function()
			local report = bundle.checkCompatibility()
			check(not report.ready and containsText(report.missing, "CFrame"))
		end)
		withPatch(mock.env.game, "GetService", function(self, name)
			if name == "HttpService" then error("controlled missing service") end
			return mock.services[name]
		end, function()
			local report = bundle.checkCompatibility()
			check(not report.ready and containsText(report.missing, "HttpService"))
		end)
		withPatch(mock.services.GuiService, "GetGuiInset", nil, function()
			local report = bundle.checkCompatibility()
			check(not report.ready and containsText(report.missing, "GetGuiInset"))
		end)
		withPatch(mock.playerGui, "Parent", nil, function()
			local report = bundle.checkCompatibility()
			check(not report.ready and containsText(report.missing, "PlayerGui"))
		end)
		check(bundle.checkCompatibility().ready)
		near(mock:countConnections(), 0)
	end)

	test("failed compatibility checks preserve the existing session and its listeners", function()
		local session = newSession()
		local listeners = mock:countConnections()
		withPatch(mock.services.RunService, "IsClient", function() return false end, function()
			local failed, report = bundle.tryInit()
			check(failed == nil and report.ready == false)
			check(not session.destroyed and session.ui.gui.Parent == mock.playerGui)
			near(mock:countConnections(), listeners)
			local strict, message = pcall(bundle.init)
			check(not strict and type(message) == "string")
			check(not session.destroyed)
		end)
		session:destroy()
		near(mock:countConnections(), 0)
	end)

	test("constructor failures clean partially built GUI resources and global listeners", function()
		local originalNew = mock.env.Instance.new
		withPatch(mock.env.Instance, "new", function(className)
			if className == "TextBox" then error("controlled constructor failure") end
			return originalNew(className)
		end, function()
			local session, report = bundle.tryInit()
			check(session == nil and report.ready == false)
			check(string.find(bundle.Modules.Runtime.errorMessage(report), "controlled constructor failure", 1, true) ~= nil)
			check(mock.playerGui:FindFirstChild("DHPredictionLab") == nil)
			check(mock.world:FindFirstChild("DHPredictionLabLocal") == nil)
			near(mock:countConnections(), 0)
		end)
		local recovered, report = bundle.tryInit()
		check(recovered ~= nil and report.ready)
		table.insert(fixtures, {ui = recovered.ui})
		local baseline = mock:countConnections()
		withPatch(mock.env.Instance, "new", function(className)
			if className == "TextBox" then error("controlled second constructor failure") end
			return originalNew(className)
		end, function()
			local replacement, failedReport = bundle.tryInit()
			check(replacement == nil and not failedReport.ready)
			check(not recovered.destroyed)
			check(mock.playerGui:FindFirstChild("DHPredictionLab") == recovered.ui.gui)
			check(mock.world:FindFirstChild("DHPredictionLabLocal") == recovered.world)
			local menus, worlds = 0, 0
			for _, child in ipairs(mock.playerGui:GetChildren()) do if child.Name == "DHPredictionLab" then menus += 1 end end
			for _, child in ipairs(mock.world:GetChildren()) do if child.Name == "DHPredictionLabLocal" then worlds += 1 end end
			near(menus, 1)
			near(worlds, 1)
			near(mock:countConnections(), baseline)
		end)
		recovered:destroy()
		near(mock:countConnections(), 0)
	end)

	test("unsupported script objects do not prevent client startup or cleanup", function()
		withPatch(mock.env, "script", {}, function()
			local session, report = bundle.tryInit()
			check(session ~= nil and report.ready)
			table.insert(fixtures, {ui = session.ui})
			session:destroy()
			near(mock:countConnections(), 0)
		end)
	end)

	test("a failing render step pauses once and retains the menu for unloading", function()
		local session = newSession()
		local attempts = 0
		session.rightMouse = true
		session.step = function()
			attempts += 1
			error("controlled frame failure")
		end
		mock.services.RunService.RenderStepped:Fire(0.1)
		mock.services.RunService.RenderStepped:Fire(0.1)
		near(attempts, 1)
		check(not session.destroyed and not session.ui.destroyed)
		check(session.ui.gui.Parent == mock.playerGui)
		check(not session.rightMouse)
		check(string.find(session.ui.status.Text, "controlled frame failure", 1, true) ~= nil)
		mock:find("Unload", session.ui.gui).Activated:Fire()
		check(session.destroyed)
		near(mock:countConnections(), 0)
	end)

	test("a real viewport layout failure pauses without repeating the failing GUI update", function()
		local session = newSession()
		mock:setTime(50)
		withPatch(mock.camera, "ViewportSize", nil, function()
			-- Execute the actual Session.step and Interface.update/_fit path. A
			-- missing native viewport fails layout; its handler must use controls
			-- that remain available instead of invoking that layout path again.
			local handled, message = pcall(mock.services.RunService.RenderStepped.Fire,
				mock.services.RunService.RenderStepped, 0.1)
			check(handled, message)
			check(session.paused and not session.destroyed)
			check(string.find(session.ui.status.Text, "Pausado", 1, true) ~= nil)
			for _, metric in ipairs(session.ui.metrics.status) do
				check(string.find(metric.Text, "Pausado", 1, true) ~= nil)
			end
			local previousPingTime = session.lastPingSample
			mock:setTime(50.3)
			local subsequent, subsequentMessage = pcall(mock.services.RunService.RenderStepped.Fire,
				mock.services.RunService.RenderStepped, 0.1)
			check(subsequent, subsequentMessage)
			near(session.lastPingSample, previousPingTime)
		end)
		-- The patch restores the viewport even when an assertion fails; unload
		-- remains available without attempting another simulation or fit pass.
		mock:find("Unload", session.ui.gui).Activated:Fire()
		check(session.destroyed)
		near(mock:countConnections(), 0)
	end)

	test("automatic startup returns a compatibility report when native constructors are unavailable", function()
		check(type(reloadBundle) == "function", "generated harness must supply reloadBundle(env)")
		withPatch(mock.env, "DHPREDICTION_NO_AUTOSTART", false, function()
			withPatch(mock.env, "CFrame", nil, function()
				local ok, automatic = pcall(reloadBundle, mock.env)
				check(ok, automatic)
				check(type(automatic) == "table" and automatic.session == nil)
				check(type(automatic.compatibility) == "table" and automatic.compatibility.ready == false)
				check(containsText(automatic.compatibility.missing, "CFrame"))
				check(mock.playerGui:FindFirstChild("DHPredictionLab") == nil)
				check(mock.world:FindFirstChild("DHPredictionLabLocal") == nil)
				near(mock:countConnections(), 0)
			end)
		end)
		local logs = {}
		withPatch(mock.env, "warn", nil, function()
			withPatch(mock.env, "print", function(message) table.insert(logs, message) end, function()
				bundle.Modules.Runtime.reportFailure("controlled logger fallback")
			end)
		end)
		near(#logs, 1)
		check(string.find(logs[1], "controlled logger fallback", 1, true) ~= nil)
	end)

	print(string.format("GUI event doubles: %d tests, %d assertions, %d failures", tests, checks, failures))
	assert(failures == 0, "GUI event tests failed")
	return {tests = tests, checks = checks}
end

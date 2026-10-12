--!nonstrict
-- The actual standalone SEDWARE bundle, its real ShotAdapter, and both owned
-- weapon controllers. Sphere/plane intersections below are explicit physics
-- doubles: this suite does not verify Roblox Studio or Da Hood physics.
local ClientController = require("../src/pink_weapon/ClientController")
local ServerController = require("../src/pink_weapon/ServerController")

return function(mock, api, reloadBundle)
	local tests, failures, checks = 0, 0, 0
	local V = mock.env.Vector3
	local sessions, targets, clients, servers = {}, {}, {}, {}
	local function check(condition, message)
		checks += 1
		assert(condition, message or ("assertion failed at line " .. tostring(debug.info(2, "l"))))
	end
	local function near(actual, expected, tolerance)
		check(type(actual) == "number" and actual == actual and math.abs(actual - expected) <= (tolerance or 1e-8),
			"expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
	local function vectorNear(actual, expected)
		check(actual ~= nil and expected ~= nil)
		near(actual.X, expected.X); near(actual.Y, expected.Y); near(actual.Z, expected.Z)
	end
	local function pressC()
		mock.services.UserInputService.InputBegan:Fire(mock:input("Keyboard", 0, 0, "C"), false)
	end
	local function session(config)
		mock:setTime(20)
		mock:setCameraDistance(20)
		mock:setPointer(640, 360)
		local created = api.init(config)
		table.insert(sessions, created)
		return created
	end
	local function target(name, position)
		local created = mock:addPlayer(name, position or V.new(0, 0, -50))
		table.insert(targets, created)
		return created
	end
	local function clear()
		for _, client in clients do client:destroy() end
		for _, server in servers do server:destroy() end
		for _, current in sessions do current:destroy() end
		for _, current in targets do
			mock:removePlayer(current)
			if current.Character then current.Character:Destroy() end
			current:Destroy()
		end
		table.clear(clients); table.clear(servers); table.clear(sessions); table.clear(targets)
	end
	local function test(name, body)
		tests += 1
		local ok, problem = pcall(body)
		if not ok then failures += 1; print("FAIL PINK OWNED BUNDLE " .. name .. ": " .. tostring(problem)) end
		clear()
	end
	local function rig(options)
		options = options or {}
		local shooter = mock.services.Players.LocalPlayer
		local shooterHumanoid = shooter.Character:FindFirstChildOfClass("Humanoid")
		shooterHumanoid.Health = 100
		local state = {
			equipped = true, tool = {}, origin = V.new(0, 2, 0),
			cameraAim = V.new(100, 2, -40), cameraCalls = 0, raycasts = 0,
			damageCalls = 0, statuses = {}, queue = {}, wall = false, forceMiss = false,
			lastRayOrigin = nil, lastRayDirection = nil,
		}
		local function clock() return mock.world:GetServerTimeNow() end
		local function getTarget(userId, partName, character)
			for _, player in targets do
				if player.UserId == userId and player.Character == character then
					local part = character:FindFirstChild(partName)
					return if part then {player = player, character = character, part = part,
						humanoid = character:FindFirstChildOfClass("Humanoid"), position = part.Position} else nil
				end
			end
			return nil
		end
		local server = ServerController.new({
			clock = clock,
			getEquippedWeapon = function(player)
				return if state.equipped and player == shooter then {tool = state.tool, character = shooter.Character,
					humanoid = shooterHumanoid, origin = state.origin} else nil
			end,
			getTarget = getTarget,
			raycast = function(origin, direction, ignoreCharacter)
				state.raycasts += 1
				state.lastRayOrigin, state.lastRayDirection = origin, direction
				check(ignoreCharacter == shooter.Character, "server did not exclude the shooter's character")
				if state.forceMiss then return nil end
				local unit = direction.Unit
				local closest, closestDistance = nil, math.huge
				-- A controlled wall plane, not a native Workspace raycast.
				if state.wall and math.abs(unit.Z) > 1e-8 then
					local distance = (-10 - origin.Z) / unit.Z
					if distance > 0 and distance <= direction.Magnitude then
						closest, closestDistance = {name = "TestWall", position = origin + unit * distance}, distance
					end
				end
				-- Explicit target spheres with radius 2 studs. Contact depends on the
				-- authoritative ray direction, never the requested prediction alone.
				for _, player in targets do
					local character = player.Character
					local part = character and character:FindFirstChild("HumanoidRootPart")
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					if part and humanoid and humanoid.Health > 0 then
						local offset = origin - part.Position
						local b, c = offset:Dot(unit), offset:Dot(offset) - 4
						local discriminant = b * b - c
						if discriminant >= 0 then
							local distance = -b - math.sqrt(discriminant)
							if distance > 0 and distance <= direction.Magnitude and distance < closestDistance then
								closestDistance = distance
								closest = {name = character.Name, character = character, humanoid = humanoid,
									playerUserId = player.UserId, position = origin + unit * distance}
							end
						end
					end
				end
				return closest
			end,
			describeHit = function(result) return result end,
			applyDamage = function(humanoid, amount)
				state.damageCalls += 1
				local before = humanoid.Health
				if not state.damageBlocked then humanoid.Health = math.max(0, before - amount) end
				return {before = before, after = humanoid.Health}
			end,
		})
		local client = ClientController.new({api = api, clock = clock, sessionId = options.sessionId or "owned-bundle-tests",
			isEquipped = function() return state.equipped end,
			getOrigin = function() return state.origin end,
			getCameraAim = function() state.cameraCalls += 1; return state.cameraAim end,
			send = function(request) table.insert(state.queue, request) end,
			onStatus = function(kind, details) table.insert(state.statuses, {kind = kind, details = details}) end,
		})
		table.insert(clients, client); table.insert(servers, server)
		state.client, state.server, state.shooter = client, server, shooter
		function state:confirm(request)
			local response = self.server:process(self.shooter, request)
			return self.client:receive(response), response
		end
		return state
	end

	test("C and actual public prediction direct the owned weapon while both camera modes stay free", function()
		local selected = target("LockedTarget")
		for _, mode in {"FirstPerson", "ThirdPerson"} do
			local s = session({LockMode = mode, PredictionSmoothing = 0})
			pressC()
			check(api.GetLockedTarget() == selected)
			near(s.config.PredictionX, 0.1205); near(s.config.PredictionY, 0.0800)
			local r = rig({sessionId = "camera-" .. mode})
			mock:resetCounters()
			local request, problem = r.client:fire()
			check(request ~= nil, problem)
			check(request.mode == "Locked" and request.targetCharacter == selected.Character)
			vectorNear(request.aimpoint, api.GetPredictedPosition())
			check((request.aimpoint - r.cameraAim).Magnitude > 10)
			near(r.cameraCalls, 0)
			local result, response = r:confirm(request)
			check(result and result.accepted and result.hit and result.selectedTargetHit, response.reason)
			near(response.damageApplied, 25)
			vectorNear(r.lastRayDirection.Unit, (request.aimpoint - r.origin).Unit)
			near(mock.counters.cameraWrites, 0); near(mock.counters.mouseWrites, 0)
			r.client:destroy(); r.server:destroy(); s:destroy()
			selected.Character:FindFirstChildOfClass("Humanoid").Health = 100
		end
	end)

	test("normal unlocked fire follows camera aim with no lock or measurement ticket", function()
		local selected = target("NormalTarget")
		local s = session()
		local r = rig()
		r.cameraAim = selected.Character:FindFirstChild("HumanoidRootPart").Position
		local request, problem = r.client:fire()
		check(request ~= nil, problem)
		check(request.mode == "Normal" and request.ticketId == nil and request.targetUserId == nil)
		check(api.GetLockedTarget() == nil and api.GetPredictedPosition() == nil)
		vectorNear(request.aimpoint, r.cameraAim)
		near(r.cameraCalls, 1)
		local result = r:confirm(request)
		check(result and result.accepted and result.hit and not result.selectedTargetHit)
		check(result.measurement == nil)
		near(r.client.adapter:summary().measurementCount, 0)
		near(s.lastError or 0, 0)
	end)

	test("no local impact or success is announced before independent server confirmation", function()
		local selected = target("Unconfirmed")
		session(); pressC()
		local r = rig()
		local humanoid = selected.Character:FindFirstChildOfClass("Humanoid")
		local request = r.client:fire()
		check(request ~= nil)
		near(r.client:summary().pending, 1)
		near(r.client:summary().confirmed, 0); near(r.client:summary().hits, 0)
		near(r.raycasts, 0); near(r.damageCalls, 0); near(humanoid.Health, 100)
		check(r.client.lastResult == nil)
		check(#r.statuses == 1 and r.statuses[1].kind == "Pending")
		local result = r:confirm(request)
		check(result and result.selectedTargetHit and result.measurement ~= nil)
		near(r.client:summary().confirmed, 1)
		near(r.client:summary().measurementCount, 1)
		near(humanoid.Health, 75)
		check(r.statuses[2].kind == "Confirmed")
	end)

	test("wall contact is recorded as a surface impact without inventing target damage", function()
		local selected = target("BehindWall")
		session(); pressC()
		local r = rig(); r.wall = true
		local request = r.client:fire()
		local result, response = r:confirm(request)
		check(result and result.accepted and result.hit and not result.selectedTargetHit)
		check(result.hitName == "TestWall" and response.reason == "surface-impact")
		near(result.damageApplied, 0); near(r.damageCalls, 0)
		near(selected.Character:FindFirstChildOfClass("Humanoid").Health, 100)
		check(result.measurement ~= nil, "a real reference can measure prediction even when the wall blocks damage")
	end)

	test("accepted miss remains a miss even with a valid selected player and prediction", function()
		target("NotHit")
		session(); pressC()
		local r = rig(); r.forceMiss = true
		local result, response = r:confirm(r.client:fire())
		check(result and result.accepted and not result.hit and not result.selectedTargetHit)
		check(response.reason == "miss")
		near(r.client:summary().hits, 0); near(r.client:summary().misses, 1)
		near(r.damageCalls, 0); near(result.damageApplied, 0)
	end)

	test("server-observed blocked damage stays zero despite confirmed target contact", function()
		local selected = target("ProtectedTarget")
		session(); pressC()
		local r = rig(); r.damageBlocked = true
		local result = r:confirm(r.client:fire())
		check(result and result.selectedTargetHit)
		near(result.damageApplied, 0); near(r.damageCalls, 1)
		near(selected.Character:FindFirstChildOfClass("Humanoid").Health, 100)
	end)

	test("memory observations and automatic prediction reach the same actual weapon path", function()
		local selected = target("MovingMemory")
		local s = session({MemoryTracking = true, AutoPrediction = true, PredictionSmoothing = 0})
		pressC()
		for index = 1, 10 do
			mock:move(selected, V.new(index * 0.25, index * 0.1, -50 - index * 0.1))
			mock:advance(0.05)
		end
		local prediction = s:GetPrediction()
		check(s.config.MemoryTracking and s.config.AutoPrediction)
		check(prediction.velocity.Magnitude > 1 and (prediction.position - prediction.currentPosition).Magnitude > 0.1)
		near(s.config.PredictionX, 0.1205); near(s.config.PredictionY, 0.0800)
		check(s.comparisons.manual ~= nil and s.comparisons.auto ~= nil)
		local r = rig()
		local request, problem = r.client:fire()
		check(request ~= nil, problem)
		vectorNear(request.aimpoint, api.GetPredictedPosition())
		near(r.cameraCalls, 0)
		local result = r:confirm(request)
		check(result and result.accepted and result.measurement ~= nil)
		check(result.measurement.manual ~= nil and result.measurement.auto ~= nil)
		near(s.lastError, result.measurement.active.errorStuds)
	end)

	test("changing the lock after firing preserves the server hit but rejects stale-lock measurement", function()
		local selected = target("OldLock")
		local other = target("NewLock", V.new(80, 0, -50))
		local s = session()
		pressC(); check(api.GetLockedTarget() == selected)
		local r = rig()
		local request = r.client:fire()
		pressC(); check(api.GetLockedTarget() == nil)
		mock:setPointer(720, 360); pressC()
		check(api.GetLockedTarget() == other)
		local result = r:confirm(request)
		check(result and result.accepted and result.hit and result.selectedTargetHit)
		check(result.measurement == nil and result.measurementError == "target-invalid")
		near(r.client:summary().measurementCount, 0)
		check(s.lastError == nil)
	end)

	test("unlocking switches the next shot to ordinary aim without moving the camera", function()
		target("ToggleTarget")
		session(); pressC()
		local r = rig()
		mock:resetCounters()
		local locked = r.client:fire()
		check(locked and locked.mode == "Locked")
		pressC()
		local normal = r.client:fire()
		check(normal and normal.mode == "Normal")
		vectorNear(normal.aimpoint, r.cameraAim)
		near(r.cameraCalls, 1)
		near(mock.counters.cameraWrites, 0); near(mock.counters.mouseWrites, 0)
	end)

	test("timeouts and duplicate acknowledgments never fabricate measurements or additional hits", function()
		target("TimeoutTarget")
		session(); pressC()
		local r = rig()
		local first = r.client:fire()
		local result, response = r:confirm(first)
		check(result and result.selectedTargetHit)
		local duplicate, reason = r.client:receive(response)
		check(duplicate == nil and reason == "unknown-or-expired-shot")
		near(r.client:summary().confirmed, 1); near(r.client:summary().measurementCount, 1)
		mock:advance(0.4)
		local second = r.client:fire()
		check(second ~= nil)
		mock:advance(2.1); r.client:step()
		near(r.client:summary().pending, 0); near(r.client:summary().timedOut, 1)
		near(r.client:summary().confirmed, 1)
		check(r.statuses[#r.statuses].kind == "Timeout")
		local late = r.client:receive({sessionId = second.sessionId, shotId = second.shotId, accepted = false, mode = "Locked"})
		check(late == nil)
	end)

	test("unload clears session and weapon adapters and restart retains one input listener", function()
		target("ReloadTarget")
		local first = session(); pressC()
		local old = rig({sessionId = "old-controller"})
		local adapter = old.client.adapter
		check(old.client:fire() ~= nil)
		check(#first.adapters == 1)
		old.client:destroy(); api.Unload()
		check(first.destroyed and adapter.destroyed)
		near(mock:countConnections(), 0)
		near(old.client:summary().pending, 0)
		local shot, reason = old.client:fire()
		check(shot == nil and reason == "destroyed")
		api = reloadBundle(mock.env)
		local second = session()
		near(mock:countSignalConnections(mock.services.UserInputService.InputBegan), 1)
		local new = rig({sessionId = "new-controller"})
		pressC(); check(api.GetLockedTarget() ~= nil)
		check(new.client:fire() ~= nil)
		near(#second.adapters, 1)
		near(mock:countSignalConnections(mock.services.UserInputService.InputBegan), 1)
		new.client:destroy(); new.client:destroy(); second:destroy(); second:destroy()
		near(mock:countConnections(), 0)
	end)

	test("replacing the controller prunes destroyed adapters without creating duplicate listeners", function()
		target("ControllerRestart")
		local s = session(); pressC()
		local listeners = mock:countConnections()
		for index = 1, 40 do
			local r = rig({sessionId = "replacement-" .. index})
			check(#s.adapters == 1, "destroyed adapters accumulated")
			check(r.client:fire() ~= nil)
			r.client:destroy(); r.server:destroy()
			near(mock:countConnections(), listeners)
		end
		near(mock:countSignalConnections(mock.services.UserInputService.InputBegan), 1)
		s:destroy()
		near(mock:countConnections(), 0)
	end)

	print(string.format("Pink owned weapon bundle doubles: %d tests, %d assertions, %d failures", tests, checks, failures))
	assert(failures == 0, "Pink owned weapon bundle tests failed")
	return {tests = tests, checks = checks}
end

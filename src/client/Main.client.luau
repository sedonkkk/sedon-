--!nonstrict
-- Client for the Aim Lab place only: native UI, target selection and local visuals.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("AimLab")
local Settings = require(shared:WaitForChild("Settings"))
local Predictor = require(shared:WaitForChild("Predictor"))
local Weapons = require(shared:WaitForChild("Weapons"))
local Diagnostics = require(shared:WaitForChild("Diagnostics"))
local Interface = require(script.Parent:WaitForChild("Interface"))

local remotes = ReplicatedStorage:WaitForChild("AimLabRemotes")
local snapshotRemote = remotes:WaitForChild("Snapshot")
local settingsRemote = remotes:WaitForChild("Settings")
local fireRemote = remotes:WaitForChild("Fire")
local observationRemote = remotes:WaitForChild("Observation")
local telemetryRemote = remotes:WaitForChild("Telemetry")

local settings = Settings.new()
local predictor = Predictor.new(settings)
local diagnostics = Diagnostics.new(600)
local targets = {}
local connections = {}
local selectedId = nil
local solution = nil
local rightMouseDown = false
local destroyed = false
local lastFireTime = -math.huge
local shotCounter = 0
local updateAccumulator = 0
local observationAccumulator = 0
local uiAccumulator = 0
local lastShotText = "—"
local lastSpreadText = "—"
local lastSnapshotTime = nil
local lastPingRoundTripSeconds = nil
local selectionMouse = UserInputService:GetMouseLocation()
local ui

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end

local function finiteNumber(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function finiteVector(value)
	return typeof(value) == "Vector3" and finiteNumber(value.X) and finiteNumber(value.Y) and finiteNumber(value.Z)
end

local function originPosition()
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position + Vector3.new(0, 1.5, 0)
	end
	return nil
end

local playerGui = player:WaitForChild("PlayerGui")
local oldOverlay = playerGui:FindFirstChild("AimLabOverlay")
if oldOverlay then
	oldOverlay:Destroy()
end
local overlay = Instance.new("ScreenGui")
overlay.Name = "AimLabOverlay"
overlay.IgnoreGuiInset = true
overlay.ResetOnSpawn = false
overlay.DisplayOrder = 10
overlay.Parent = playerGui

local fovCircle = Instance.new("Frame")
fovCircle.Name = "FieldOfView"
fovCircle.BackgroundTransparency = 1
fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
fovCircle.Parent = overlay
local circleCorner = Instance.new("UICorner")
circleCorner.CornerRadius = UDim.new(1, 0)
circleCorner.Parent = fovCircle
local circleStroke = Instance.new("UIStroke")
circleStroke.Color = Color3.fromRGB(88, 211, 191)
circleStroke.Transparency = 0.35
circleStroke.Thickness = 1
circleStroke.Parent = fovCircle

local aimDot = Instance.new("Frame")
aimDot.Name = "PredictionPoint"
aimDot.Size = UDim2.fromOffset(8, 8)
aimDot.AnchorPoint = Vector2.new(0.5, 0.5)
aimDot.BackgroundColor3 = Color3.fromRGB(255, 196, 98)
aimDot.BorderSizePixel = 0
aimDot.Visible = false
aimDot.Parent = overlay
local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = aimDot

local marker = Instance.new("Part")
marker.Name = "AimLabLocalPrediction"
marker.Shape = Enum.PartType.Ball
marker.Size = Vector3.new(0.6, 0.6, 0.6)
marker.Color = Color3.fromRGB(255, 196, 98)
marker.Material = Enum.Material.Neon
marker.Anchored = true
marker.CanCollide = false
marker.CanTouch = false
marker.CanQuery = false
marker.CastShadow = false
marker.Transparency = 1
marker.Parent = workspace

local function cleanup()
	if destroyed then
		return
	end
	destroyed = true
	rightMouseDown = false
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	predictor:clear()
	overlay:Destroy()
	marker:Destroy()
	if ui then
		ui:destroy()
	end
end

local function applyChange(key, value)
	local calibrationIndex = tonumber(string.match(key, "^pingCalibration:(%d+)$"))
	local function writeSetting(newValue)
		if key == "weaponOffset" then
			settings.weaponOffsets[settings.weapon] = newValue
		elseif calibrationIndex then
			settings.pingCalibration[calibrationIndex].offsetSeconds = newValue
		else
			settings[key] = newValue
		end
	end
	local previous = settings[key]
	if key == "weaponOffset" then
		previous = settings.weaponOffsets[settings.weapon]
	elseif calibrationIndex then
		previous = settings.pingCalibration[calibrationIndex].offsetSeconds
	end
	writeSetting(value)
	local valid, message = Settings.validate(settings)
	if not valid then
		writeSetting(previous)
		return false, message
	end
	-- Existing Predictor instances keep this settings table by reference.
	if key == "simulationDelaySeconds" then
		settingsRemote:FireServer({ simulationDelaySeconds = settings.simulationDelaySeconds })
	end
	if key == "memoryTracking" then
		predictor:clear()
		for id, target in pairs(targets) do
			predictor:observe(id, target)
		end
	end
	if not settings.enabled then
		selectedId = nil
		solution = nil
	end
	return true
end

local function fire()
	if destroyed then
		return
	end
	local origin = originPosition()
	if not settings.enabled or not selectedId or not solution or not origin then
		ui:setStatus("Selecciona un objetivo visible en el escenario.", true)
		return
	end
	local now = workspace:GetServerTimeNow()
	if not lastSnapshotTime or now - lastSnapshotTime > 1 then
		ui:setStatus("Esperando datos recientes del servidor.", true)
		return
	end
	local profile = Weapons.get(settings.weapon)
	if now - lastFireTime < profile.cooldown then
		return
	end
	-- Refresh the solution at firing time, even when the pointer is over the fire button.
	local fresh = predictor:predict(selectedId, origin, now, profile)
	if not fresh or not finiteVector(fresh.position) then
		ui:setStatus("No hay una solución válida para este objetivo.", true)
		return
	end
	local direction = fresh.position - origin
	if direction.Magnitude < 0.001 then
		return
	end
	lastFireTime = now
	shotCounter += 1
	fireRemote:FireServer({
		shotId = shotCounter,
		origin = origin,
		direction = direction.Unit,
		targetId = selectedId,
		weapon = settings.weapon,
		aimpoint = fresh.position,
	})
	ui:setStatus("Disparo enviado; esperando impacto.")
end

local function exportMeasurements()
	-- JSON Lines remain copyable from Studio Output without plugin/clipboard APIs.
	-- Export only simulator configuration and bounded measurement records.
	print("AIMLAB_EXPORT_BEGIN")
	print(HttpService:JSONEncode({
		type = "configuration",
		t = workspace:GetServerTimeNow(),
		settings = settings,
		summary = diagnostics:summary(),
		units = { time = "seconds", distance = "studs", spread = "radians", ping = "RTT/2 estimated one-way" },
	}))
	for _, record in ipairs(diagnostics.shots) do
		local exported = {}
		for key, value in pairs(record) do
			if type(value) == "string" or type(value) == "boolean" or finiteNumber(value) then
				exported[key] = value
			elseif finiteVector(value) then
				exported[key] = { x = value.X, y = value.Y, z = value.Z }
			end
		end
		print(HttpService:JSONEncode(exported))
	end
	for _, record in ipairs(diagnostics.predictions) do
		print(HttpService:JSONEncode(record))
	end
	print("AIMLAB_EXPORT_END")
	ui:setStatus("Mediciones JSON Lines impresas en Studio Output; selecciona y copia allí.")
end

ui = Interface.new(settings, {
	onChange = applyChange,
	onFire = fire,
	onExport = exportMeasurements,
	onClearMeasurements = function()
		diagnostics:clear()
		lastShotText = "—"
		lastSpreadText = "—"
		ui:setStatus("Mediciones borradas; empieza una nueva ventana de calibración.")
	end,
	onReset = function()
		local defaults = Settings.new()
		table.clear(settings)
		for key, value in pairs(defaults) do
			settings[key] = value
		end
		predictor:clear()
		for id, target in pairs(targets) do
			predictor:observe(id, target)
		end
		selectedId = nil
		solution = nil
		settingsRemote:FireServer({ simulationDelaySeconds = settings.simulationDelaySeconds })
		ui:setSettings(settings)
		ui:setStatus("Configuración predeterminada restaurada.")
	end,
})
connect(ui.stopEvent.Event, cleanup)
connect(script.Destroying, cleanup)
connect(ui.gui.Destroying, cleanup)

local function canSee(camera, position)
	local direction = position - camera.CFrame.Position
	if direction.Magnitude < 0.001 then
		return true
	end
	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	local excluded = { marker }
	if player.Character then
		table.insert(excluded, player.Character)
	end
	local lab = workspace:FindFirstChild("AimLab")
	local targetFolder = lab and lab:FindFirstChild("Targets")
	if targetFolder then
		table.insert(excluded, targetFolder)
	end
	parameters.FilterDescendantsInstances = excluded
	local result = workspace:Raycast(camera.CFrame.Position, direction, parameters)
	return result == nil or result.Distance >= direction.Magnitude - 0.25
end

local function selectTarget(now)
	local camera = workspace.CurrentCamera
	local origin = originPosition()
	if not settings.enabled or not camera or not origin or not lastSnapshotTime or now - lastSnapshotTime > 1 then
		selectedId = nil
		solution = nil
		return
	end
	-- Keep the last scene pointer position while interacting with the UI.
	if not ui:isPointerOver() and not UserInputService:GetFocusedTextBox() then
		selectionMouse = UserInputService:GetMouseLocation()
	end
	local inset = GuiService:GetGuiInset()
	local viewportMouse = selectionMouse - inset
	local function candidate(id)
		local target = targets[id]
		if not target then
			return nil
		end
		if (target.position - origin).Magnitude > settings.maxTargetDistanceStuds then
			return nil
		end
		local point, onScreen = camera:WorldToViewportPoint(target.position)
		if not onScreen or point.Z <= 0 then
			return nil
		end
		local distance = (Vector2.new(point.X, point.Y) - viewportMouse).Magnitude
		if distance > settings.fovPixels or not canSee(camera, target.position) then
			return nil
		end
		return distance
	end
	-- Retain a valid target to avoid oscillating between nearby bots.
	if not selectedId or candidate(selectedId) == nil then
		selectedId = nil
		local closest = math.huge
		for id in pairs(targets) do
			local distance = candidate(id)
			if distance and distance < closest then
				closest = distance
				selectedId = id
			end
		end
	end
	local profile = Weapons.get(settings.weapon)
	solution = selectedId and predictor:predict(selectedId, origin, now, profile) or nil
	if solution and not finiteVector(solution.position) then
		solution = nil
	end
end

connect(snapshotRemote.OnClientEvent, function(snapshot)
	if type(snapshot) ~= "table" or not finiteNumber(snapshot.t) or type(snapshot.targets) ~= "table" then
		return
	end
	if lastSnapshotTime and snapshot.t < lastSnapshotTime then
		return
	end
	lastSnapshotTime = snapshot.t
	if finiteNumber(snapshot.pingSeconds) and snapshot.pingSeconds >= 0 then
		predictor:setPing(snapshot.pingSeconds, snapshot.t)
		lastPingRoundTripSeconds = finiteNumber(snapshot.pingRoundTripSeconds)
			and snapshot.pingRoundTripSeconds or snapshot.pingSeconds * 2
	end
	local present = {}
	for _, target in ipairs(snapshot.targets) do
		if type(target) == "table" and type(target.id) == "string"
			and finiteVector(target.position) and finiteVector(target.velocity) then
			local sample = {
				t = snapshot.t,
				position = target.position,
				velocity = target.velocity,
				state = type(target.state) == "string" and target.state or "unknown",
			}
			present[target.id] = true
			targets[target.id] = sample
			predictor:observe(target.id, sample)
		end
	end
	for id in pairs(targets) do
		if not present[id] then
			targets[id] = nil
			predictor:forget(id)
		end
	end
end)

connect(telemetryRemote.OnClientEvent, function(record)
	if type(record) ~= "table" then
		return
	end
	if record.type == "shot" then
		if record.accepted == false then
			ui:setStatus("Disparo rechazado: " .. (record.reason or "solicitud no válida"), true)
			return
		end
		diagnostics:recordShot(record)
		local intendedHit = record.intendedHit == true or (record.intendedHit == nil and record.hit == true)
		lastShotText = intendedHit and "Acierto en objetivo elegido"
			or (record.hit and "Otro objetivo alcanzado" or "Fallo: " .. (record.reason or "sin impacto"))
		lastSpreadText = finiteNumber(record.spreadRadians)
			and string.format("%.3f°", math.deg(record.spreadRadians)) or "—"
		ui:setStatus(intendedHit and "Objetivo elegido alcanzado." or "Disparo finalizado: " .. lastShotText)
	elseif record.type == "prediction" then
		diagnostics:recordPrediction(record)
	end
end)

connect(UserInputService.InputBegan, function(input, gameProcessed)
	if gameProcessed or UserInputService:GetFocusedTextBox() or ui:isPointerOver() then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rightMouseDown = true
	elseif input.KeyCode == Enum.KeyCode.F then
		fire()
	end
end)
connect(UserInputService.InputEnded, function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rightMouseDown = false
	end
end)
connect(UserInputService.WindowFocusReleased, function()
	rightMouseDown = false
end)

local function updateMetrics()
	local summary = diagnostics:summary()
	local profile = Weapons.get(settings.weapon)
	local function weaponStats(name)
		local bucket = summary.byWeapon[name]
		return bucket and string.format("%d / %d", bucket.shots, bucket.hits) or "0 / 0"
	end
	local activeBucket = summary.byWeapon[settings.weapon]
	local live = {
		target = selectedId or "Sin objetivo",
		rtt = lastPingRoundTripSeconds and string.format("%.1f ms", lastPingRoundTripSeconds * 1000) or "—",
		ping = "—",
		delay = "—",
		speed = "—",
		distance = "—",
		predicted = "—",
		aimpoint = "—",
		motion = "—",
		flight = "—",
		horizon = "—",
		selection = settings.enabled and (selectedId and "Retenido dentro del FOV" or "Busca un bot en el FOV") or "Desactivada",
		weaponKind = profile.kind == "hitscan" and "Hitscan" or string.format("Proyectil (g = %.1f)", profile.gravity),
		weaponSpeed = profile.kind == "hitscan" and "Instantáneo" or string.format("%.0f studs/s", profile.speed),
		weaponSpread = string.format("%.3f°", math.deg(profile.spreadRadians)),
		weaponCooldown = string.format("%.3f s", profile.cooldown),
		activeStats = activeBucket and activeBucket.shots > 0
			and string.format("%.1f%% (%d / %d)", activeBucket.hitRate * 100, activeBucket.hits, activeBucket.shots) or "Sin disparos",
		activePrediction = activeBucket and (activeBucket.predictionCount or 0) > 0
			and string.format("%.3f studs / %d", activeBucket.predictionRMSEStuds, activeBucket.predictionCount) or "Sin muestras",
		shots = string.format("%d / %d", summary.shots, summary.hits),
		hitRate = string.format("%.1f%%", summary.hitRate * 100),
		rmse = summary.predictionCount > 0 and string.format("%.3f", summary.predictionRMSEStuds) or "—",
		measurementCount = tostring(summary.predictionCount),
		miss = finiteNumber(summary.missDistanceMeanStuds) and string.format("%.3f studs", summary.missDistanceMeanStuds) or "—",
		lastShot = lastShotText,
		lastSpread = lastSpreadText,
		revolverStats = weaponStats("RevolverLab"),
		projectileStats = weaponStats("ProjectileLab"),
	}
	if solution then
		live.ping = string.format("%.1f / %.1f ms", solution.rawPingSeconds * 1000, solution.smoothedPingSeconds * 1000)
		live.delay = string.format("%.1f ms", solution.delaySeconds * 1000)
		live.speed = string.format("%.1f studs/s", solution.velocity.Magnitude)
		live.distance = string.format("%.1f studs", solution.distanceStuds)
		live.predicted = string.format("%.1f, %.1f, %.1f", solution.targetPosition.X, solution.targetPosition.Y, solution.targetPosition.Z)
		live.aimpoint = string.format("%.1f, %.1f, %.1f", solution.position.X, solution.position.Y, solution.position.Z)
		live.motion = solution.state
		live.flight = string.format("%.3f s", solution.flightSeconds)
		live.horizon = string.format("%.3f s", solution.predictionHorizonSeconds)
	end
	ui:update(live)
end

-- Bounded selection/measurement/UI work; per-frame work only updates local drawings and camera.
connect(RunService.RenderStepped, function(dt)
	if destroyed then
		return
	end
	local now = workspace:GetServerTimeNow()
	updateAccumulator += dt
	observationAccumulator += dt
	uiAccumulator += dt
	if updateAccumulator >= 1 / settings.updateHz then
		updateAccumulator %= 1 / settings.updateHz
		selectTarget(now)
	end
	if observationAccumulator >= 0.2 then
		observationAccumulator %= 0.2
		if selectedId and solution then
			observationRemote:FireServer({
				id = selectedId,
				-- RMSE compares the target position, excluding projectile drop compensation.
				aimpoint = solution.targetPosition,
				horizon = solution.predictionHorizonSeconds,
				sampleTime = solution.sampleTime,
				weapon = settings.weapon,
			})
		end
	end
	if uiAccumulator >= 0.1 then
		uiAccumulator %= 0.1
		updateMetrics()
	end
	local camera = workspace.CurrentCamera
	fovCircle.Visible = settings.enabled
	fovCircle.Position = UDim2.fromOffset(selectionMouse.X, selectionMouse.Y)
	fovCircle.Size = UDim2.fromOffset(settings.fovPixels * 2, settings.fovPixels * 2)
	circleStroke.Transparency = selectedId and 0.2 or 0.6
	marker.Transparency = settings.debugVisualization and solution and 0.2 or 1
	aimDot.Visible = false
	if solution and camera then
		if settings.debugVisualization then
			marker.Position = solution.position
			local point, onScreen = camera:WorldToViewportPoint(solution.position)
			local inset = GuiService:GetGuiInset()
			aimDot.Position = UDim2.fromOffset(point.X + inset.X, point.Y + inset.Y)
			aimDot.Visible = onScreen and point.Z > 0
		end
		if settings.enabled and rightMouseDown and not ui:isPointerOver() and not UserInputService:GetFocusedTextBox() then
			local direction = solution.position - camera.CFrame.Position
			if direction.Magnitude > 0.001 then
				local desired = CFrame.lookAt(camera.CFrame.Position, solution.position)
				camera.CFrame = camera.CFrame:Lerp(desired, 1 - math.exp(-12 * dt))
			end
		end
	end
end)

settingsRemote:FireServer({ simulationDelaySeconds = settings.simulationDelaySeconds })
ui:setStatus("Laboratorio listo. Apunta el cursor a un bot y dispara con F.")

--!strict
-- This standalone place owns only workspace.AimLab and ReplicatedStorage.AimLabRemotes.
-- Client predictions are observations, never authoritative hits or movement commands.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local shared = ReplicatedStorage:WaitForChild("AimLab")
local Weapons = require(shared:WaitForChild("Weapons"))
local Geometry = require(shared:WaitForChild("Geometry"))
local closestOnSegment = Geometry.closestOnSegment
local sphereIntersection = Geometry.sphereIntersection
local SNAPSHOT_INTERVAL = 1 / 20
local MAX_RANGE = 400
local MAX_ORIGIN_OFFSET = 16
local MAX_PREDICTIONS = 24
local MAX_PREDICTION_HORIZON = 4 -- Includes sample age, transport estimate and far-target flight.
local MAX_PROJECTILES_PER_PLAYER = 12
local MAX_PROJECTILES = 128
local MAX_SUBSTEP = 1 / 120
local MAX_DELAY = 0.25
local epoch = workspace:GetServerTimeNow()
local random = Random.new()

type Target = {
	id: string,
	part: Part,
	base: Vector3,
	width: number,
	period: number,
	phase: number,
	radius: number,
}
type Observation = { id: string, aimpoint: Vector3, horizon: number, sampleTime: number, due: number, weapon: string? }
type PlayerState = {
	nextFire: number,
	lastRequest: number,
	lastObservation: number,
	lastSettings: number,
	simulationDelay: number,
	projectileCount: number,
	observations: { Observation },
	snapshots: { { due: number, payload: any } },
	recentShotIds: { [string]: boolean },
	shotOrder: { string },
}
type Projectile = {
	player: Player,
	shotId: string | number,
	weapon: string,
	targetId: string,
	origin: Vector3,
	velocity: Vector3,
	gravity: number,
	radius: number,
	spreadRadians: number,
	started: number,
	processed: number,
	lifetime: number,
	visual: Part,
	params: RaycastParams,
	closestDistance: number,
	closestTime: number,
	closestPosition: Vector3,
}

local function folder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA("Folder"), name .. " must be a Folder in this prototype")
		return existing
	end
	local result = Instance.new("Folder")
	result.Name = name
	result.Parent = parent
	return result
end

local remotes = folder(ReplicatedStorage, "AimLabRemotes")
local function remote(name: string): RemoteEvent
	local existing = remotes:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteEvent"), name .. " must be a RemoteEvent")
		return existing
	end
	local result = Instance.new("RemoteEvent")
	result.Name = name
	result.Parent = remotes
	return result
end
local Snapshot = remote("Snapshot")
local Fire = remote("Fire")
local Telemetry = remote("Telemetry")
local Settings = remote("Settings")
local Observe = remote("Observation")

local lab = folder(workspace, "AimLab")
local targetFolder = folder(lab, "Targets")
local projectileFolder = folder(lab, "Projectiles")
local effectsFolder = folder(lab, "Effects")

local function part(name: string, parent: Instance, size: Vector3, position: Vector3, color: Color3): Part
	local result = Instance.new("Part")
	result.Name = name
	result.Anchored = true
	result.Size = size
	result.Position = position
	result.Color = color
	result.TopSurface = Enum.SurfaceType.Smooth
	result.BottomSurface = Enum.SurfaceType.Smooth
	result.Parent = parent
	return result
end

if not lab:FindFirstChild("Floor") then
	local floor = part("Floor", lab, Vector3.new(100, 1, 230), Vector3.new(0, -0.5, -85), Color3.fromRGB(24, 30, 43))
	floor.Material = Enum.Material.Concrete
end
local spawn = lab:FindFirstChild("Spawn") :: SpawnLocation?
if not spawn then
	spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(8, 0.2, 8)
	spawn.Position = Vector3.new(0, 0.1, 8)
	spawn.Color = Color3.fromRGB(53, 79, 112)
	spawn.Duration = 0
	spawn.Parent = lab
end

local targets: { Target } = {}
local byId: { [string]: Target } = {}
local byPart: { [Instance]: Target } = {}
local specs = {
	{ id = "near", z = -24, width = 13, period = 4.3, phase = 0.0, color = Color3.fromRGB(62, 230, 165) },
	{ id = "mid", z = -88, width = 19, period = 4.9, phase = 1.1, color = Color3.fromRGB(255, 190, 74) },
	{ id = "far", z = -153, width = 22, period = 5.6, phase = 2.3, color = Color3.fromRGB(198, 129, 255) },
}
for _, spec in specs do
	local base = Vector3.new(0, 3, spec.z)
	local existing = targetFolder:FindFirstChild(spec.id)
	local targetPart: Part
	if existing then
		-- A server script restart may retain its world folder. Reuse only an
		-- explicitly tagged lab target; duplicate spheres would block hitscan.
		assert(existing:IsA("Part") and existing:GetAttribute("AimLabTargetId") == spec.id, "Unowned part conflicts with target " .. spec.id)
		targetPart = existing :: Part
		targetPart.Size = Vector3.new(4, 4, 4)
		targetPart.Position = base
		targetPart.Color = spec.color
	else
		targetPart = part(spec.id, targetFolder, Vector3.new(4, 4, 4), base, spec.color)
	end
	targetPart.Shape = Enum.PartType.Ball
	targetPart.Material = Enum.Material.Neon
	targetPart.Anchored = true
	targetPart.CanCollide = false
	targetPart.CanTouch = false
	targetPart.CanQuery = true
	targetPart.CastShadow = false
	targetPart:SetAttribute("AimLabTargetId", spec.id)
	local target: Target = {
		id = spec.id, part = targetPart, base = base,
		width = spec.width, period = spec.period, phase = spec.phase, radius = 2,
	}
	table.insert(targets, target)
	byId[target.id] = target
	byPart[targetPart] = target
end

-- Piecewise analytic truth lets us measure delayed observations at their exact timestamp.
-- Running reverses abruptly at the zigzag endpoints; jumps have a real ballistic arc.
local function truth(target: Target, timestamp: number): (Vector3, Vector3, string)
	local elapsed = timestamp - epoch + target.phase
	local phase = (elapsed / target.period) % 1
	local x = target.width * (1 - 4 * math.abs(phase - 0.5))
	local vx = (if phase < 0.5 then 1 else -1) * 4 * target.width / target.period
	local z = 4 * math.sin(elapsed * 0.9)
	local vz = 3.6 * math.cos(elapsed * 0.9)
	local jumpTime = (elapsed % 3.4) - 1.8
	local height, vy, state = 0, 0, "running"
	if jumpTime >= 0 and jumpTime < 1.2 then
		height = 24 * jumpTime - 20 * jumpTime * jumpTime
		vy = 24 - 40 * jumpTime
		state = if vy > 0 then "jumping" else "falling"
	end
	return target.base + Vector3.new(x, height, z), Vector3.new(vx, vy, vz), state
end

local states: { [Player]: PlayerState } = {}
local projectiles: { Projectile } = {}
local connections: { RBXScriptConnection } = {}
local function finite(number: any): boolean
	-- Unix GetServerTimeNow timestamps already exceed 1e9; finite is not a range bound.
	return typeof(number) == "number" and number == number and math.abs(number) < math.huge
end
local function vector(value: any): boolean
	return typeof(value) == "Vector3" and finite(value.X) and finite(value.Y) and finite(value.Z)
end
local function shotIdValid(value: any): boolean
	return (typeof(value) == "string" and #value > 0 and #value <= 64)
		or (finite(value) and value >= 0 and value <= 1e12 and value % 1 == 0)
end
local function ping(player: Player): number
	-- Current Creator documentation calls GetNetworkPing() round-trip latency in
	-- seconds. Half RTT estimates one direction assuming symmetric paths; it is
	-- not a direct measurement of one-way latency or replication scheduling.
	local ok, value = pcall(function() return player:GetNetworkPing() end)
	return if ok and finite(value) then math.clamp(value * 0.5, 0, 1) else 0
end
local function send(player: Player, payload: any)
	if states[player] and player.Parent == Players then
		Telemetry:FireClient(player, payload)
	end
end
local function addPlayer(player: Player)
	states[player] = {
		nextFire = 0, lastRequest = -math.huge, lastObservation = -math.huge,
		lastSettings = -math.huge, simulationDelay = 0, projectileCount = 0,
		observations = {}, snapshots = {}, recentShotIds = {}, shotOrder = {},
	}
	player.RespawnLocation = spawn
end
for _, player in Players:GetPlayers() do addPlayer(player) end
table.insert(connections, Players.PlayerAdded:Connect(addPlayer))
table.insert(connections, Players.PlayerRemoving:Connect(function(player)
	states[player] = nil -- Releases pending observations and delayed snapshots.
	for i = #projectiles, 1, -1 do
		if projectiles[i].player == player then
			projectiles[i].visual:Destroy()
			table.remove(projectiles, i)
		end
	end
end))

local function measure(player: Player, observation: Observation)
	local target = byId[observation.id]
	if not target then return end
	local position, _, state = truth(target, observation.due)
	send(player, {
		type = "prediction", id = target.id,
		errorStuds = (position - observation.aimpoint).Magnitude,
		state = state, horizon = observation.horizon,
		sampleTime = observation.sampleTime, impactTime = observation.due, weapon = observation.weapon,
	})
end
table.insert(connections, Observe.OnServerEvent:Connect(function(player, payload: any)
	local state = states[player]
	local now = workspace:GetServerTimeNow()
	if not state or now - state.lastObservation < 0.09 or typeof(payload) ~= "table" then return end
	state.lastObservation = now
	if typeof(payload.id) ~= "string" or not byId[payload.id] or not vector(payload.aimpoint)
		or not finite(payload.horizon) or payload.horizon < 0 or payload.horizon > MAX_PREDICTION_HORIZON
		or not finite(payload.sampleTime) or payload.sampleTime < now - 2 or payload.sampleTime > now + 0.05
		or payload.aimpoint.Magnitude > 1000 or #state.observations >= MAX_PREDICTIONS then return end
	if payload.weapon ~= nil and (typeof(payload.weapon) ~= "string" or #payload.weapon > 40 or not Weapons.get(payload.weapon)) then return end
	local observation: Observation = {
		id = payload.id, aimpoint = payload.aimpoint, horizon = payload.horizon,
		sampleTime = payload.sampleTime, due = payload.sampleTime + payload.horizon,
		weapon = payload.weapon,
	}
	if observation.due <= now then measure(player, observation)
	else table.insert(state.observations, observation) end
end))
table.insert(connections, Settings.OnServerEvent:Connect(function(player, payload: any)
	local state = states[player]
	local now = workspace:GetServerTimeNow()
	if not state or now - state.lastSettings < 0.1 or typeof(payload) ~= "table" then return end
	state.lastSettings = now
	if finite(payload.simulationDelaySeconds) then
		state.simulationDelay = math.clamp(payload.simulationDelaySeconds, 0, MAX_DELAY)
		-- Clear old schedule so reducing the delay cannot deliver reordered snapshots.
		table.clear(state.snapshots)
	end
end))

local function parameters(player: Player, excludeTargets: boolean): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclusions: { Instance } = { projectileFolder, effectsFolder }
	if player.Character then table.insert(exclusions, player.Character) end
	if excludeTargets then table.insert(exclusions, targetFolder) end
	params.FilterDescendantsInstances = exclusions
	params.IgnoreWater = true
	return params
end
local function spread(direction: Vector3, radians: number): Vector3
	if radians <= 0 then return direction end
	local axis = if math.abs(direction.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	local right = direction:Cross(axis).Unit
	local up = right:Cross(direction).Unit
	-- Uniform solid-angle cone, using server-side randomness.
	local cosine = 1 - random:NextNumber() * (1 - math.cos(radians))
	local sine = math.sqrt(math.max(0, 1 - cosine * cosine))
	local angle = random:NextNumber(0, 2 * math.pi)
	return (direction * cosine + (right * math.cos(angle) + up * math.sin(angle)) * sine).Unit
end
local function trace(from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	if length < 0.01 then return end
	local line = part("ShotTrace", effectsFolder, Vector3.new(0.06, 0.06, length), (from + to) / 2, Color3.fromRGB(255, 242, 157))
	line.CFrame = CFrame.lookAt((from + to) / 2, to)
	line.Material = Enum.Material.Neon
	line.CanCollide = false
	line.CanQuery = false
	line.CanTouch = false
	Debris:AddItem(line, 0.1)
end
local function rejection(player: Player, payload: any, reason: string)
	send(player, { type = "shot", shotId = payload.shotId, accepted = false, hit = false, reason = reason })
end

table.insert(connections, Fire.OnServerEvent:Connect(function(player, payload: any)
	local state = states[player]
	local now = workspace:GetServerTimeNow()
	if not state or now - state.lastRequest < 0.02 or typeof(payload) ~= "table" or not shotIdValid(payload.shotId) then return end
	state.lastRequest = now
	if not vector(payload.origin) or not vector(payload.direction) or payload.direction.Magnitude < 0.5
		or payload.direction.Magnitude > 2 then rejection(player, payload, "invalid-direction"); return end
	if payload.aimpoint ~= nil and (not vector(payload.aimpoint) or payload.aimpoint.Magnitude > 1000) then
		rejection(player, payload, "invalid-aimpoint"); return
	end
	if typeof(payload.weapon) ~= "string" or #payload.weapon > 40 or typeof(payload.targetId) ~= "string" or not byId[payload.targetId] then
		rejection(player, payload, "invalid-target-or-weapon"); return
	end
	local profile = Weapons.get(payload.weapon)
	if not profile then rejection(player, payload, "unknown-weapon"); return end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0
		or (payload.origin - root.Position).Magnitude > MAX_ORIGIN_OFFSET then
		rejection(player, payload, "invalid-origin"); return
	end
	if now < state.nextFire then rejection(player, payload, "cooldown"); return end
	local key = typeof(payload.shotId) .. ":" .. tostring(payload.shotId)
	if state.recentShotIds[key] then rejection(player, payload, "duplicate-shot"); return end
	if profile.kind == "projectile" and (state.projectileCount >= MAX_PROJECTILES_PER_PLAYER or #projectiles >= MAX_PROJECTILES) then
		rejection(player, payload, "projectile-limit"); return
	end
	state.nextFire = now + profile.cooldown
	state.recentShotIds[key] = true
	table.insert(state.shotOrder, key)
	if #state.shotOrder > 64 then state.recentShotIds[table.remove(state.shotOrder, 1)] = nil end
	local direction = spread(payload.direction.Unit, profile.spreadRadians)
	local target = byId[payload.targetId]
	if profile.kind == "hitscan" then
		for _, movingTarget in targets do movingTarget.part.Position = truth(movingTarget, now) end
		local ray = workspace:Raycast(payload.origin, direction * MAX_RANGE, parameters(player, false))
		local endpoint = if ray then ray.Position else payload.origin + direction * MAX_RANGE
		local hitTarget = if ray then byPart[ray.Instance] else nil
		local targetPosition, _, movement = truth(target, now)
		local _, closest = closestOnSegment(targetPosition, payload.origin, endpoint)
		trace(payload.origin, endpoint)
		send(player, {
			type = "shot", shotId = payload.shotId, accepted = true,
			hit = hitTarget ~= nil, targetId = target.id, hitTargetId = if hitTarget then hitTarget.id else nil,
			intendedHit = hitTarget ~= nil and hitTarget.id == target.id,
			weapon = payload.weapon, flightSeconds = 0, spreadRadians = profile.spreadRadians,
			state = movement, distance = (targetPosition - payload.origin).Magnitude,
			pingSeconds = ping(player), reason = if hitTarget then "hit" elseif ray then "obstacle" else "miss",
			missDistanceStuds = math.max(0, (targetPosition - closest).Magnitude - target.radius),
			impactPosition = endpoint,
		})
	else
		local visual = part("Projectile", projectileFolder, Vector3.new(0.35, 0.35, 0.35), payload.origin, Color3.fromRGB(255, 217, 86))
		visual.Shape = Enum.PartType.Ball
		visual.Material = Enum.Material.Neon
		visual.CanCollide = false
		visual.CanQuery = false
		visual.CanTouch = false
		state.projectileCount += 1
		table.insert(projectiles, {
			player = player, shotId = payload.shotId, weapon = payload.weapon, targetId = target.id,
			origin = payload.origin, velocity = direction * profile.speed, gravity = profile.gravity,
			radius = profile.radius, spreadRadians = profile.spreadRadians,
			started = now, processed = now, lifetime = math.min(4, MAX_RANGE / profile.speed),
			visual = visual, params = parameters(player, true),
			closestDistance = math.huge, closestTime = now, closestPosition = payload.origin,
		})
	end
end))

local function projectilePosition(projectile: Projectile, timestamp: number): Vector3
	local elapsed = timestamp - projectile.started
	return projectile.origin + projectile.velocity * elapsed + Vector3.new(0, -0.5 * projectile.gravity * elapsed * elapsed, 0)
end

local function finish(projectile: Projectile, hitTarget: Target?, reason: string, timestamp: number, impactPosition: Vector3)
	local target = byId[projectile.targetId]
	local targetPosition, _, movement = truth(target, timestamp)
	-- For misses this is closest clearance along the actually simulated flight,
	-- not prediction error: spread, obstruction and flight termination also contribute.
	send(projectile.player, {
		type = "shot", shotId = projectile.shotId, accepted = true, hit = hitTarget ~= nil,
		targetId = target.id, hitTargetId = if hitTarget then hitTarget.id else nil,
		intendedHit = hitTarget ~= nil and hitTarget.id == target.id,
		weapon = projectile.weapon, flightSeconds = timestamp - projectile.started,
		spreadRadians = projectile.spreadRadians, state = movement,
		distance = (targetPosition - projectile.origin).Magnitude, pingSeconds = ping(projectile.player),
		reason = reason, impactPosition = impactPosition,
		missDistanceStuds = if hitTarget and hitTarget.id == target.id then 0 else projectile.closestDistance,
		closestApproachTime = projectile.closestTime,
	})
	projectile.visual:Destroy()
	local state = states[projectile.player]
	if state then state.projectileCount = math.max(0, state.projectileCount - 1) end
end

local function advance(projectile: Projectile, now: number): boolean
	local endTime = math.min(now, projectile.started + projectile.lifetime)
	-- Bounded catch-up avoids an unbounded loop after a stalled frame. No elapsed
	-- flight is skipped: remaining time is processed on subsequent Heartbeats.
	local steps = 0
	while projectile.processed < endTime and steps < 64 do
		steps += 1
		local fromTime = projectile.processed
		local toTime = math.min(fromTime + MAX_SUBSTEP, endTime)
		local from = projectilePosition(projectile, fromTime)
		local to = projectilePosition(projectile, toTime)
		local intended = byId[projectile.targetId]
		local intendedStart = truth(intended, fromTime)
		local intendedEnd = truth(intended, toTime)
		local relativeStart, relativeEnd = from - intendedStart, to - intendedEnd
		local fraction, relativeClosest = closestOnSegment(Vector3.zero, relativeStart, relativeEnd)
		local clearance = math.max(0, relativeClosest.Magnitude - intended.radius - projectile.radius)
		local earliest, hitTarget = 1.1, nil :: Target?
		-- Geometry.sphereIntersection tests finite relative-motion segments.
		-- Target motion is linearized only within <=1/120 s substeps.
		for _, target in targets do
			local targetStart = truth(target, fromTime)
			local targetEnd = truth(target, toTime)
			local contact = sphereIntersection(from - targetStart, to - targetEnd, target.radius + projectile.radius)
			if contact and contact < earliest then earliest, hitTarget = contact, target end
		end
		local delta = to - from
		local obstacle = if delta.Magnitude > 1e-9 then
			(if projectile.radius > 0 then workspace:Spherecast(from, projectile.radius, delta, projectile.params)
			else workspace:Raycast(from, delta, projectile.params)) else nil
		local obstacleFraction = if obstacle then obstacle.Distance / delta.Magnitude else 1.1
		local stopFraction = math.min(1, earliest, obstacleFraction)
		-- Do not count closest approach beyond a wall or a different target.
		if fraction > stopFraction then
			fraction = stopFraction
			clearance = math.max(0, relativeStart:Lerp(relativeEnd, fraction).Magnitude - intended.radius - projectile.radius)
		end
		if clearance < projectile.closestDistance then
			projectile.closestDistance = clearance
			projectile.closestTime = fromTime + (toTime - fromTime) * fraction
			projectile.closestPosition = from:Lerp(to, fraction)
		end
		if obstacle and obstacleFraction <= earliest then
			local impactTime = fromTime + (toTime - fromTime) * math.clamp(obstacleFraction, 0, 1)
			finish(projectile, nil, "obstacle", impactTime, obstacle.Position)
			return true
		elseif hitTarget then
			local impactTime = fromTime + (toTime - fromTime) * earliest
			finish(projectile, hitTarget, "hit", impactTime, from:Lerp(to, earliest))
			return true
		end
		projectile.processed = toTime
		projectile.visual.Position = to
	end
	if projectile.processed >= projectile.started + projectile.lifetime then
		finish(projectile, nil, "expired", projectile.processed, projectile.visual.Position)
		return true
	end
	return false
end

local nextSnapshot = epoch
table.insert(connections, RunService.Heartbeat:Connect(function()
	local now = workspace:GetServerTimeNow()
	for _, target in targets do
		local position, _, movement = truth(target, now)
		target.part.Position = position
		target.part:SetAttribute("MovementState", movement)
	end
	for i = #projectiles, 1, -1 do
		if advance(projectiles[i], now) then table.remove(projectiles, i) end
	end
	for player, state in states do
		for i = #state.observations, 1, -1 do
			if state.observations[i].due <= now then
				measure(player, state.observations[i])
				table.remove(state.observations, i)
			end
		end
		while #state.snapshots > 0 and state.snapshots[1].due <= now do
			Snapshot:FireClient(player, table.remove(state.snapshots, 1).payload)
		end
	end
	if now + 1e-4 < nextSnapshot then return end
	nextSnapshot = if now - nextSnapshot > SNAPSHOT_INTERVAL then now + SNAPSHOT_INTERVAL else nextSnapshot + SNAPSHOT_INTERVAL
	local samples = {}
	for _, target in targets do
		local position, velocity, movement = truth(target, now)
		table.insert(samples, { id = target.id, position = position, velocity = velocity, state = movement, radius = target.radius })
	end
	for player, state in states do
		local oneWay = ping(player)
		local payload = { t = now, targets = samples, pingSeconds = oneWay, pingRoundTripSeconds = oneWay * 2 }
		if state.simulationDelay <= 0 then Snapshot:FireClient(player, payload)
		else
			if #state.snapshots >= 8 then table.remove(state.snapshots, 1) end
			table.insert(state.snapshots, { due = now + state.simulationDelay, payload = payload })
		end
	end
end))

script.Destroying:Connect(function()
	for _, connection in connections do connection:Disconnect() end
	for _, projectile in projectiles do projectile.visual:Destroy() end
	table.clear(projectiles)
	table.clear(states)
end)

--!nonstrict
-- OPTIONAL OWNED STUDIO EXPERIENCE ONLY. Independent server-time hitscan probe;
-- this does not reproduce, hook, or claim integration with Da Hood weapons.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local MAX_RANGE, COOLDOWN, MAX_SAMPLE_AGE = 400, 0.35, 0.6
local allowedParts = {}
for _, name in {
	"HumanoidRootPart", "Head", "Torso", "UpperTorso", "LowerTorso",
	"Left Arm", "Right Arm", "Left Leg", "Right Leg",
	"LeftHand", "RightHand", "LeftFoot", "RightFoot",
	"LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm",
	"LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg",
} do allowedParts[name] = true end

local folder = ReplicatedStorage:FindFirstChild("PinkDotLockProbe")
if folder then
	assert(folder:IsA("Folder") and folder:GetAttribute("OwnedStudioProbe") == true, "Unowned probe name conflict")
else
	folder = Instance.new("Folder")
	folder.Name = "PinkDotLockProbe"
	folder:SetAttribute("OwnedStudioProbe", true)
	folder.Parent = ReplicatedStorage
end
local function remote(name)
	local event = folder:FindFirstChild(name)
	if event then assert(event:IsA("RemoteEvent"), "Probe remote conflict"); return event end
	event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = folder
	return event
end
local Fire, Reference = remote("Fire"), remote("Reference")
local states, connections = {}, {}
local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function vector(value)
	return typeof(value) == "Vector3" and finite(value.X) and finite(value.Y) and finite(value.Z)
end
local function reject(player, request, reason)
	Reference:FireClient(player, { sessionId = request.sessionId, ticketId = request.ticketId,
		accepted = false, reason = reason })
end
table.insert(connections, Fire.OnServerEvent:Connect(function(player, request)
	if type(request) ~= "table" or type(request.sessionId) ~= "string" or #request.sessionId > 64
		or not finite(request.ticketId) or request.ticketId < 1 or request.ticketId > 1e12 or request.ticketId % 1 ~= 0 then return end
	local now = Workspace:GetServerTimeNow()
	local state = states[player]
	if not state then state = { lastRequest = -math.huge, nextFire = 0, seen = {}, order = {} }; states[player] = state end
	if now - state.lastRequest < 0.02 then return end
	state.lastRequest = now
	if not finite(request.targetUserId) or request.targetUserId % 1 ~= 0 or request.targetUserId == player.UserId
		or not allowedParts[request.partName] then reject(player, request, "invalid-target"); return end
	if not finite(request.capturedAt) or request.capturedAt > now + 0.05 or now - request.capturedAt > MAX_SAMPLE_AGE
		or not finite(request.sampleTime) or request.sampleTime > now + 0.05 or now - request.sampleTime > MAX_SAMPLE_AGE then
		reject(player, request, "stale-request"); return
	end
	if not vector(request.origin) or not vector(request.direction) or request.direction.Magnitude < 0.5
		or request.direction.Magnitude > 2 or not vector(request.aimpoint)
		or not vector(request.manualPosition) or not vector(request.autoPosition) then
		reject(player, request, "invalid-vectors"); return
	end
	local character = player.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not head or not head:IsA("BasePart") or not humanoid or humanoid.Health <= 0
		or (request.origin - head.Position).Magnitude > 3 then reject(player, request, "invalid-origin"); return end
	local target = Players:GetPlayerByUserId(request.targetUserId)
	local targetCharacter = target and target.Character
	local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
	local targetPart = targetCharacter and targetCharacter:FindFirstChild(request.partName)
	if not targetPart or not targetPart:IsA("BasePart") or not targetHumanoid or targetHumanoid.Health <= 0
		or request.targetCharacter ~= targetCharacter then reject(player, request, "target-lost"); return end
	if (targetPart.Position - request.origin).Magnitude > MAX_RANGE
		or (request.aimpoint - request.origin).Magnitude > MAX_RANGE + 100
		or (request.manualPosition - request.origin).Magnitude > MAX_RANGE + 100
		or (request.autoPosition - request.origin).Magnitude > MAX_RANGE + 100 then
		reject(player, request, "out-of-range"); return
	end
	if now < state.nextFire then reject(player, request, "cooldown"); return end
	local key = request.sessionId .. ":" .. tostring(request.ticketId)
	if state.seen[key] then reject(player, request, "duplicate-ticket"); return end
	state.nextFire = now + COOLDOWN
	state.seen[key] = true
	table.insert(state.order, key)
	if #state.order > 120 then state.seen[table.remove(state.order, 1)] = nil end
	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = { character }
	local result = Workspace:Raycast(request.origin, request.direction.Unit * MAX_RANGE, parameters)
	local hit = result ~= nil and result.Instance:IsDescendantOf(targetCharacter)
	-- Timestamp and position are measured HERE, independently of all prediction
	-- delays/horizons. The provided predicted positions never decide actual hits.
	local referenceTime=Workspace:GetServerTimeNow()
	local actualPosition=targetPart.Position
	Reference:FireClient(player, {
		sessionId = request.sessionId, ticketId = request.ticketId, targetUserId = target.UserId,
		character = targetCharacter, actualPosition = actualPosition,
		referenceTime = referenceTime, accepted = true, hit = hit,
		impactPosition = if result then result.Position else request.origin + request.direction.Unit * MAX_RANGE,
		reason = if hit then "owned-studio-hit" elseif result then "obstructed-or-other-part" else "miss",
	})
end))
table.insert(connections, Players.PlayerRemoving:Connect(function(player) states[player] = nil end))
script.Destroying:Connect(function()
	for _, connection in connections do connection:Disconnect() end
	table.clear(states)
end)

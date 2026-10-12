--!nonstrict
-- OWNED STUDIO EXPERIENCE ONLY. This script creates and validates its own Tool
-- and remotes; it never connects to Da Hood weapons or protected communications.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	print("[SEDWARE Weapon] SKIPPED: this owned weapon demonstration requires Roblox Studio")
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local modules = ReplicatedStorage:WaitForChild("SEDWAREWeaponModules", 10)
assert(modules and modules:IsA("Folder"), "[SEDWARE Weapon] owned weapon module folder missing or invalid")
local function loadRequired(name)
	local source = modules:WaitForChild(name, 10)
	assert(source and source:IsA("ModuleScript"), "[SEDWARE Weapon] required module missing or invalid: " .. name)
	local ok, value = pcall(require, source)
	assert(ok and type(value) == "table", "[SEDWARE Weapon] module failed: " .. name .. ": " .. tostring(value))
	return value
end
local WeaponSettings = loadRequired("WeaponSettings")
local ServerController = loadRequired("ServerController")
local settings = WeaponSettings.new()

local previous = ReplicatedStorage:FindFirstChild("SEDWAREWeaponRemotes")
assert(not previous or previous:IsA("Folder") and previous:GetAttribute("OwnedSEDWAREWeapon") == true,
	"SEDWARE owned weapon remote name conflict")
if previous then
	local stop = previous:FindFirstChild("StopOwner")
	assert(stop and stop:IsA("BindableEvent"), "SEDWARE prior weapon owner cannot be stopped safely")
	stop:Fire()
	assert(previous.Parent == nil, "SEDWARE prior weapon owner did not clean up")
end
local folder = Instance.new("Folder")
folder.Name = "SEDWAREWeaponRemotes"
folder:SetAttribute("OwnedSEDWAREWeapon", true)
local Fire = Instance.new("RemoteEvent")
Fire.Name = "Fire"; Fire.Parent = folder
local Result = Instance.new("RemoteEvent")
Result.Name = "Result"; Result.Parent = folder
local StopOwner = Instance.new("BindableEvent")
StopOwner.Name = "StopOwner"; StopOwner.Parent = folder

-- A real equipped Tool produces the origin used by the server raycast.
local template = Instance.new("Tool")
template.Name = settings.WeaponName
template.RequiresHandle = true
template.CanBeDropped = false
template.ToolTip = "SEDWARE owned Studio test weapon: C locks; click fires"
template:SetAttribute("OwnedSEDWAREWeapon", true)
local handle = Instance.new("Part")
handle.Name = "Handle"
handle.Size = Vector3.new(0.45, 0.6, 1.8)
handle.Color = Color3.fromRGB(255, 105, 180)
handle.Material = Enum.Material.Metal
handle.CanCollide = false
handle.Massless = true
handle.Parent = template
local muzzle = Instance.new("Attachment")
muzzle.Name = "Muzzle"
muzzle.Position = Vector3.new(0, 0, -0.9)
muzzle.Parent = handle

local connections, playerConnections, playerTools = {}, {}, {}
local destroyed = false
local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function vector(value)
	return typeof(value) == "Vector3" and finite(value.X) and finite(value.Y) and finite(value.Z)
end
local controller = ServerController.new({
	clock = function() return Workspace:GetServerTimeNow() end,
	isVector = vector,
	getEquippedWeapon = function(player)
		local character, tool = player.Character, playerTools[player]
		if not character or not character:IsDescendantOf(Workspace) or not tool or tool.Parent ~= character
			or tool.Name ~= settings.WeaponName or tool:GetAttribute("OwnedSEDWAREWeapon") ~= true then return nil end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
		local part = tool:FindFirstChild("Handle")
		local attachment = part and part:FindFirstChild("Muzzle")
		if not humanoid or humanoid.Health <= 0 or not head or not head:IsA("BasePart")
			or not part or not part:IsA("BasePart") or not attachment or not attachment:IsA("Attachment") then return nil end
		local from = attachment.WorldPosition
		if not vector(from) or (from - head.Position).Magnitude > 8 then return nil end
		return { tool = tool, character = character, humanoid = humanoid, origin = from }
	end,
	getTarget = function(userId, partName, expectedCharacter)
		local player = Players:GetPlayerByUserId(userId)
		local character = player and player.Character
		if not character or character ~= expectedCharacter or not character:IsDescendantOf(Workspace) then return nil end
		local humanoid, part = character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild(partName)
		if not humanoid or humanoid.Health <= 0 or not part or not part:IsA("BasePart") then return nil end
		return { player = player, character = character, humanoid = humanoid, part = part, position = part.Position }
	end,
	raycast = function(from, direction, ignoreCharacter)
		local parameters = RaycastParams.new()
		parameters.FilterType = Enum.RaycastFilterType.Exclude
		parameters.FilterDescendantsInstances = { ignoreCharacter }
		return Workspace:Raycast(from, direction, parameters)
	end,
	describeHit = function(result)
		local model, humanoid = result.Instance:FindFirstAncestorOfClass("Model"), nil
		while model do
			humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then break end
			model = model:FindFirstAncestorOfClass("Model")
		end
		local targetPlayer = model and Players:GetPlayerFromCharacter(model)
		return { name = result.Instance:GetFullName(), position = result.Position,
			character = model, humanoid = humanoid, playerUserId = targetPlayer and targetPlayer.UserId }
	end,
	applyDamage = function(humanoid, amount)
		local before = humanoid.Health
		humanoid:TakeDamage(amount)
		return { before = before, after = humanoid.Health }
	end,
})

local function clearPlayer(player)
	local binding = playerConnections[player]
	if binding then binding:Disconnect(); playerConnections[player] = nil end
	local tool = playerTools[player]
	if tool then tool:Destroy(); playerTools[player] = nil end
	controller:removePlayer(player)
end
local function grant(player, character)
	if destroyed or player.Parent ~= Players or player.Character ~= character then return end
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if destroyed or player.Parent ~= Players or player.Character ~= character or not backpack then return end
	local prior = playerTools[player]
	if prior then prior:Destroy() end
	-- Do not modify a foreign Tool using the same name.
	if backpack:FindFirstChild(settings.WeaponName) or character:FindFirstChild(settings.WeaponName) then
		warn("[SEDWARE Weapon] Tool name conflict for " .. player.Name); playerTools[player] = nil; return
	end
	local tool = template:Clone()
	playerTools[player] = tool
	tool.Parent = backpack
end
local function attachPlayer(player)
	if playerConnections[player] then return end
	playerConnections[player] = player.CharacterAdded:Connect(function(character) grant(player, character) end)
	if player.Character then task.defer(grant, player, player.Character) end
end
local function cleanup()
	if destroyed then return end
	destroyed = true
	for _, binding in connections do binding:Disconnect() end
	table.clear(connections)
	for player in playerConnections do clearPlayer(player) end
	for player in playerTools do clearPlayer(player) end
	controller:destroy()
	template:Destroy()
	folder:Destroy()
end
table.insert(connections, StopOwner.Event:Connect(cleanup))
table.insert(connections, Fire.OnServerEvent:Connect(function(player, request)
	if destroyed then return end
	local result = controller:process(player, request)
	if result.reason == "server-error" then warn("[SEDWARE Weapon] " .. tostring(result.error)) end
	-- Malformed packets without an attributable ID are discarded; valid packets
	-- always receive an explicit accepted/rejected result.
	if result.sessionId and result.shotId then Result:FireClient(player, result) end
end))
table.insert(connections, Players.PlayerAdded:Connect(attachPlayer))
table.insert(connections, Players.PlayerRemoving:Connect(clearPlayer))
table.insert(connections, script.Destroying:Connect(cleanup))
folder.Parent = ReplicatedStorage
for _, player in Players:GetPlayers() do attachPlayer(player) end
print("[SEDWARE Weapon] OWN Studio server ready: real equipped Tool, authoritative raycast and measured damage")

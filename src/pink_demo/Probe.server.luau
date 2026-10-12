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
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
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
local WeaponProfiles = loadRequired("WeaponProfiles")
local ProjectileTracker = loadRequired("ProjectileTracker")
local settings = WeaponSettings.new()
local profiles = WeaponProfiles.defaults()

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
local Verification = Instance.new("RemoteFunction")
Verification.Name = "Verification"; Verification.Parent = folder
assert(not Workspace:FindFirstChild("SEDWAREWeaponPhysics"),"SEDWARE physics namespace conflict")
local physicsFolder=Instance.new("Folder")
physicsFolder.Name="SEDWAREWeaponPhysics";physicsFolder.Parent=Workspace

-- A real equipped Tool produces the origin used by the server raycast.
local templates={}
for id,profile in profiles do
local template = Instance.new("Tool")
template.Name = profile.Name
template.RequiresHandle = true
template.CanBeDropped = false
template.ToolTip = "SEDWARE owned Studio test weapon: C locks; click fires"
template:SetAttribute("OwnedSEDWAREWeapon", true)
template:SetAttribute("SEDWAREProfileId",id)
local handle = Instance.new("Part")
handle.Name = "Handle"
handle.Size = Vector3.new(0.45, 0.6, 1.8)
handle.Color = Color3.fromRGB(255, 105, 180)
handle.Material = Enum.Material.Metal
handle.CanCollide = false
handle.CanTouch = false
handle.CanQuery = false
handle.Massless = true
handle.Parent = template
local muzzle = Instance.new("Attachment")
muzzle.Name = "Muzzle"
muzzle.Position = Vector3.new(0, 0, -0.9)
muzzle.Parent = handle
templates[id]=template
end

local connections, playerConnections, playerTools = {}, {}, {}
local trackers,verificationRuns={},{}
local destroyed = false
local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function vector(value)
	return typeof(value) == "Vector3" and finite(value.X) and finite(value.Y) and finite(value.Z)
end
local function query(from,direction,ignoreCharacter)
	local parameters=RaycastParams.new()
	parameters.FilterType=Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances={ignoreCharacter,physicsFolder}
	return Workspace:Raycast(from,direction,parameters)
end
local function trace(from,to)
	local distance=(to-from).Magnitude
	if distance<0.001 then return end
	local part=Instance.new("Part")
	part.Name="AuthoritativeRayTrace";part.Anchored=true;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false
	part.Material=Enum.Material.Neon;part.Color=Color3.fromRGB(255,105,180)
	part.Size=Vector3.new(0.035,0.035,distance)
	part.CFrame=CFrame.lookAt((from+to)/2,to);part.Parent=physicsFolder
	Debris:AddItem(part,0.1)
end
local function deliver(player,result)
	if destroyed or player.Parent~=Players then return end
	result.engine="RobloxWorkspace"
	if result.error then warn("[SEDWARE Weapon] "..tostring(result.error)) end
	if result.sessionId and result.shotId then
		print("[SEDWARE Weapon][RESULT] "..HttpService:JSONEncode({shotId=result.shotId,weaponId=result.weaponId,
			mode=result.mode,pending=result.pending==true,accepted=result.accepted,hit=result.hit,
			selectedTargetHit=result.selectedTargetHit,damageApplied=result.damageApplied,
			pelletCount=result.pelletCount,pelletHits=result.pelletHits,reason=result.reason,
			physicsKind=result.physicsKind,referenceTime=result.referenceTime,engine=result.engine}))
		Result:FireClient(player,result)
	end
end
local random=Random.new()
local controller = ServerController.new({
	profiles=profiles,
	settings={MaxProjectiles=settings.MaxProjectiles,MaxProjectilesPerPlayer=settings.MaxProjectilesPerPlayer},
	random=function() return random:NextNumber() end,
	makeVector=Vector3.new,
	onResult=deliver,
	clock = function() return Workspace:GetServerTimeNow() end,
	isVector = vector,
	getEquippedWeapon = function(player)
		local character, tool,profileId = player.Character,nil,nil
		for id,candidate in playerTools[player] or {} do
			if candidate.Parent==character then tool=candidate;profileId=id;break end
		end
		if not character or not character:IsDescendantOf(Workspace) or not tool or tool.Parent ~= character
			or tool.Name ~= profiles[profileId].Name or tool:GetAttribute("OwnedSEDWAREWeapon") ~= true
			or tool:GetAttribute("SEDWAREProfileId")~=profileId then return nil end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
		local part = tool:FindFirstChild("Handle")
		local attachment = part and part:FindFirstChild("Muzzle")
		if not humanoid or humanoid.Health <= 0 or not head or not head:IsA("BasePart")
			or not part or not part:IsA("BasePart") or not attachment or not attachment:IsA("Attachment") then return nil end
		local from = attachment.WorldPosition
		if not vector(from) or (from - head.Position).Magnitude > 8 then return nil end
		return { tool = tool, profileId=profileId, character = character, humanoid = humanoid, origin = from }
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
		local result=query(from,direction,ignoreCharacter)
		trace(from,if result then result.Position else from+direction)
		return result
	end,
	launchProjectile=function(from,velocity,profile,ignoreCharacter,complete)
		local part=Instance.new("Part")
		local tracker
		local ok,problem=xpcall(function()
			part.Name="PhysicalProjectile";part.Shape=Enum.PartType.Ball;part.Size=Vector3.new(0.25,0.25,0.25)
			part.Color=Color3.fromRGB(255,105,180);part.Material=Enum.Material.Neon
			part.Anchored=false;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false
			part.Position=from;part.Parent=physicsFolder
			part:SetNetworkOwner(nil)
			local attachment=Instance.new("Attachment");attachment.Parent=part
			local force=Instance.new("VectorForce")
			force.Attachment0=attachment;force.RelativeTo=Enum.ActuatorRelativeTo.World;force.ApplyAtCenterOfMass=true
			force.Force=Vector3.new(0,(Workspace.Gravity-profile.Gravity)*part.AssemblyMass,0);force.Parent=part
			part.AssemblyLinearVelocity=velocity
			tracker=ProjectileTracker.new({origin=from,range=profile.Range,lifetime=profile.Lifetime,
				clock=function() return Workspace:GetServerTimeNow() end,
				getPosition=function()
					if not part.Parent then return nil end
					force.Force=Vector3.new(0,(Workspace.Gravity-profile.Gravity)*part.AssemblyMass,0)
					return part.Position
				end,
				raycast=function(origin,direction) return query(origin,direction,ignoreCharacter) end,
				onComplete=complete,
				dispose=function() if tracker then trackers[tracker]=nil end;part:Destroy() end})
			trackers[tracker]=true
		end,debug.traceback)
		if not ok then part:Destroy();error(problem) end
		return function() tracker:cancel() end
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

local function restoreRun(player)
	local run=verificationRuns[player]
	if not run then return end
	verificationRuns[player]=nil
	local restored,problem=pcall(function() run.humanoid.MaxHealth=run.maxHealth;run.humanoid.Health=run.health end)
	if not restored then warn("[SEDWARE Native] health restore failed: "..tostring(problem)) end
end
local function clearPlayer(player)
	for owner,run in verificationRuns do if owner==player or run.target==player then restoreRun(owner) end end
	local binding = playerConnections[player]
	if binding then binding:Disconnect(); playerConnections[player] = nil end
	for _,tool in playerTools[player] or {} do tool:Destroy() end
	playerTools[player]=nil
	controller:removePlayer(player)
end
local function grant(player, character)
	if destroyed or player.Parent ~= Players or player.Character ~= character then return end
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if destroyed or player.Parent ~= Players or player.Character ~= character or not backpack then return end
	local prior = playerTools[player]
	if prior then for _,tool in prior do tool:Destroy() end end
	playerTools[player]={}
	-- Do not modify a foreign Tool using the same name.
	for id,template in templates do
		if backpack:FindFirstChild(template.Name) or character:FindFirstChild(template.Name) then
			warn("[SEDWARE Weapon] Tool name conflict: "..template.Name.." for "..player.Name)
		else
			local tool=template:Clone();playerTools[player][id]=tool;tool.Parent=backpack
		end
	end
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
	for tracker in trackers do tracker:cancel() end
	for _,template in templates do template:Destroy() end
	for player in verificationRuns do restoreRun(player) end
	Verification.OnServerInvoke=nil
	physicsFolder:Destroy()
	folder:Destroy()
end
table.insert(connections, StopOwner.Event:Connect(cleanup))
table.insert(connections, Fire.OnServerEvent:Connect(function(player, request)
	if destroyed then return end
	-- Malformed packets without an attributable ID are discarded; valid packets
	-- always receive an explicit accepted/rejected result.
	deliver(player,controller:process(player,request))
end))
table.insert(connections,RunService.Heartbeat:Connect(function()
	local now=Workspace:GetServerTimeNow()
	for player,run in verificationRuns do
		if now>=run.deadline or not run.humanoid.Parent then restoreRun(player) end
	end
	for tracker in trackers do
		local ok,problem=pcall(function() tracker:step(Workspace:GetServerTimeNow()) end)
		if not ok then warn("[SEDWARE Weapon] projectile tracker: "..tostring(problem));tracker:cancel();trackers[tracker]=nil end
	end
end))
-- Optional F6 native verification uses these OWN Studio-only controls. Raising
-- health is test setup; every damage delta is still measured after TakeDamage.
Verification.OnServerInvoke=function(player,action,targetId,runId)
	if destroyed or player.Parent~=Players then return {ok=false,reason="server-unavailable"} end
	if action=="End" then
		local run=verificationRuns[player]
		if not run or run.id~=runId then return {ok=false,reason="unknown-native-run"} end
		restoreRun(player)
		return {ok=true}
	end
	if action~="Begin" then return {ok=false,reason="invalid-native-test-action"} end
	for _ in verificationRuns do return {ok=false,reason="native-run-already-active"} end
	local target=if finite(targetId) and targetId%1==0 then Players:GetPlayerByUserId(targetId) else nil
	local character=target and target.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	local root=character and character:FindFirstChild("HumanoidRootPart")
	local ownRoot=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not target or target==player or not humanoid or humanoid.Health<=0 or not root or not ownRoot
		or (root.Position-ownRoot.Position).Magnitude>40 then return {ok=false,reason="native-test-requires-two-live-players-within-40-studs"} end
	local run={id=HttpService:GenerateGUID(false),humanoid=humanoid,target=target,maxHealth=humanoid.MaxHealth,
		health=humanoid.Health,deadline=Workspace:GetServerTimeNow()+90}
	verificationRuns[player]=run
	humanoid.MaxHealth=10000;humanoid.Health=10000
	print("[SEDWARE Native] Started "..run.id.."; target health temporarily 10000, restored after test. Hits remain native collision results.")
	return {ok=true,runId=run.id,engine="RobloxWorkspace"}
end
table.insert(connections, Players.PlayerAdded:Connect(attachPlayer))
table.insert(connections, Players.PlayerRemoving:Connect(clearPlayer))
table.insert(connections, script.Destroying:Connect(cleanup))
folder.Parent = ReplicatedStorage
for _, player in Players:GetPlayers() do attachPlayer(player) end
print("[SEDWARE Weapon] OWN Studio controllers ready: six Tool templates, server spread and physical projectile launcher. Each shot still requires equipped-Tool validation and an actual collision result.")

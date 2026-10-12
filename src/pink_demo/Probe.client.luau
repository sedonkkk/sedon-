--!nonstrict
-- OPTIONAL OWNED STUDIO EXPERIENCE ONLY. Use Studio Start Server + two clients.
-- C locks another player through PinkDotLock; F submits this OWN test hitscan.
-- No camera writes and no protected/game-specific remotes are used.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService") -- GenerateGUID only, no HTTP access.
local player = Players.LocalPlayer
local bundle = ReplicatedStorage:WaitForChild("PinkDotLock", 10)
if not bundle or not bundle:IsA("ModuleScript") then warn("PINK DOT LOCK probe: bundle missing"); return end
local ok, api = pcall(require, bundle)
if not ok or type(api) ~= "table" or not api.session then warn("PINK DOT LOCK probe: initialization failed"); return end
local folder = ReplicatedStorage:WaitForChild("PinkDotLockProbe", 10)
if not folder then warn("PINK DOT LOCK probe: install the paired server script"); return end
local Fire, Reference = folder:WaitForChild("Fire", 10), folder:WaitForChild("Reference", 10)
if not Fire or not Reference then warn("PINK DOT LOCK probe: owned remotes missing"); return end
local sessionId = HttpService:GenerateGUID(false)
local connections, destroyed = {}, false
local function origin()
	local character = player.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	return head and head:IsA("BasePart") and head.Position or nil
end
local adapter = api.session:CreateShotAdapter(function(ticket)
	local from = origin()
	assert(from, "Local character origin unavailable")
	local delta = ticket.aimpointActive - from
	assert(delta.Magnitude > 0.001, "Degenerate aimpoint")
	Fire:FireServer({
		sessionId = sessionId, ticketId = ticket.id, targetUserId = ticket.targetUserId,
		targetCharacter = ticket.character, partName = api.session.config.TargetPart,
		capturedAt = ticket.capturedAt, sampleTime = ticket.sampleTime,
		origin = from, direction = delta.Unit, aimpoint = ticket.aimpointActive,
		manualPosition = ticket.manual.targetPosition or ticket.manual.position,
		autoPosition = ticket.auto.targetPosition or ticket.auto.position,
	})
end)
if not adapter then warn("PINK DOT LOCK probe: adapter unavailable"); return end
table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
	if destroyed or processed or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.F then
		local ticket, err = adapter:fire()
		if not ticket then warn("PINK DOT LOCK probe: " .. tostring(err)) end
	end
end))
table.insert(connections, Reference.OnClientEvent:Connect(function(reference)
	if destroyed or type(reference) ~= "table" or reference.sessionId ~= sessionId then return end
	if reference.accepted ~= true then
		warn("PINK DOT LOCK own Studio shot rejected: " .. tostring(reference.reason)); return
	end
	local record, err = adapter:record(reference.ticketId, reference)
	if not record then warn("PINK DOT LOCK measurement rejected: " .. tostring(err)); return end
	print(string.format("PINK DOT LOCK owned Studio probe: active %.3f | manual %.3f | auto %.3f studs | selected-target hit %s",
		record.active.errorStuds, record.manual.errorStuds, record.auto.errorStuds, tostring(reference.hit)))
end))
local function cleanup()
	if destroyed then return end
	destroyed = true
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)
	adapter:destroy()
end
table.insert(connections,script.Destroying:Connect(cleanup))
table.insert(connections,api.session.overlay.gui.Destroying:Connect(cleanup))
print("PINK DOT LOCK owned Studio probe ready: C locks another player; F fires the test hitscan.")

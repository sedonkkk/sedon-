--!nonstrict
-- ONLY embedded in SedwareCamV32Test.rbxlx, an owned native regression place.
-- This intentionally changes the test player's WalkSpeed from the SERVER so
-- the client can distinguish a real correction from a client-only override.
-- It is never included in SedwareCamLock.lua or the production MovementServer.
local players=game:GetService("Players")
local storage=game:GetService("ReplicatedStorage")
local run=game:GetService("RunService")
assert(run:IsStudio() or workspace:GetAttribute("SEDWAREV32OwnedTestFixture")==true,
 "SEDWARE V3.2 correction fixture requires Studio or an explicitly owned test place")
assert(storage:FindFirstChild("SEDWAREV32TestControl")==nil,"Duplicate owned V3.2 test fixture")
local remote=Instance.new("RemoteEvent")
remote.Name="SEDWAREV32TestControl";remote.Parent=storage
local cooldown,connections={},{}
local function grant(player)
 player:SetAttribute("SEDWAREV32TestAuthorized",true)
 player:SetAttribute("SEDWAREV32TestCorrectionSerial",0)
end
table.insert(connections,players.PlayerAdded:Connect(grant))
for _,player in players:GetPlayers() do grant(player) end
table.insert(connections,remote.OnServerEvent:Connect(function(player,command,value)
 if player:GetAttribute("SEDWAREV32TestAuthorized")~=true then return end
 if command~="WalkSpeedOverride" or type(value)~="number" or (value~=7 and value~=16) then return end
 local now=os.clock()
 if cooldown[player] and now-cooldown[player]<.5 then return end
 local character=player.Character;local humanoid=character and character:FindFirstChildOfClass("Humanoid")
 if humanoid==nil or humanoid.Health<=0 then return end
 cooldown[player]=now
 local ok,issue=pcall(function() humanoid.WalkSpeed=value end)
 if not ok then warn("[SEDWARE][NativeV32][SERVER CORRECTION FAILED] "..tostring(issue));return end
 player:SetAttribute("SEDWAREV32TestAppliedWalkSpeed",humanoid.WalkSpeed)
 player:SetAttribute("SEDWAREV32TestCorrectionSerial",(player:GetAttribute("SEDWAREV32TestCorrectionSerial") or 0)+1)
 print("[SEDWARE][NativeV32][SERVER CORRECTION] "..player.Name.." WalkSpeed="..humanoid.WalkSpeed)
end))
table.insert(connections,players.PlayerRemoving:Connect(function(player) cooldown[player]=nil end))
script.Destroying:Connect(function()
 for _,connection in connections do connection:Disconnect() end
 table.clear(connections);table.clear(cooldown);remote:Destroy()
 for _,player in players:GetPlayers() do
  player:SetAttribute("SEDWAREV32TestAuthorized",nil)
  player:SetAttribute("SEDWAREV32TestAppliedWalkSpeed",nil)
  player:SetAttribute("SEDWAREV32TestCorrectionSerial",nil)
 end
end)

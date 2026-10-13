--!nonstrict
-- Only packaged in THIS owned Studio test/demo experience. No game remotes.
local players=game:GetService("Players")
local storage=game:GetService("ReplicatedStorage")
workspace:SetAttribute("SEDWAREMovementAuthorized",true)
local function grant(player) player:SetAttribute("SEDWAREMovementAuthorized",true) end
players.PlayerAdded:Connect(grant)
for _,player in players:GetPlayers() do grant(player) end
local reset=Instance.new("RemoteEvent");reset.Name="SEDWAREV2TestRespawn";reset.Parent=storage
local last={}
reset.OnServerEvent:Connect(function(player)
 if player:GetAttribute("SEDWAREMovementAuthorized")~=true then return end
 local now=os.clock()
 if last[player] and now-last[player]<1 then return end
 last[player]=now
 local ok,problem=pcall(function() player:LoadCharacterAsync() end)
 if not ok then warn("[SEDWARE][NativeV2][RespawnFailure] "..tostring(problem)) end
end)
players.PlayerRemoving:Connect(function(player) last[player]=nil end)

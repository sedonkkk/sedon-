--!nonstrict
-- Event-driven roster/character cache. GetPlayers is used exactly once.
local Cleanup=if script then require(script.Parent.Cleanup) else require("./Cleanup")
local PlayerRegistry={}
PlayerRegistry.__index=PlayerRegistry
function PlayerRegistry.new(players,onChange)
 local self=setmetatable({entries={},list={},byUsername={},cleanup=Cleanup.new(),onChange=onChange,destroyed=false},PlayerRegistry)
 local ok,problem=pcall(function()
  self.cleanup:connect(players.PlayerAdded,function(player) self:_add(player) end)
  self.cleanup:connect(players.PlayerRemoving,function(player) self:_remove(player) end)
  for _,player in players:GetPlayers() do self:_add(player) end
 end)
 if not ok then self:destroy();error(problem,2) end
 return self
end
function PlayerRegistry:_emit(kind,entry)
 if not self.destroyed and self.onChange then self.onChange(kind,entry) end
end
function PlayerRegistry:_refresh(entry)
 local character=entry.character
 local oldHumanoid=entry.humanoid
 entry.humanoid=character and character:FindFirstChildOfClass("Humanoid")
 entry.root=character and character:FindFirstChild("HumanoidRootPart")
 entry.head=character and character:FindFirstChild("Head")
 if oldHumanoid~=entry.humanoid then
  if entry.deathConnection then entry.deathConnection:Disconnect();entry.deathConnection=nil end
  if entry.humanoid then
   entry.deathConnection=entry.charCleanup:connect(entry.humanoid.Died,function() self:_emit("Died",entry) end)
  end
 end
 self:_emit("Ready",entry)
end
function PlayerRegistry:_character(entry,character)
 entry.charCleanup:destroy();entry.charCleanup=Cleanup.new();entry.deathConnection=nil
 entry.character=character;entry.humanoid=nil;entry.root=nil;entry.head=nil
 if character then
  entry.charCleanup:connect(character.ChildAdded,function() self:_refresh(entry) end)
  entry.charCleanup:connect(character.ChildRemoved,function() self:_refresh(entry) end)
  entry.charCleanup:connect(character.AncestryChanged,function() self:_refresh(entry) end)
  self:_refresh(entry)
 else self:_emit("CharacterRemoving",entry) end
end
function PlayerRegistry:_add(player)
 if self.destroyed or self.entries[player] then return end
 local entry={player=player,username=string.lower(player.Name),cleanup=Cleanup.new(),charCleanup=Cleanup.new()}
 self.entries[player]=entry;self.byUsername[string.lower(player.Name)]=entry;table.insert(self.list,entry)
 entry.cleanup:connect(player.CharacterAdded,function(character) self:_character(entry,character) end)
 entry.cleanup:connect(player.CharacterRemoving,function(character)
  if entry.character==character then self:_character(entry,nil) end
 end)
 self:_character(entry,player.Character);self:_emit("PlayerAdded",entry)
end
function PlayerRegistry:_remove(player)
 local entry=self.entries[player];if not entry then return end
 self.entries[player]=nil;self.byUsername[string.lower(player.Name)]=nil
 for index,value in self.list do if value==entry then table.remove(self.list,index);break end end
 self:_emit("PlayerRemoving",entry)
 entry.cleanup:destroy();entry.charCleanup:destroy()
end
function PlayerRegistry:lookup(username) return self.byUsername[string.lower(username)] end
function PlayerRegistry:destroy()
 if self.destroyed then return end
 self.destroyed=true;self.cleanup:destroy()
 for _,entry in self.list do entry.cleanup:destroy();entry.charCleanup:destroy() end
 table.clear(self.entries);table.clear(self.list);table.clear(self.byUsername)
end
return PlayerRegistry

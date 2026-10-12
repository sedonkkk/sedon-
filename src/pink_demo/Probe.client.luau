--!nonstrict
-- OWNED STUDIO EXPERIENCE ONLY. Six compatible Tools share one SEDWARE lock.
-- C selects through SEDWARE. Locked shots use its public predicted position;
-- unlocked shots follow the camera/mouse ray. No camera writes or game hooks.
local RunService=game:GetService("RunService")
if not RunService:IsStudio() then
 warn("[SEDWARE][Weapon][SKIPPED] Owned weapon demonstration requires Roblox Studio; no Da Hood weapon integration is installed.")
 return
end
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService") -- GenerateGUID only; no HTTP requests.
local player=Players.LocalPlayer
local world=workspace
local connections,trackedTools,containers={},{},{}
local manager,verification,destroyed=nil,nil,false
local api
local owner
local function logFailure(message)
 warn("[SEDWARE][Weapon] "..tostring(message))
end
local function required(parent,name,class)
 local object=parent:WaitForChild(name,10)
 assert(object and object:IsA(class),"Missing owned Studio "..name.." (expected "..class..")")
 return object
end
local function connect(list,signal,callback)
 local connection=signal:Connect(callback)
 assert(connection and connection.Connected and type(connection.Disconnect)=="function","Owned weapon connection failed")
 table.insert(list,connection)
 return connection
end
local function disconnect(list)
 for _,connection in list do pcall(function() connection:Disconnect() end) end
 table.clear(list)
end
local function cleanup()
 if destroyed then return end
 destroyed=true
 disconnect(connections)
 for tool,list in trackedTools do disconnect(list);trackedTools[tool]=nil end
 for container,list in containers do disconnect(list);containers[container]=nil end
 if verification then verification:destroy() end
 if manager then manager:destroy() end
 if owner then pcall(function() owner:Destroy() end);owner=nil end
end
local ok,problem=xpcall(function()
 assert(player,"LocalPlayer unavailable")
 local bundle=required(ReplicatedStorage,"PinkDotLock","ModuleScript")
 api=require(bundle)
 assert(type(api)=="table" and api.session and not api.session.destroyed,"SEDWARE initialization failed; inspect [SEDWARE] console messages")
 local modules=required(ReplicatedStorage,"SEDWAREWeaponModules","Folder")
 local WeaponManager=require(required(modules,"WeaponManager","ModuleScript"))
 local WeaponProfiles=require(required(modules,"WeaponProfiles","ModuleScript"))
 local NativeVerification=require(required(modules,"NativeVerification","ModuleScript"))
 local profiles=WeaponProfiles.defaults()
 local remotes=required(ReplicatedStorage,"SEDWAREWeaponRemotes","Folder")
 assert(remotes:GetAttribute("OwnedSEDWAREWeapon")==true,"Owned Studio weapon remotes marker missing")
 local Fire=required(remotes,"Fire","RemoteEvent")
 local Result=required(remotes,"Result","RemoteEvent")
 local Verification=required(remotes,"Verification","RemoteFunction")
 local function invokeVerification(action,targetId,runId)
  if not remotes.Parent then return {ok=false,reason="native-test-remotes-unavailable"} end
  local finished,result=false,nil
  local worker=task.spawn(function()
   local succeeded,value=pcall(function() return Verification:InvokeServer(action,targetId,runId) end)
   result=if succeeded then value else {ok=false,reason=tostring(value)}
   finished=true
  end)
  local deadline=os.clock()+5
  while not finished and remotes.Parent and os.clock()<deadline do task.wait(0.05) end
  if not finished then pcall(task.cancel,worker);return {ok=false,reason="native-test-control-timeout"} end
  return result
 end
 -- This ScreenGui has ResetOnSpawn=false. A direct PlayerGui BindableEvent can
 -- be removed during respawn even while the SEDWARE interface is preserved.
 local ownerContainer=api.session.overlay.gui
 assert(ownerContainer and ownerContainer:IsA("ScreenGui") and ownerContainer.Parent,"SEDWARE persistent interface unavailable")
 local old=ownerContainer:FindFirstChild("SEDWAREWeaponClientOwner")
 if old then
  assert(old:IsA("BindableEvent"),"Conflicting owned weapon client owner")
  old:Fire();old:Destroy()
 end
 owner=Instance.new("BindableEvent")
 owner.Name="SEDWAREWeaponClientOwner";owner.Parent=ownerContainer
 connect(connections,owner.Event,cleanup)
 connect(connections,script.Destroying,cleanup)
 connect(connections,api.session.overlay.gui.Destroying,cleanup)
 connect(connections,remotes.Destroying,function()
  logFailure("Owned weapon server/remotes unloaded. No further shots or confirmations; restart Play to reconnect.")
  cleanup()
 end)
 local cameraRayParams=RaycastParams.new()
 cameraRayParams.FilterType=Enum.RaycastFilterType.Exclude
 cameraRayParams.IgnoreWater=true
 local function getOrigin(tool)
  if not tool or tool.Parent~=player.Character then return nil end
  local handle=tool:FindFirstChild("Handle")
  if not handle or not handle:IsA("BasePart") then return nil end
  local muzzle=handle:FindFirstChild("Muzzle")
  return if muzzle and muzzle:IsA("Attachment") then muzzle.WorldPosition else nil
 end
 local function getCameraAim(profile)
  local camera=world.CurrentCamera
  if not camera then return nil end
  local size=camera.ViewportSize
  if not size or size.X<=0 or size.Y<=0 then return nil end
  local x,y
  if api.session.mode=="FirstPerson" then x,y=size.X/2,size.Y/2
  else
   local mouse=UserInputService:GetMouseLocation()
   -- ViewportPointToRay and GetMouseLocation use the viewport origin. Subtracting
   -- a Core UI inset here would displace normal shots away from the actual cursor.
   x,y=mouse.X,mouse.Y
  end
  local ray=camera:ViewportPointToRay(x,y)
  local direction=ray.Direction*profile.Range
  cameraRayParams.FilterDescendantsInstances=if player.Character then {player.Character} else {}
  local result=world:Raycast(ray.Origin,direction,cameraRayParams)
  return if result then result.Position else ray.Origin+direction
 end
 local function status(kind,details)
  if destroyed then return end
  if verification then verification:record(kind,details) end
  local caption
  if kind=="Pending" then
   print("[SEDWARE][Weapon][PENDING] shot="..details.shotId.." weapon="..tostring(details.request.weaponId).." mode="..details.mode.." waiting for server collision result")
   caption="Shot pending | "..details.mode
  elseif kind=="InFlight" then
   print("[SEDWARE][Weapon][IN FLIGHT] shot="..details.shotId.." physical projectile launched; no impact confirmed")
   caption="Projectile in flight | no impact yet"
  elseif kind=="Confirmed" then
   local contact=if details.selectedTargetHit then "Confirmed target hit" elseif details.hit then "Confirmed surface contact" else "Confirmed miss"
   local damage=if type(details.damageApplied)=="number" then " | damage="..details.damageApplied else ""
   print("[SEDWARE][Weapon][CONFIRMED] shot="..details.shotId.." weapon="..tostring(details.weaponId).." "..contact..damage
    .." serverTime="..tostring(details.referenceTime).." impact="..tostring(details.impactPosition))
   caption=contact..damage
   if details.measurement then
    local record=details.measurement
    print(string.format("[SEDWARE][Weapon][MEASURED] active=%.3f manual=%.3f auto=%.3f studs at server reference %.6f",
     record.active.errorStuds,record.manual.errorStuds,record.auto.errorStuds,record.referenceTime))
   elseif details.measurementError then logFailure("Shot confirmed; measurement unavailable: "..details.measurementError) end
  elseif kind=="ServerRejected" then
   logFailure("Server rejected shot "..tostring(details.shotId)..": "..tostring(details.reason))
   caption="Shot rejected | "..tostring(details.reason)
  elseif kind=="Timeout" then
   logFailure("No server confirmation for shot "..tostring(details.shotId).."; no hit claimed")
   caption="Shot timeout | no server confirmation"
  else
   logFailure("Shot not sent: "..tostring(details.reason))
   caption="Shot not sent | "..tostring(details.reason)
  end
  if api.session and not api.session.destroyed and api.session.overlay then
   local shown,notifyError=pcall(function()
    api.session.overlay:notify("SEDWARE",world:GetServerTimeNow(),2,caption)
   end)
   if not shown then logFailure("Cannot show owned shot status: "..tostring(notifyError)) end
  end
 end
 manager=WeaponManager.new({api=api,clock=function() return world:GetServerTimeNow() end,
  sessionId=HttpService:GenerateGUID(false),profiles=profiles,
  send=function(request) Fire:FireServer(request) end,
  getCameraAim=getCameraAim,getOrigin=getOrigin,
  isEquipped=function(tool) return tool~=nil and tool.Parent==player.Character and tool:GetAttribute("OwnedSEDWAREWeapon")==true
   and profiles[tool:GetAttribute("SEDWAREProfileId")]~=nil end,
  onStatus=status,
  onWeaponChanged=function(profile)
   print("[SEDWARE][Weapon][EQUIPPED] "..profile.Id.." kind="..profile.Kind.." pellets="..profile.Pellets
    .." automatic="..tostring(profile.Automatic).." lockedTarget="..tostring(api.GetLockedTarget()))
  end})
 local function getTool(id)
  for _,container in {player.Character,player:FindFirstChildOfClass("Backpack")} do
   if container then
    for _,child in container:GetChildren() do
     if child:IsA("Tool") and child:GetAttribute("OwnedSEDWAREWeapon")==true and child:GetAttribute("SEDWAREProfileId")==id then return child end
    end
   end
  end
  return nil
 end
 verification=NativeVerification.new({api=api,manager=manager,clock=function() return world:GetServerTimeNow() end,
  wait=task.wait,getTool=getTool,getCameraAim=getCameraAim,runtimeName="RobloxStudio",
  getHumanoid=function() return assert(player.Character and player.Character:FindFirstChildOfClass("Humanoid"),"Native test shooter is not alive") end,
  beginRun=function(targetId) return invokeVerification("Begin",targetId) end,
  endRun=function(runId)
   task.defer(function()
    if remotes.Parent then local result=invokeVerification("End",nil,runId)
     if type(result)~="table" or not result.ok then logFailure("Native test health restore not confirmed: "..tostring(type(result)=="table" and result.reason or result)) end
    end
   end)
  end,
  publish=function(report)
   local encoded=HttpService:JSONEncode(report)
   player:SetAttribute("SEDWARE_NativeReport",encoded)
   print("[SEDWARE][NATIVE RUN]["..(if report.passed then "PASS" else "FAIL").."] "..encoded)
  end})
 connect(connections,UserInputService.InputBegan,function(input,processed)
  if processed or UserInputService:GetFocusedTextBox() then return end
  if input.KeyCode==api.session.config.LockKey then
   task.defer(function() if not destroyed then verification:noteC() end end)
  elseif input.KeyCode==Enum.KeyCode.F6 then
   task.spawn(function()
    local ran,result,problem=pcall(function() return verification:run() end)
    if not ran or not result then logFailure("Native verification did not complete: "..tostring(if ran then problem else result)) end
   end)
  end
 end)
 connect(connections,Result.OnClientEvent,function(response)
  if destroyed then return end
  local result,err=manager:receive(response)
  if not result then logFailure("Ignored owned shot response: "..tostring(err)) end
 end)
 connect(connections,RunService.Heartbeat,function()
  if not destroyed then
   local advanced,problem=pcall(function() manager:step() end)
   if not advanced then logFailure("Weapon heartbeat failed: "..tostring(problem));cleanup() end
  end
 end)
 local function trackTool(tool)
  if destroyed or not tool:IsA("Tool") or tool:GetAttribute("OwnedSEDWAREWeapon")~=true or trackedTools[tool] then return end
  local id=tool:GetAttribute("SEDWAREProfileId")
  if not profiles[id] then logFailure("Unsupported owned weapon profile: "..tostring(id));return end
  local list={};trackedTools[tool]=list
  manager:track(tool,id)
  connect(list,tool.Destroying,function()
   disconnect(list);trackedTools[tool]=nil
   if not manager.destroyed then manager:untrack(tool) end
  end)
 end
 local function untrackContainer(container)
  local list=containers[container]
  if list then disconnect(list);containers[container]=nil end
 end
 local function trackContainer(container)
  if destroyed or containers[container] then return end
  local list={};containers[container]=list
  for _,child in container:GetChildren() do trackTool(child) end
  connect(list,container.ChildAdded,trackTool)
  connect(list,container.Destroying,function() untrackContainer(container) end)
 end
 trackContainer(required(player,"Backpack","Backpack"))
 connect(connections,player.ChildAdded,function(child)
  if child:IsA("Backpack") then trackContainer(child) end
 end)
 if player.Character then trackContainer(player.Character) end
 connect(connections,player.CharacterAdded,trackContainer)
 connect(connections,player.CharacterRemoving,function(character)
  manager:unequip()
  untrackContainer(character)
  for tool,list in trackedTools do
   if tool:IsDescendantOf(character) then disconnect(list);trackedTools[tool]=nil;manager:untrack(tool) end
  end
 end)
 connect(connections,owner.Destroying,cleanup)
 print("[SEDWARE][Weapon][READY] WeaponManager ready; six OWN profiles registered. Tools connect on arrival/equip. C locks; click fires; hold for Automatic. F6 native verification after C. Camera stays free.")
end,function(err)
 return if debug and type(debug.traceback)=="function" then debug.traceback(tostring(err),2) else tostring(err)
end)
if not ok then
 cleanup();logFailure("Owned Studio weapon client initialization failed: "..tostring(problem))
 if api and api.session and not api.session.destroyed and api.session.overlay then
  pcall(function() api.session.overlay:notify("SEDWARE",world:GetServerTimeNow(),3,"Weapon integration failed | "..tostring(problem)) end)
 end
end

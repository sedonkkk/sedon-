--!nonstrict
-- Actual embedded ESP modules exercised with explicit Roblox API doubles.
-- Instance properties are checked; native pixel rendering/StreamingEnabled
-- replication and client frame rate are not verified by this fixture.
return function(reloadBundle)
 local Mock=require("./CamV2Mock")
 local tests,checks,failures=0,0,0
 local function check(value,message)
  checks+=1;assert(value,message or ("V3.2 ESP assertion at line "..tostring(debug.info(2,"l"))))
 end
 local function test(name,body)
  tests+=1;local m=Mock.new();local a=reloadBundle(m.env)
  local ok,problem=pcall(body,m,a)
  if not ok then failures+=1;print("FAIL V3.2 ESP "..name..": "..tostring(problem)) end
  a.Unload()
  check(m:liveInstances("Highlight")==0,"Highlight survived unload")
  check(m:liveInstances("SelectionBox")==0,"SelectionBox survived unload")
  check(m:liveInstances("BillboardGui")==0,"BillboardGui survived unload")
  check(m:countConnections()==0,"connection survived unload")
  check(m:countRenderBindings()==0,"render binding survived unload")
  check(m.tweens.active==0,"tween survived unload")
 end
 local function session(m,a,overrides)
  local config={ESP=true,Names=true,Hitboxes=true,ESPAuthorized=true,ESPOcclusionMode="AlwaysOnTop",WelcomeNotification=false}
  for key,value in overrides or {} do config[key]=value end
  local s=a.init(config);m:advance(.15);return s
 end
 test("loaded occluded parts use native authorized depth flags and keep physical size",function(m,a)
  local p=m:addPlayer("OccludedOwned",m.env.Vector3.new(0,0,-50));m:setOccluded(p,true)
  local root=p.Character:FindFirstChild("HumanoidRootPart");local originalSize=root.Size
  local s=session(m,a);local r=s.esp.renderers[p]
  check(r and r.highlight.Enabled and r.highlight.DepthMode==m.env.Enum.HighlightDepthMode.AlwaysOnTop)
  check(r.highlight.Adornee==p.Character and r.highlight.Parent==m.playerGui)
  check(r.screenBox.Visible and r.screenBox.Parent==s.esp.layer and s.esp.layer.Parent==m.playerGui)
  check(r.billboard.Enabled and r.billboard.AlwaysOnTop and r.billboard.Adornee==p.Character:FindFirstChild("Head"))
  check(root.Size==originalSize and root.Anchored==false,"visual ESP changed physical hitbox")
  check(s.esp.stats.raycasts==0)
 end)
 test("hidden Highlights release native slots while other visuals remain pooled",function(m,a)
  local p=m:addPlayer("PooledOwned",m.env.Vector3.new(0,0,-50));local s=session(m,a)
  local r=s.esp.renderers[p];local frame,billboard,first=r.screenBox,r.billboard,r.highlight
  local created=r.created;local allocated=#m.instances
  for _=1,120 do m:advance(1/60) end
  check(r.highlight==first and r.created==created,"visible Highlight was allocated repeatedly")
  check(#m.instances==allocated,"steady visible SDK allocated instances")
  m:move(p,m.env.Vector3.new(2000,0,-50));s.esp:refresh();m:advance(.15)
  check(r.highlight==nil and first._destroyed and m:liveInstances("Highlight")==0,"disabled Highlight retained a native slot")
  check(r.screenBox==frame and not frame.Visible and r.billboard==billboard and not billboard.Enabled)
  local hiddenAllocated=#m.instances
  for _=1,120 do m:advance(1/60) end
  check(r.created==created,"hidden renderer allocated per update")
  check(#m.instances==hiddenAllocated,"steady hidden SDK allocated instances")
  m:move(p,m.env.Vector3.new(0,0,-50));s.esp:refresh();m:advance(.15)
  check(r.highlight~=nil and r.highlight~=first and r.highlight.Enabled)
  check(r.created==created+1 and r.screenBox==frame and r.billboard==billboard,"reveal replaced pooled GUI")
  check(m:liveInstances("Highlight")==1)
 end)
 test("applied Username follows respawn without applying the edited draft",function(m,a)
  local p=m:addPlayer("AppliedOwned",m.env.Vector3.new(0,0,-50))
  local draft=m:addPlayer("DraftOwned",m.env.Vector3.new(10,0,-50));local s=session(m,a)
  check(s:configure("ESPUsername",p.Name));check(s:ApplyESPTarget())
  check(s:configure("ESPUsername",draft.Name));m:advance(.15)
  local r=s.esp.renderers[p];local oldCharacter=p.Character;local frame,billboard=r.screenBox,r.billboard
  m:respawn(p,m.env.Vector3.new(0,0,-60));m:advance(.15)
  check(p.Character~=oldCharacter and s.esp.selectedUsername=="appliedowned" and s.config.ESPUsername==draft.Name)
  check(s.esp.renderers[p]==r and s.esp.renderers[draft]==nil)
  check(r.screenBox==frame and r.billboard==billboard and r.highlight.Adornee==p.Character)
  check(r.billboard.Adornee==p.Character:FindFirstChild("Head") and r.billboard.Enabled)
  check(m:liveInstances("Highlight")==1)
 end)
 test("stale Head from another character falls back to the valid root",function(m,a)
  local p=m:addPlayer("HeadFallback",m.env.Vector3.new(0,0,-50))
  local other=m:addPlayer("OtherHead",m.env.Vector3.new(2000,0,-50));local s=session(m,a,{ESPTargetMode="Specific Player",ESPUsername=p.Name})
  local entry=s.registry.entries[p];local actualHead=entry.head;local root=entry.root
  entry.head=other.Character:FindFirstChild("Head");s.esp:refresh();m:advance(.15)
  local r=s.esp.renderers[p]
  check(s.esp.stats.visible==1 and s.esp.stats.invalidHead==1 and r.billboard.Enabled and r.billboard.Adornee==root,"stale Head affected range or Adornee")
  entry.head=actualHead;s.esp:refresh();m:advance(.15)
  check(r.billboard.Adornee==actualHead and r.billboard.Enabled)
 end)
 test("stale or non-BasePart roots are rejected rather than drawing another character",function(m,a)
  local p=m:addPlayer("RootValidation",m.env.Vector3.new(0,0,-50))
  local other=m:addPlayer("OtherRoot",m.env.Vector3.new(20,0,-50));local s=session(m,a,{ESPTargetMode="Specific Player",ESPUsername=p.Name})
  local entry=s.registry.entries[p];local root=entry.root;local r=s.esp.renderers[p]
  entry.root=other.Character:FindFirstChild("HumanoidRootPart");s.esp:refresh();m:advance(.15)
  check(s.esp.stats.visible==0 and s.esp.stats.notReady==1 and s.esp.stats.invalidRoot==1 and r.highlight==nil)
  check(not r.screenBox.Visible and not r.billboard.Enabled and r.billboard.Adornee==nil)
  -- Inject a stale registry reference, rather than relying only on its events.
  local folder=m.env.Instance.new("Folder");folder.Parent=p.Character;entry.root=folder
  s.esp:refresh();m:advance(.15);check(s.esp.stats.notReady==1 and r.highlight==nil)
  folder:Destroy();entry.root=root;s.esp:refresh();m:advance(.15)
  check(s.esp.stats.visible==1 and r.highlight.Adornee==p.Character and r.billboard.Enabled)
 end)
 test("stream-out and stream-in reuse GUI and never infer absent character positions",function(m,a)
  local p=m:addPlayer("StreamingOwned",m.env.Vector3.new(0,0,-3000))
  local s=session(m,a,{ESPUnlimitedRange=true});m:advance(.4)
  local r=s.esp.renderers[p];local frame,billboard=r.screenBox,r.billboard;local character=p.Character
  check(billboard.MaxDistance==0 and s.esp.stats.visible==1)
  character.Parent=nil;m:advance(.4)
  check(s.esp.stats.notReady==1 and s.esp.stats.visible==0 and r.highlight==nil)
  check(not frame.Visible and not billboard.Enabled and billboard.Adornee==nil)
  character.Parent=m.world;m:advance(.4)
  check(s.esp.stats.visible==1 and r.screenBox==frame and r.billboard==billboard)
  check(r.highlight.Adornee==character and billboard.Adornee==character:FindFirstChild("Head"))
  m:removePlayer(p);check(s.esp.renderers[p]==nil and m:liveInstances("Highlight")==0)
 end)
 test("shared config mode changes create the required hierarchy for an existing renderer",function(m,a)
  local p=m:addPlayer("ConfigModeOwned",m.env.Vector3.new(0,0,-50))
  local s=session(m,a,{ESPOcclusionMode="VisibleOnly",ESPTargetMode="Specific Player",ESPUsername=p.Name})
  local manager=s.esp;local r=manager.renderers[p]
  check(r.box.Visible and manager.layer==nil)
  -- The modular API shares Config. refresh() must support a mode change,
  -- independently of Session.configure() rebuilding the whole manager.
  s.config.ESPOcclusionMode="AlwaysOnTop";manager:refresh();m:advance(.15)
  check(manager.renderers[p]==r and r.box==nil)
  check(manager.layer~=nil and manager.layer.Parent==m.playerGui)
  check(r.screenBox.Visible and r.screenBox.Parent==manager.layer and r.highlight.Enabled)
  check(r.billboard.AlwaysOnTop and manager.stats.mode=="AlwaysOnTop")
  local layer=manager.layer;local highlight=r.highlight
  s.config.ESPOcclusionMode="VisibleOnly";manager:refresh();m:advance(.15)
  check(manager.renderers[p]==r and manager.layer==nil and layer._destroyed)
  check(highlight._destroyed and r.highlight==nil and r.screenBox==nil)
  check(r.box.Visible and not r.billboard.AlwaysOnTop)
  check(manager.stats.mode=="VisibleOnly" and manager.selectedUsername=="configmodeowned")
 end)
 test("mode toggles release old hierarchy and preserve applied Username",function(m,a)
  local p=m:addPlayer("ModeOwned",m.env.Vector3.new(0,0,-50));local s=session(m,a,{ESPTargetMode="Specific Player",ESPUsername=p.Name})
  for _=1,8 do
   local old=s.esp.renderers[p];check(old and old.highlight and old.highlight.Enabled)
   check(s:configure("ESPOcclusionMode","VisibleOnly"));m:advance(.15)
   local r=s.esp.renderers[p]
   check(old.destroyed and old.highlight==nil and old.screenBox==nil and old.billboard==nil)
   check(r.box.Visible and r.box.Adornee==p.Character:FindFirstChild("HumanoidRootPart"))
   check(not r.billboard.AlwaysOnTop and r.highlight==nil and s.esp.layer==nil and m:liveInstances("Highlight")==0)
   check(s.esp.selectedUsername=="modeowned")
   m:setOccluded(p,true);s.esp:refresh();m:advance(.15)
   check(not r.box.Visible and not r.billboard.Enabled)
   check(s:configure("ESPOcclusionMode","AlwaysOnTop"));m:advance(.15)
   check(s.esp.renderers[p].highlight.Enabled and s.esp.renderers[p].billboard.AlwaysOnTop)
   check(m:liveInstances("Highlight")==1 and m:liveInstances("BillboardGui")==1)
   m:setOccluded(p,false)
  end
  check(s:configure("ESP",false));check(next(s.esp.renderers)==nil and s.esp.layer==nil)
 end)
 print(string.format("SEDWARE V3.2 ESP actual-bundle doubles: %d tests, %d assertions, %d failures",tests,checks,failures))
 assert(failures==0,"V3.2 ESP bundle regressions failed")
end

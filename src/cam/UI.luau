--!nonstrict
local Config=if script then require(script.Parent.Config) else require("./Config")
local Branding=if script then require(script.Parent.Branding) else require("./Branding")
local UIAnimations=if script then require(script.Parent.UIAnimations) else require("./UIAnimations")
local UI={}
UI.__index=UI
local WIDTH,HEIGHT,HEADER,ROW=360,432,56,34
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function point(input) local p=input and input.Position;if p and finite(p.X) and finite(p.Y) then return p.X,p.Y end end
local function contains(object,x,y)
 if not object or not x or not object.Visible then return false end
 local p,s=object.AbsolutePosition,object.AbsoluteSize
 return x>=p.X and x<=p.X+s.X and y>=p.Y and y<=p.Y+s.Y
end
function UI:_create(class,props,parent)
 local item=Instance.new(class);table.insert(self.owned,item)
 for key,value in props do item[key]=value end
 item.Parent=parent;return item
end
function UI:_connect(signal,callback)
 local connection=signal:Connect(callback);table.insert(self.connections,connection);return connection
end
function UI:_label(parent,name,text,position,size,fontSize,color)
 return self:_create("TextLabel",{Name=name,Active=false,BackgroundTransparency=1,Text=text,
  Font=Enum.Font.Gotham,TextSize=fontSize or 12,TextColor3=color or Branding.Colors.White,
  TextXAlignment=Enum.TextXAlignment.Left,Position=position,Size=size,ZIndex=5},parent)
end
function UI:_button(parent,name,text,position,size)
 local button=self:_create("TextButton",{Name=name,Active=true,AutoButtonColor=false,BackgroundColor3=Branding.Colors.Input,
  BorderSizePixel=0,Text=text,Font=Enum.Font.GothamMedium,TextSize=12,TextColor3=Branding.Colors.White,
  Position=position,Size=size,ZIndex=6},parent)
 self:_create("UICorner",{CornerRadius=UDim.new(0,5)},button)
 self:_connect(button.MouseEnter,function() self.animations:play(button,0.10,{BackgroundColor3=Branding.Colors.Surface}) end)
 self:_connect(button.MouseLeave,function()
  local on=self.values[name]==true
  self.animations:play(button,0.10,{BackgroundColor3=if on then Branding.Colors.Neon else Branding.Colors.Input})
 end)
 return button
end
function UI:_notice(message) if self.onNotice then self.onNotice(tostring(message)) end end
function UI:_action(name,value) if self.onAction then return self.onAction(name,value) end end
function UI:_change(field,value)
 if self.destroyed then return false end
 local ok,accepted,reason=pcall(self.onChange,field,value)
 if not ok then reason=accepted;accepted=false end
 if accepted then self:setValue(field,value);return true end
 self:setValue(field,self.values[field]);self:_notice(reason or "Invalid value");return false
end
function UI:setValue(field,value)
 if self.destroyed or not self.controls[field] then return false end
 local changed=self.values[field]~=value
 self.values[field]=value
 local control,descriptor=self.controls[field],Config.fields[field]
 local text
 if descriptor.kind=="toggle" then
  text=if value then "ON" else "OFF"
  local properties={BackgroundColor3=if value then Branding.Colors.Neon else Branding.Colors.Input,
   TextColor3=if value then Branding.Colors.White else Branding.Colors.Muted}
  if self.building then for key,property in properties do control[key]=property end
  elseif changed then self.animations:play(control,0.15,properties) end
 elseif descriptor.kind=="choice" then text=tostring(value).."  ▾"
 elseif descriptor.kind=="keybind" then text=Config.keyName(value)
 elseif descriptor.kind=="number" then text=string.format(if descriptor.decimals==0 then "%g" else "%."..tostring(descriptor.decimals).."f",value)
 else text=tostring(value) end
 if control.Text~=text then control.Text=text end
 if field=="ESPTargetMode" and not self.building then self:_layoutMisc() end
 return true
end
function UI:setCapture(field,active)
 if self.destroyed then return end
 self.capturing=if active then field else nil
 self.controls[field].Text=if active then "Press a key" else Config.keyName(self.values[field])
 self.animations:play(self.controls[field],0.15,{TextColor3=if active then Branding.Colors.Pink else Branding.Colors.White})
end
function UI:resetDrag() self.drag=nil end
function UI:_startDrag(input)
 if self.destroyed then return end
 if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
 local x,y=point(input)
 if not contains(self.header,x,y) or contains(self.minimizeButton,x,y) then return end
 if self.drag and self.drag.input==input then return end
 self:closeDropdown(true)
 self.drag={input=input,touch=input.UserInputType==Enum.UserInputType.Touch,x=x,y=y,position=self.panel.Position}
end
function UI:_fit(force)
 local camera=self.world.CurrentCamera;local size=camera and camera.ViewportSize or self.gui.AbsoluteSize
 if not size or not finite(size.X) or not finite(size.Y) or size.X<=0 or size.Y<=0 then return end
 local desiredHeight=if self.minimized then HEADER else HEIGHT
 local scale=math.max(0.05,math.min(1,(size.X-16)/WIDTH,(size.Y-16)/desiredHeight))
 local current=self.panel.Position
 local x=math.clamp(current.X.Offset,8,math.max(8,size.X-WIDTH*scale-8))
 local y=math.clamp(current.Y.Offset,8,math.max(8,size.Y-desiredHeight*scale-8))
 if self.scale.Scale~=scale then self.scale.Scale=scale end
 if current.X.Offset~=x or current.Y.Offset~=y then self.panel.Position=UDim2.fromOffset(x,y) end
 local resized=not self.viewport or self.viewport.X~=size.X or self.viewport.Y~=size.Y
 self.viewport=size
 if resized and self.popupField then self:_positionDropdown(false) end
end
function UI:step(now)
 if self.destroyed then return end
 self:_fit()
 if self.popupCloseAt and os.clock()>=self.popupCloseAt then self.dropdown.Visible=false;self.popupCloseAt=nil end
end
function UI:setTab(tab)
 if self.destroyed or not self.pages[tab] then return false end
 if self.shownTab==tab then return true end
 self:closeDropdown(true);self:_action("CancelCapture");self.tab=tab
 self.shownTab=tab
 for name,page in self.pages do
  page.Visible=name==tab and not self.minimized
  if page.Visible then page.GroupTransparency=1;self.animations:play(page,0.18,{GroupTransparency=0}) end
  self.tabButtons[name].TextColor3=if name==tab then Branding.Colors.Pink else Branding.Colors.Muted
 end
 return true
end
function UI:setMinimized(value)
 if self.destroyed or value==self.minimized then return end
 self.minimized=value;self:resetDrag();self:closeDropdown(true);self:_action("CancelCapture")
 self.minimizeButton.Text=if value then "+" else "−"
 self.tabs.Visible=not value
 for name,page in self.pages do page.Visible=not value and name==self.tab end
 self.animations:play(self.panel,0.22,{Size=UDim2.fromOffset(WIDTH,if value then HEADER else HEIGHT)})
 if not value then
  local page=self.pages[self.tab];page.GroupTransparency=1;self.animations:play(page,0.18,{GroupTransparency=0})
 end
 self:_fit(true)
end
function UI:closeDropdown(immediate)
 self.popupField=nil
 for _,button in self.popupButtons do button.Active=false end
 if not self.dropdown or not self.dropdown.Visible then return end
 if immediate then self.animations:cancel(self.dropdown);self.dropdown.Visible=false;self.popupCloseAt=nil
 else
  self.animations:play(self.dropdown,0.15,{Size=UDim2.fromOffset(self.dropdown.Size.X.Offset,0)})
  self.popupCloseAt=os.clock()+0.15
 end
end
function UI:_openDropdown(field)
 if self.popupField==field then self:closeDropdown();return end
 self:closeDropdown(true);self:_action("CancelCapture")
 self.popupField=field;self.popupOptions=Config.fields[field].options
 self.popupCloseAt=nil
 self:_positionDropdown(true)
end
function UI:_positionDropdown(animate)
 local field=self.popupField;if not field then return end
 local button=self.controls[field];local p,s=button.AbsolutePosition,button.AbsoluteSize
 local view=self.viewport or self.world.CurrentCamera.ViewportSize
 local scale=self.scale.Scale;local width=math.min(view.X-16,math.max(130,s.X))
 local height=30*#self.popupOptions*scale
 local x=math.clamp(p.X,8,math.max(8,view.X-width-8))
 local y=p.Y+s.Y+4
 if y+height>view.Y-8 then y=math.max(8,p.Y-height-4) end
 self.dropdown.Position=UDim2.fromOffset(x,y)
 self.animations:cancel(self.dropdown)
 self.dropdown.Size=UDim2.fromOffset(width,if animate then 0 else math.min(height,view.Y-16))
 self.dropdown.CanvasSize=UDim2.fromOffset(0,height);self.dropdown.Visible=true
 for index,choice in self.popupButtons do
  local value=self.popupOptions[index];choice.Visible=value~=nil;choice.Active=value~=nil
  if value then
   choice.Text=value;choice.Position=UDim2.fromOffset(3,(index-1)*30*scale+2)
   choice.Size=UDim2.fromOffset(width-6,30*scale-3);choice.TextSize=math.max(10,11*scale)
  end
 end
 if animate then self.animations:play(self.dropdown,0.15,{Size=UDim2.fromOffset(width,math.min(height,view.Y-16))}) end
end
function UI:_row(parent,descriptor)
 local row=self:_create("Frame",{Name=descriptor.key.."Row",Active=false,BackgroundTransparency=1,
  Size=UDim2.fromOffset(WIDTH-32,ROW),Position=UDim2.fromOffset(0,0),ZIndex=4},parent)
 self.rows[descriptor.key]=row
 self:_label(row,"Label",descriptor.label,UDim2.fromOffset(0,0),UDim2.fromOffset(162,ROW),12)
 local control
 if descriptor.kind=="number" or descriptor.kind=="text" then
  control=self:_create("TextBox",{Name=descriptor.key,Active=true,BackgroundColor3=Branding.Colors.Input,
   BorderSizePixel=0,ClearTextOnFocus=false,Text="",PlaceholderText=if descriptor.kind=="text" then "Exact username" else "",
   Font=Enum.Font.Gotham,TextSize=12,TextColor3=Branding.Colors.White,PlaceholderColor3=Branding.Colors.Muted,
   Position=UDim2.fromOffset(164,3),Size=UDim2.fromOffset(160,27),ZIndex=6},row)
  self:_create("UICorner",{CornerRadius=UDim.new(0,5)},control)
  self:_connect(control.FocusLost,function()
   local value=if descriptor.kind=="text" then control.Text:gsub("^%s*(.-)%s*$","%1") else tonumber(control.Text)
   if descriptor.kind=="number" and not finite(value) then self:setValue(descriptor.key,self.values[descriptor.key]);self:_notice("Enter a finite number")
   else self:_change(descriptor.key,value) end
  end)
 else
  control=self:_button(row,descriptor.key,"",UDim2.fromOffset(164,3),UDim2.fromOffset(160,27))
  self:_connect(control.Activated,function()
   if self.minimized or self.tab~=descriptor.tab then return end
   if descriptor.kind=="toggle" then self:_change(descriptor.key,not self.values[descriptor.key])
   elseif descriptor.kind=="choice" then self:_openDropdown(descriptor.key)
   elseif descriptor.kind=="keybind" then self:_action("CaptureKey",descriptor.key) end
  end)
 end
 self.controls[descriptor.key]=control
 return row
end
function UI:_layoutMisc()
 if not self.miscScroll then return end
 local y=26
 for _,descriptor in Config.controls do
  if descriptor.tab=="MISC" and descriptor.section=="MOVEMENT" then self.rows[descriptor.key].Position=UDim2.fromOffset(0,y);y+=ROW end
 end
 self.espLabel.Position=UDim2.fromOffset(0,y+10);y+=38
 for _,descriptor in Config.controls do
  if descriptor.section=="ESP" then
   local visible=descriptor.key~="ESPUsername" or self.values.ESPTargetMode=="Specific Player"
   self.rows[descriptor.key].Visible=visible
   if visible then self.rows[descriptor.key].Position=UDim2.fromOffset(0,y);y+=ROW end
  end
 end
 self.actionsRow.Visible=self.values.ESPTargetMode=="Specific Player"
 if self.actionsRow.Visible then self.actionsRow.Position=UDim2.fromOffset(0,y+5);y+=38 end
 self.miscScroll.CanvasSize=UDim2.fromOffset(0,y+12)
end
function UI:updateFOV(reference,radius)
 if not self.config.ShowFOV or not reference then
  if self.fov then self.fov:Destroy();self.fov=nil end;return
 end
 if not self.fov then
  self.fov=self:_create("Frame",{Name="SelectionRadius",Active=false,AnchorPoint=Vector2.new(0.5,0.5),
   BackgroundTransparency=1,Size=UDim2.fromOffset(2*radius,2*radius),ZIndex=1},self.gui)
  self:_create("UICorner",{CornerRadius=UDim.new(0.5,0)},self.fov)
  self:_create("UIStroke",{Color=Branding.Colors.Pink,Thickness=1,Transparency=0.55},self.fov)
 end
 self.fov.Position=UDim2.fromOffset(reference.X,reference.Y);self.fov.Size=UDim2.fromOffset(2*radius,2*radius)
end
function UI.new(playerGui,config,onChange,onNotice,onAction,player)
 local self=setmetatable({config=config,onChange=onChange,onNotice=onNotice,onAction=onAction,
  controls={},values={},rows={},pages={},tabButtons={},popupButtons={},hitPartOptions={},owned={},connections={},
  tab="MAIN",minimized=false,destroyed=false,building=true,animations=UIAnimations.new(),
  input=game:GetService("UserInputService"),world=game:GetService("Workspace")},UI)
 local ok,problem=xpcall(function()
  local C=Branding.Colors
  self.gui=self:_create("ScreenGui",{Name="SedwareCamLock_UI",ResetOnSpawn=false,IgnoreGuiInset=true,
   DisplayOrder=41,ZIndexBehavior=Enum.ZIndexBehavior.Global},playerGui)
  self.panel=self:_create("Frame",{Name="PinkEditionPanel",Active=true,BackgroundColor3=C.Background,BorderSizePixel=0,
   Position=UDim2.fromOffset(24,110),Size=UDim2.fromOffset(WIDTH,HEIGHT),ClipsDescendants=true,ZIndex=2},self.gui)
  self.scale=self:_create("UIScale",{Scale=1},self.panel)
  self:_create("UICorner",{CornerRadius=UDim.new(0,9)},self.panel)
  self:_create("UIStroke",{Color=C.Border,Thickness=1},self.panel)
  self.header=self:_create("Frame",{Name="Header",Active=true,BackgroundColor3=C.Surface,BorderSizePixel=0,
   Size=UDim2.fromOffset(WIDTH,HEADER),ZIndex=3},self.panel)
  self.logo=Branding.addLogo(self.header,function(...) return self:_create(...) end,
   UDim2.fromOffset(15,13),UDim2.fromOffset(30,30),5,config,function(...) return self:_connect(...) end)
  self.title=self:_label(self.header,"Title","SEDWARE",UDim2.fromOffset(56,9),UDim2.fromOffset(218,22),17)
  self.title.Font=Enum.Font.GothamBold
  self.subtitle=self:_label(self.header,"Subtitle",Branding.Subtitle,UDim2.fromOffset(57,32),UDim2.fromOffset(255,14),9,C.Pink)
  self.version=self:_label(self.header,"Version","v2",UDim2.fromOffset(276,15),UDim2.fromOffset(22,17),10,C.Muted)
  self.minimizeButton=self:_button(self.header,"Minimize","−",UDim2.fromOffset(317,12),UDim2.fromOffset(29,29))
  self:_connect(self.minimizeButton.Activated,function() self:setMinimized(not self.minimized) end)
  self.tabs=self:_create("Frame",{Name="Tabs",Active=false,BackgroundTransparency=1,
   Position=UDim2.fromOffset(16,66),Size=UDim2.fromOffset(WIDTH-32,28),ZIndex=4},self.panel)
  for index,name in {"MAIN","MISC"} do
   local tab=self:_button(self.tabs,name,name,UDim2.fromOffset((index-1)*164,0),UDim2.fromOffset(160,28))
   self.tabButtons[name]=tab;self:_connect(tab.Activated,function() self:setTab(name) end)
   self.pages[name]=self:_create("CanvasGroup",{Name=name.."Page",Active=false,BackgroundTransparency=1,
    Position=UDim2.fromOffset(16,106),Size=UDim2.fromOffset(WIDTH-32,HEIGHT-122),Visible=name=="MAIN",ZIndex=4},self.panel)
  end
  self.mainLabel=self:_label(self.pages.MAIN,"MainLabel","CAM LOCK",UDim2.fromOffset(0,0),UDim2.fromOffset(300,22),10,C.Pink)
  self.miscScroll=self:_create("ScrollingFrame",{Name="MiscScroll",Active=true,BackgroundTransparency=1,BorderSizePixel=0,
   Size=UDim2.fromScale(1,1),CanvasSize=UDim2.fromOffset(0,500),ScrollBarThickness=3,ScrollBarImageColor3=C.Pink,
   ScrollingDirection=Enum.ScrollingDirection.Y,ClipsDescendants=true,ZIndex=4},self.pages.MISC)
  self.movementLabel=self:_label(self.miscScroll,"MovementLabel","MOVEMENT",UDim2.fromOffset(0,0),UDim2.fromOffset(300,22),10,C.Pink)
  self.espLabel=self:_label(self.miscScroll,"ESPLabel","ESP",UDim2.fromOffset(0,245),UDim2.fromOffset(300,22),10,C.Pink)
  local mainIndex=0
  for _,descriptor in Config.controls do
   local row=self:_row(if descriptor.tab=="MAIN" then self.pages.MAIN else self.miscScroll,descriptor)
   if descriptor.tab=="MAIN" then row.Position=UDim2.fromOffset(0,26+mainIndex*ROW);mainIndex+=1 end
   self:setValue(descriptor.key,config[descriptor.key])
  end
  self.actionsRow=self:_create("Frame",{Name="TargetActions",Active=false,BackgroundTransparency=1,
   Size=UDim2.fromOffset(WIDTH-32,34),Position=UDim2.fromOffset(0,480),ZIndex=4},self.miscScroll)
  self.applyButton=self:_button(self.actionsRow,"ApplyTarget","Apply Target",UDim2.fromOffset(0,3),UDim2.fromOffset(160,28))
  self.clearButton=self:_button(self.actionsRow,"ClearTarget","Clear Target",UDim2.fromOffset(164,3),UDim2.fromOffset(160,28))
  self:_connect(self.applyButton.Activated,function()
   if self.minimized or self.tab~="MISC" then return end
   if self:_change("ESPUsername",self.controls.ESPUsername.Text:gsub("^%s*(.-)%s*$","%1")) then self:_action("ApplyTarget") end
  end)
  self:_connect(self.clearButton.Activated,function()
   if not self.minimized and self.tab=="MISC" and self.actionsRow.Visible then self:_action("ClearTarget") end
  end)
  self.building=false;self:_layoutMisc()
  self.popupLayer=self:_create("Frame",{Name="PopupLayer",Active=false,BackgroundTransparency=1,Size=UDim2.fromScale(1,1),
   ClipsDescendants=false,ZIndex=100},self.gui)
  self.dropdown=self:_create("ScrollingFrame",{Name="Dropdown",Active=false,BackgroundColor3=C.Surface,BorderSizePixel=0,
   Size=UDim2.fromOffset(160,0),Position=UDim2.fromOffset(0,0),CanvasSize=UDim2.fromOffset(0,90),Visible=false,
   ScrollBarThickness=2,ClipsDescendants=true,ZIndex=101},self.popupLayer)
  self:_create("UICorner",{CornerRadius=UDim.new(0,5)},self.dropdown)
  self:_create("UIStroke",{Color=C.Pink,Thickness=1,Transparency=0.4},self.dropdown)
  for index,value in Config.HitParts do
   local button=self:_button(self.dropdown,"Option"..index,value,UDim2.fromOffset(3,(index-1)*30),UDim2.fromOffset(154,28))
   button.ZIndex=102;self.popupButtons[index]=button;self.hitPartOptions[value]=button
   self:_connect(button.Activated,function()
    local field=self.popupField;local choice=field and self.popupOptions[index]
    if field and choice then self:closeDropdown();self:_change(field,choice) end
   end)
  end
  self:_connect(self.header.InputBegan,function(event) self:_startDrag(event) end)
  self:_connect(self.input.InputBegan,function(event)
   if self.dropdown.Visible then
    if event.KeyCode==Enum.KeyCode.Escape then self:closeDropdown()
    else local x,y=point(event)
     if (event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch)
      and x and not contains(self.dropdown,x,y) and not contains(self.popupField and self.controls[self.popupField],x,y) then self:closeDropdown() end
    end
   end
   self:_startDrag(event)
  end)
  self:_connect(self.input.InputChanged,function(event)
   local drag=self.drag;if not drag then return end
   if drag.touch and event~=drag.input then return end
   if not drag.touch and event.UserInputType~=Enum.UserInputType.MouseMovement then return end
   local x,y=point(event);if not x then return end
   self.panel.Position=UDim2.fromOffset(drag.position.X.Offset+x-drag.x,drag.position.Y.Offset+y-drag.y);self:_fit()
  end)
  self:_connect(self.input.InputEnded,function(event)
   if self.drag and (event==self.drag.input or (not self.drag.touch and event.UserInputType==Enum.UserInputType.MouseButton1)) then self:resetDrag() end
  end)
  self:_connect(self.input.WindowFocusReleased,function() self:resetDrag();self:closeDropdown(true) end)
  if player then
   local function reset() self:resetDrag();self:closeDropdown(true);self:_action("CancelCapture") end
   self:_connect(player.CharacterRemoving,reset);self:_connect(player.CharacterAdded,reset)
  end
  self:_connect(self.gui.AncestryChanged,function() self:resetDrag();self:closeDropdown(true) end)
  self:setTab("MAIN");self:_fit(true)
 end,debug.traceback)
 if not ok then self:destroy();error("SEDWARE V2 UI: "..tostring(problem),2) end
 return self
end
function UI:setLogo(asset) Branding.setLogo(self.logo,asset) end
function UI:destroy()
 if self.destroyed then return end
 self.destroyed=true;self.drag=nil;self.animations:destroy()
 for _,connection in self.connections do pcall(function() connection:Disconnect() end) end;table.clear(self.connections)
 for index=#self.owned,1,-1 do pcall(function() self.owned[index]:Destroy() end) end;table.clear(self.owned)
end
return UI

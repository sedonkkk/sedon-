--!nonstrict
-- Native adornments follow character transforms; no per-player render loops.
local Branding=if script then require(script.Parent.Branding) else require("./Branding")
local ESPRenderer={}
ESPRenderer.__index=ESPRenderer
function ESPRenderer.new(parent,entry,config,layer,world)
 return setmetatable({parent=parent,entry=entry,config=config,layer=layer,world=world,created=0,destroyed=false,hidden=true},ESPRenderer)
end
function ESPRenderer:_new(className)
 self.created+=1;return Instance.new(className)
end
function ESPRenderer:_screenBounds(root)
 local camera=self.world.CurrentCamera
 local loX,loY,hiX,hiY=math.huge,math.huge,-math.huge,-math.huge
 local half=root.Size*0.5;local frame=root.CFrame
 for _,x in {-1,1} do for _,y in {-1,1} do for _,z in {-1,1} do
  local world=root.Position+frame.RightVector*half.X*x+frame.UpVector*half.Y*y-frame.LookVector*half.Z*z
  local p=camera:WorldToViewportPoint(world)
  if p.Z<=0 then return false end
  loX=math.min(loX,p.X);loY=math.min(loY,p.Y);hiX=math.max(hiX,p.X);hiY=math.max(hiY,p.Y)
 end end end
 self.screenBox.Position=UDim2.fromOffset(loX,loY)
 self.screenBox.Size=UDim2.fromOffset(math.max(4,hiX-loX),math.max(6,hiY-loY))
 return true
end
function ESPRenderer:sync(visible)
 if not visible then self:hide();return end
 local entry,config=self.entry,self.config
 local root=entry.root and entry.character and entry.root:IsA("BasePart") and entry.root:IsDescendantOf(entry.character) and entry.root
 local head=entry.head and entry.character and entry.head:IsA("BasePart") and entry.head:IsDescendantOf(entry.character) and entry.head
 local top=config.ESPOcclusionMode=="AlwaysOnTop"
 if config.Hitboxes and root and top then
  if self.box then self.box:Destroy();self.box=nil end
  if not self.screenBox then
   self.screenBox=self:_new("Frame");self.screenBox.Name="SEDWAREProjectedHitbox"
   self.screenBox.BackgroundTransparency=1;self.screenBox.BorderSizePixel=0;self.screenBox.Parent=self.layer
   local stroke=self:_new("UIStroke");stroke.Color=Branding.Colors.Pink;stroke.Thickness=1.5;stroke.Parent=self.screenBox
  end
  -- Disabled Highlights still consume a native rendering slot. Keep the 2D
  -- frame pooled, but create the Highlight only when it will be shown.
  if visible and not self.highlight then
   self.highlight=self:_new("Highlight");self.highlight.Name="SEDWAREAuthorizedHighlight"
   self.highlight.FillColor=Branding.Colors.Pink;self.highlight.OutlineColor=Branding.Colors.Pink
   self.highlight.FillTransparency=0.9;self.highlight.OutlineTransparency=0.15
   self.highlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop;self.highlight.Parent=self.parent
  end
  if self.highlight then
   if visible then self.highlight.Adornee=entry.character;self.highlight.Enabled=true
   else self.highlight:Destroy();self.highlight=nil end
  end
  local shown=visible and self:_screenBounds(root)
  self.screenBox.Visible=shown
 elseif config.Hitboxes and root then
  if self.screenBox then self.screenBox:Destroy();self.screenBox=nil end
  if self.highlight then self.highlight:Destroy();self.highlight=nil end
  if not self.box then
   self.box=self:_new("SelectionBox");self.box.Name="SEDWAREVisualHitbox"
   self.box.Color3=Branding.Colors.Pink;self.box.SurfaceColor3=Branding.Colors.Pink
   self.box.LineThickness=0.025;self.box.Transparency=0.2;self.box.SurfaceTransparency=0.95;self.box.Parent=self.parent
  end
  -- BasePart reference avoids ambiguous Model bounding boxes; never resizes physics.
  if self.box.Adornee~=root then self.box.Adornee=root end
  self.box.Visible=visible
 else
  if self.box then self.box:Destroy();self.box=nil end
  if self.screenBox then self.screenBox:Destroy();self.screenBox=nil end
  if self.highlight then self.highlight:Destroy();self.highlight=nil end
 end
 if config.Names and root then
  if not self.billboard then
   self.billboard=self:_new("BillboardGui");self.billboard.Name="SEDWAREPlayerName"
   self.billboard.AlwaysOnTop=false;self.billboard.LightInfluence=0;self.billboard.Size=UDim2.fromOffset(180,28)
   self.billboard.StudsOffsetWorldSpace=Vector3.new(0,2,0);self.billboard.Parent=self.parent
   self.label=self:_new("TextLabel");self.label.BackgroundTransparency=1;self.label.Size=UDim2.fromScale(1,1)
   self.label.Text=entry.player.Name;self.label.Font=Enum.Font.GothamMedium;self.label.TextSize=14
   self.label.TextColor3=Branding.Colors.White;self.label.TextStrokeTransparency=0.5;self.label.Parent=self.billboard
  end
  local adornee=head or root
  if self.billboard.Adornee~=adornee then self.billboard.Adornee=adornee end
  self.billboard.AlwaysOnTop=top
  self.billboard.MaxDistance=if config.ESPUnlimitedRange then 0 else config.ESPMaxDistance;self.billboard.Enabled=visible
 elseif self.billboard then self.billboard:Destroy();self.billboard=nil;self.label=nil end
 self.hidden=not root
end
function ESPRenderer:hide()
 if self.hidden then return end
 self.hidden=true
 if self.screenBox then self.screenBox.Visible=false end
 if self.highlight then self.highlight:Destroy();self.highlight=nil end
 if self.box then self.box.Visible=false;self.box.Adornee=nil end
 if self.billboard then self.billboard.Enabled=false;self.billboard.Adornee=nil end
end
function ESPRenderer:destroy()
 if self.destroyed then return end
 self.destroyed=true
 if self.screenBox then self.screenBox:Destroy();self.screenBox=nil end
 if self.highlight then self.highlight:Destroy();self.highlight=nil end
 if self.box then self.box:Destroy();self.box=nil end
 if self.billboard then self.billboard:Destroy();self.billboard=nil;self.label=nil end
end
return ESPRenderer

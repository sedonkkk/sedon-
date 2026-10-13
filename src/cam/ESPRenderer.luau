--!nonstrict
-- Native adornments follow character transforms; no per-player render loops.
local Branding=if script then require(script.Parent.Branding) else require("./Branding")
local ESPRenderer={}
ESPRenderer.__index=ESPRenderer
function ESPRenderer.new(parent,entry,config)
 return setmetatable({parent=parent,entry=entry,config=config,created=0,destroyed=false},ESPRenderer)
end
function ESPRenderer:_new(className)
 self.created+=1;return Instance.new(className)
end
function ESPRenderer:sync(visible)
 local entry,config=self.entry,self.config
 if config.Hitboxes and entry.character then
  if not self.box then
   self.box=self:_new("SelectionBox");self.box.Name="SEDWAREVisualHitbox"
   self.box.Color3=Branding.Colors.Pink;self.box.SurfaceColor3=Branding.Colors.Pink
   self.box.LineThickness=0.025;self.box.Transparency=0.2;self.box.SurfaceTransparency=0.95;self.box.Parent=self.parent
  end
  if self.box.Adornee~=entry.character then self.box.Adornee=entry.character end
  self.box.Visible=visible
 elseif self.box then self.box:Destroy();self.box=nil end
 if config.Names and (entry.head or entry.root) then
  if not self.billboard then
   self.billboard=self:_new("BillboardGui");self.billboard.Name="SEDWAREPlayerName"
   self.billboard.AlwaysOnTop=false;self.billboard.LightInfluence=0;self.billboard.Size=UDim2.fromOffset(132,22)
   self.billboard.StudsOffsetWorldSpace=Vector3.new(0,2,0);self.billboard.Parent=self.parent
   self.label=self:_new("TextLabel");self.label.BackgroundTransparency=1;self.label.Size=UDim2.fromScale(1,1)
   self.label.Text=entry.player.Name;self.label.Font=Enum.Font.GothamMedium;self.label.TextSize=12
   self.label.TextColor3=Branding.Colors.White;self.label.TextStrokeTransparency=0.5;self.label.Parent=self.billboard
  end
  local adornee=entry.head or entry.root
  if self.billboard.Adornee~=adornee then self.billboard.Adornee=adornee end
  self.billboard.MaxDistance=config.ESPMaxDistance;self.billboard.Enabled=visible
 elseif self.billboard then self.billboard:Destroy();self.billboard=nil;self.label=nil end
end
function ESPRenderer:hide()
 if self.box then self.box.Visible=false;self.box.Adornee=nil end
 if self.billboard then self.billboard.Enabled=false;self.billboard.Adornee=nil end
end
function ESPRenderer:destroy()
 if self.destroyed then return end
 self.destroyed=true
 if self.box then self.box:Destroy();self.box=nil end
 if self.billboard then self.billboard:Destroy();self.billboard=nil;self.label=nil end
end
return ESPRenderer

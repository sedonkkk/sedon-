--!nonstrict
-- Native geometry keeps the Sedware mark visible without an uploaded asset.
local Branding = {
	Title = "SEDWARE", Subtitle = "CAM LOCK · PINK EDITION", Version = "v2",
	Colors = if Color3 then {
		Background = Color3.fromRGB(10, 10, 14), Surface = Color3.fromRGB(19, 19, 25),
		Input = Color3.fromRGB(29, 29, 38), Border = Color3.fromRGB(57, 42, 61),
		Pink = Color3.fromRGB(255, 105, 180), Neon = Color3.fromRGB(255, 20, 147),
		White = Color3.fromRGB(245, 245, 250), Muted = Color3.fromRGB(155, 155, 170),
	} else nil,
}

-- create(className, properties, parent) is supplied by the owning UI so every
-- piece is included in its construction-failure and unload cleanup.
function Branding.addLogo(parent, create, position, size, zIndex, config, connect)
	local logo = create("Frame", {
		Name = "SedwareLogo", Active = false, BackgroundTransparency = 1,
		Position = position or UDim2.fromOffset(14, 12), Size = size or UDim2.fromOffset(26, 29),
		ZIndex = zIndex or 4,
	}, parent)
	local fallback=create("Frame",{Name="TemporaryFallback",Active=false,BackgroundTransparency=1,
  Size=UDim2.fromScale(1,1),ZIndex=zIndex or 4},logo)
	local image=create("ImageLabel",{Name="OriginalLogoImage",Active=false,BackgroundTransparency=1,
  Size=UDim2.fromScale(1,1),ScaleType=Enum.ScaleType.Fit,Image="",Visible=false,ZIndex=zIndex or 4},logo)
	local bars = {
		{"STop", 0.17, 0.07, 0.77, 0.17},
		{"SUpper", 0.10, 0.15, 0.23, 0.39},
		{"SMiddle", 0.13, 0.41, 0.75, 0.17},
		{"SLower", 0.68, 0.49, 0.23, 0.39},
		{"SBottom", 0.08, 0.78, 0.75, 0.17},
	}
	for _, bar in ipairs(bars) do
		create("Frame", {
			Name = bar[1], Active = false, BackgroundColor3 = Branding.Colors.Neon,
			BorderSizePixel = 0, Position = UDim2.fromScale(bar[2], bar[3]),
			Size = UDim2.fromScale(bar[4], bar[5]), Rotation = -12, ZIndex = zIndex or 4,
		}, fallback)
	end
	if connect then connect(image:GetPropertyChangedSignal("IsLoaded"),function()
  local loaded=image.Image:match("^rbxassetid://[1-9]%d*$")~=nil and image.IsLoaded==true
  fallback.Visible=not loaded;image.Visible=loaded;logo:SetAttribute("OriginalLogoAvailable",loaded)
 end) end
 Branding.setLogo(logo,config and config.LogoAssetId or "")
	return logo
end
function Branding.setLogo(logo,asset)
 local image=logo:FindFirstChild("OriginalLogoImage")
 local fallback=logo:FindFirstChild("TemporaryFallback")
 local valid=type(asset)=="string" and asset:match("^rbxassetid://[1-9]%d*$")~=nil
 image.Image=if valid then asset else ""
 image.Visible=valid and image.IsLoaded==true;fallback.Visible=not image.Visible
 logo:SetAttribute("OriginalLogoAvailable",image.Visible)
end

return Branding

--!nonstrict
-- Native geometry keeps the Sedware mark visible without an uploaded asset.
local Branding = {
	Title = "SEDWARE", Subtitle = "CAM LOCK", Version = "v1",
	Colors = if Color3 then {
		Background = Color3.fromRGB(10, 10, 10), Surface = Color3.fromRGB(20, 20, 20),
		Input = Color3.fromRGB(27, 27, 27), Border = Color3.fromRGB(49, 39, 45),
		Pink = Color3.fromRGB(255, 105, 180), Neon = Color3.fromRGB(255, 20, 147),
		White = Color3.fromRGB(255, 255, 255), Muted = Color3.fromRGB(158, 151, 155),
	} else nil,
}

-- create(className, properties, parent) is supplied by the owning UI so every
-- piece is included in its construction-failure and unload cleanup.
function Branding.addLogo(parent, create, position, size, zIndex)
	local logo = create("Frame", {
		Name = "SedwareLogo", Active = false, BackgroundTransparency = 1,
		Position = position or UDim2.fromOffset(14, 12), Size = size or UDim2.fromOffset(26, 29),
		ZIndex = zIndex or 4,
	}, parent)
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
		}, logo)
	end
	return logo
end

return Branding

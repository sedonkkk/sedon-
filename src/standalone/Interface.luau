--!nonstrict
-- Native Roblox controls with portable configuration in an editable JSON field.
local Players = if game then game:GetService("Players") else nil
local UserInputService = if game then game:GetService("UserInputService") else nil
local Interface = {}
Interface.__index = Interface
local COLORS = if Color3 then {
	background = Color3.fromRGB(11, 18, 31), surface = Color3.fromRGB(19, 31, 51),
	input = Color3.fromRGB(29, 44, 69), text = Color3.fromRGB(228, 237, 251),
	muted = Color3.fromRGB(147, 169, 199), accent = Color3.fromRGB(69, 139, 245),
	error = Color3.fromRGB(255, 156, 147),
} else nil
local WIDTH, HEIGHT = 620, 670

local function make(className, properties, parent)
	local instance = Instance.new(className)
	local ok, message = pcall(function()
		instance.Parent = parent
		for key, value in pairs(properties) do instance[key] = value end
	end)
	if not ok then instance:Destroy(); error(message, 2) end
	return instance
end
local function corner(parent, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius or 7) }, parent)
end
local function label(parent, text, size)
	return make("TextLabel", {
		BackgroundTransparency = 1, Text = text, TextColor3 = COLORS.text,
		Font = Enum.Font.Gotham, TextSize = size or 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.fromScale(1, 1),
	}, parent)
end
local function button(parent, text, properties)
	local values = { BackgroundColor3 = COLORS.input, TextColor3 = COLORS.text,
		Text = text, Font = Enum.Font.GothamBold, TextSize = 12, BorderSizePixel = 0 }
	for key, value in pairs(properties or {}) do values[key] = value end
	local result = make("TextButton", values, parent)
	corner(result)
	return result
end

function Interface:_connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(self.connections, connection)
	return connection
end
function Interface:_value(path)
	local node = self.config
	for segment in string.gmatch(path, "[^.]+") do
		if segment == "profile" and node == self.config then
			node = self.config.profiles and self.config.profiles[self.config.activeProfile]
		elseif type(node) == "table" then node = node[segment]
		else return nil end
	end
	return node
end
function Interface:_invoke(name, ...)
	local callback = self.callbacks[name]
	if type(callback) ~= "function" then
		self:setStatus("Acción no disponible: " .. name, true)
		return false
	end
	local ok, first, second = pcall(callback, ...)
	if not ok then self:setStatus(tostring(first), true); return false end
	return true, first, second
end
function Interface:_change(path, value)
	local invoked, accepted, message = self:_invoke("onChange", path, value)
	if invoked then
		self:setStatus(message or (accepted and "Configuración actualizada." or "Valor no válido."), not accepted)
	end
	self:refreshControls()
end
function Interface:_row(page, height)
	self.order += 1
	return make("Frame", { Name = "Row", BackgroundTransparency = 1,
		Size = UDim2.new(1, -6, 0, height or 40), LayoutOrder = self.order }, page)
end
function Interface:_note(page, text, height)
	local value = label(self:_row(page, height or 48), text, 12)
	value.TextColor3 = COLORS.muted
	value.TextWrapped = true
	value.TextYAlignment = Enum.TextYAlignment.Top
	return value
end
function Interface:_section(page, title)
	local value = label(self:_row(page, 28), string.upper(title), 11)
	value.Font = Enum.Font.GothamBold
	value.TextColor3 = COLORS.accent
end
function Interface:_metric(page, key, title, height)
	local row = self:_row(page, height or 27)
	local titleLabel = label(row, title, 12)
	titleLabel.TextColor3 = COLORS.muted
	titleLabel.Size = UDim2.fromScale(0.43, 1)
	local value = label(row, "—", 12)
	value.Position = UDim2.fromScale(0.43, 0)
	value.Size = UDim2.fromScale(0.57, 1)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextWrapped = height ~= nil
	if not height then value.TextTruncate = Enum.TextTruncate.AtEnd end
	self.metrics[key] = self.metrics[key] or {}
	table.insert(self.metrics[key], value)
end
function Interface:_toggle(page, title, path)
	local row = self:_row(page)
	local titleLabel = label(row, title)
	titleLabel.Size = UDim2.new(1, -95, 1, 0)
	local control = button(row, "", { Name = path, Size = UDim2.fromOffset(76, 28),
		Position = UDim2.new(1, -76, 0.5, -14) })
	self:_connect(control.Activated, function() self:_change(path, self:_value(path) ~= true) end)
	table.insert(self.controls, { kind = "toggle", path = path, instance = control })
end
function Interface:_number(page, title, path, minimum, maximum, decimals)
	local row = self:_row(page)
	local titleLabel = label(row, title)
	titleLabel.Size = UDim2.new(1, -125, 1, 0)
	local input = make("TextBox", { Name = path, BackgroundColor3 = COLORS.input,
		TextColor3 = COLORS.text, ClearTextOnFocus = false, Text = "", BorderSizePixel = 0,
		Size = UDim2.fromOffset(110, 30), Position = UDim2.new(1, -110, 0.5, -15),
		Font = Enum.Font.Gotham, TextSize = 12 }, row)
	corner(input)
	self:_connect(input.FocusLost, function()
		local value = tonumber(input.Text)
		if value == nil or value ~= value or math.abs(value) == math.huge then
			self:setStatus("Escribe un número finito.", true)
		elseif value < minimum or value > maximum then
			self:setStatus(string.format("Rango permitido: %g a %g.", minimum, maximum), true)
		else self:_change(path, value) end
		self:refreshControls()
	end)
	table.insert(self.controls, { kind = "number", path = path, instance = input, decimals = decimals or 3 })
end
function Interface:_closeDropdowns()
	for _, dropdown in ipairs(self.dropdowns) do
		dropdown.options.Visible = false
		dropdown.row.Size = UDim2.new(1, -6, 0, 40)
	end
end
function Interface:_dropdown(page, title, path, options)
	local row = self:_row(page)
	local titleLabel = label(row, title)
	titleLabel.Size = UDim2.new(1, -210, 0, 40)
	local control = button(row, "", { Name = path, Size = UDim2.fromOffset(198, 30),
		Position = UDim2.new(1, -198, 0, 5) })
	local choices = make("Frame", { Name = "Options", BackgroundColor3 = COLORS.input,
		BorderSizePixel = 0, Position = UDim2.new(1, -198, 0, 40),
		Size = UDim2.fromOffset(198, #options * 31 + 4), Visible = false }, row)
	corner(choices)
	for index, option in ipairs(options) do
		local optionLabel = type(option) == "table" and option.label or option
		local optionValue = option
		if type(option) == "table" then optionValue = option.value end
		local choice = button(choices, optionLabel, { Name = optionLabel,
			BackgroundTransparency = 1, Size = UDim2.new(1, -4, 0, 30),
			Position = UDim2.fromOffset(2, (index - 1) * 31 + 2) })
		self:_connect(choice.Activated, function()
			self:_closeDropdowns()
			self:_change(path, optionValue)
		end)
	end
	self:_connect(control.Activated, function()
		local show = not choices.Visible
		self:_closeDropdowns()
		choices.Visible = show
		row.Size = UDim2.new(1, -6, 0, show and (44 + #options * 31) or 40)
	end)
	table.insert(self.dropdowns, { row = row, options = choices })
	table.insert(self.controls, { kind = "dropdown", path = path, instance = control, options = options })
end
function Interface:_button(page, title, callback, name)
	local control = button(self:_row(page, 38), title, {
		Name = name or title, Size = UDim2.new(1, 0, 0, 34) })
	self:_connect(control.Activated, callback)
	return control
end
function Interface:refreshControls()
	if self.destroyed then return end
	for _, control in ipairs(self.controls) do
		local value = self:_value(control.path)
		if control.kind == "toggle" then
			control.instance.Text = value == true and "ON" or "OFF"
			control.instance.TextColor3 = value == true and COLORS.text or COLORS.muted
			control.instance.BackgroundColor3 = value == true and COLORS.accent or COLORS.input
		elseif control.kind == "number" then
			if not control.instance:IsFocused() then
				control.instance.Text = type(value) == "number"
					and string.format("%." .. control.decimals .. "f", value) or "—"
			end
		else
			local display = tostring(value)
			for _, option in ipairs(control.options) do
				if type(option) == "table" and option.value == value then display = option.label end
			end
			control.instance.Text = display .. "  ▾"
		end
	end
end
function Interface:setConfig(config)
	self.config = config
	self:refreshControls()
end
function Interface:setStatus(message, isError)
	if self.destroyed or not self.status then return end
	self.status.Text = tostring(message or "")
	self.status.TextColor3 = isError and COLORS.error or COLORS.muted
end
function Interface:_showPage(name)
	self:_closeDropdowns()
	for pageName, page in pairs(self.pages) do
		local selected = pageName == name
		page.Visible = selected
		self.tabs[pageName].TextColor3 = selected and COLORS.text or COLORS.muted
		self.tabs[pageName].BackgroundColor3 = selected and COLORS.accent or COLORS.surface
	end
end
function Interface:_setCollapsed(collapsed)
	self.collapsed = collapsed
	self.content.Visible = not collapsed
	self.tabStrip.Visible = not collapsed
	self.status.Visible = not collapsed
	self.fireButton.Visible = not collapsed
	self.panel.Size = UDim2.fromOffset(WIDTH, collapsed and 54 or HEIGHT)
	self.minimize.Text = collapsed and "+" or "−"
	self:_fit()
end
function Interface:_fit()
	local camera = workspace.CurrentCamera
	if not camera or not self.scale then return end
	local viewport = camera.ViewportSize
	self.scale.Scale = math.clamp(math.min((viewport.X - 24) / WIDTH, (viewport.Y - 32) / HEIGHT), 0.2, 1)
	local position = self.panel.Position
	self.panel.Position = UDim2.fromOffset(
		math.clamp(position.X.Offset, 0, math.max(0, viewport.X - self.panel.AbsoluteSize.X)),
		math.clamp(position.Y.Offset, 0, math.max(0, viewport.Y - self.panel.AbsoluteSize.Y))
	)
end
function Interface:_showText(text, message)
	if type(text) ~= "string" then self:setStatus("La exportación no devolvió texto JSON.", true); return end
	self.editor.Text = text
	self:_setCollapsed(false)
	self:_showPage("SETTINGS")
	-- UIListLayout updates asynchronously; the next metrics update sees its positions.
	self.pendingEditorScroll = true
	self:setStatus(message or "JSON listo para copiar desde el campo editable.")
end

function Interface.new(config, callbacks)
	assert(Players and UserInputService and COLORS, "La interfaz requiere las APIs de Roblox en un LocalScript")
	local self = setmetatable({ config = config, callbacks = callbacks or {},
		connections = {}, controls = {}, metrics = {}, pages = {}, tabs = {},
		dropdowns = {}, order = 0, destroyed = false }, Interface)
	local ok, failure = pcall(function()
	self.gui = make("ScreenGui", { Name = "DHPredictionLab", ResetOnSpawn = false,
		IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 30,
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))
	-- Session owns this event so a later run can clean up the complete session.
	self.stopEvent = make("BindableEvent", { Name = "DHPredictionLabStop" }, self.gui)
	self.panel = make("Frame", { Name = "Panel", BackgroundColor3 = COLORS.background,
		BorderSizePixel = 0, Size = UDim2.fromOffset(WIDTH, HEIGHT),
		Position = UDim2.fromOffset(22, 38) }, self.gui)
	corner(self.panel, 12)
	make("UIStroke", { Color = Color3.fromRGB(44, 69, 104), Thickness = 1 }, self.panel)
	self.scale = make("UIScale", {}, self.panel)
	local header = make("Frame", { BackgroundTransparency = 1,
		Size = UDim2.new(1, -28, 0, 54), Position = UDim2.fromOffset(14, 0) }, self.panel)
	local dragHandle = make("Frame", { Name = "DragHandle", BackgroundTransparency = 1,
		Active = true, Size = UDim2.new(1, -115, 1, 0) }, header)
	local title = label(dragHandle, "DH PREDICTION LAB", 17)
	title.Font, title.TextColor3 = Enum.Font.GothamBold, COLORS.accent
	self.minimize = button(header, "−", { Name = "Minimize", TextSize = 20,
		Size = UDim2.fromOffset(32, 29), Position = UDim2.new(1, -105, 0, 12) })
	local hide = button(header, "↓", { Name = "Hide", TextSize = 18,
		Size = UDim2.fromOffset(32, 29), Position = UDim2.new(1, -69, 0, 12) })
	local close = button(header, "×", { Name = "Close", TextSize = 20,
		Size = UDim2.fromOffset(32, 29), Position = UDim2.new(1, -32, 0, 12) })
	self.restore = button(self.gui, "SHOW DH LAB", { Name = "RestoreMenu",
		BackgroundColor3 = COLORS.accent, Size = UDim2.fromOffset(142, 34),
		Position = UDim2.new(0, 12, 1, -46), Visible = false })
	self.tabStrip = make("Frame", { BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 54), Size = UDim2.new(1, -32, 0, 32) }, self.panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, self.tabStrip)
	self.content = make("Frame", { BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 99), Size = UDim2.new(1, -36, 0, HEIGHT - 188) }, self.panel)
	for index, name in ipairs({ "MAIN", "PREDICTION", "WEAPONS", "DIAGNOSTICS", "SETTINGS" }) do
		local tab = button(self.tabStrip, name, { Name = name, TextSize = 10,
			Size = UDim2.new(0.2, -4, 1, 0), LayoutOrder = index })
		local page = make("ScrollingFrame", { Name = name, BackgroundTransparency = 1,
			BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
			ScrollBarImageColor3 = COLORS.accent, ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false }, self.content)
		make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, page)
		self.pages[name], self.tabs[name] = page, tab
		self:_connect(tab.Activated, function() self:_showPage(name) end)
	end

	local main = self.pages.MAIN
	self:_toggle(main, "Enable", "core.enabled")
	self:_dropdown(main, "AimType", "core.memoryTracking", {
		{ label = "Memory", value = true }, { label = "Velocity", value = false } })
	self:_toggle(main, "Auto Prediction", "core.autoPrediction")
	self:_number(main, "Manual Prediction · active profile (s)", "profile.manualDelaySeconds", 0, 0.6, 3)
	self:_dropdown(main, "Target source", "targetMode", { "Simulated", "OwnCharacters" })
	self:_number(main, "FOV · radius (pixels)", "core.fovPixels", 20, 1000, 0)
	self:_number(main, "Target distance limit (studs)", "core.maxTargetDistanceStuds", 10, 2000, 0)
	self:_toggle(main, "Position Indicators", "core.debugVisualization")
	self:_note(main, "RMB orienta la cámara; F o DISPARAR mide un tiro del laboratorio. Simulated usa objetivos locales; OwnCharacters usa personajes de esta experiencia.")
	self:_section(main, "Live prediction")
	self:_metric(main, "target", "Target")
	self:_metric(main, "delay", "Prediction delay")
	self:_metric(main, "predicted", "Predicted position")
	self:_metric(main, "status", "Runtime status", 42)

	local prediction = self.pages.PREDICTION
	for _, item in ipairs({
		{ "Ping Based Prediction", "pingCompensation" }, { "Velocity Prediction", "core.velocityPrediction" },
		{ "Distance Based Prediction", "core.distancePrediction" }, { "Memory Tracking", "core.memoryTracking" },
		{ "Acceleration Prediction", "core.accelerationPrediction" },
	}) do self:_toggle(prediction, item[1], item[2]) end
	self:_number(prediction, "Prediction Smoothing · τ (s)", "predictionSmoothingSeconds", 0, 1, 3)
	self:_number(prediction, "Ping Smoothing · τ (s)", "core.pingSmoothingSeconds", 0.05, 10, 3)
	self:_number(prediction, "Global latency offset (s)", "core.latencyOffsetSeconds", -0.2, 0.2, 3)
	self:_note(prediction, "Auto usa RTT/2 suavizado y offsets del perfil. Manual usa los segundos del perfil activo. La simulación retrasa observaciones; el suavizado de predicción usa tiempo, no FPS.", 54)
	self:_section(prediction, "Advanced calibration")
	self:_toggle(prediction, "Adaptive Calibration", "adaptiveCalibration")
	self:_metric(prediction, "suggestion", "Measured suggestion", 42)
	self:_button(prediction, "APPLY CALIBRATION SUGGESTION", function()
		local ok, accepted, message = self:_invoke("onApplyCalibration")
		if ok and accepted ~= nil then
			self:setStatus(message or (accepted and "Calibración aplicada." or "Faltan mediciones suficientes."), not accepted)
		end
	end, "ApplyCalibration")
	self:_note(prediction, "La sugerencia se obtiene del error medido para el perfil activo. Los offsets no se ajustan a valores universales por nombre de arma.")

	local weapons = self.pages.WEAPONS
	self:_dropdown(weapons, "Weapon Profile", "activeProfile", { "Revolver", "Default", "Custom" })
	self:_dropdown(weapons, "Physics model", "profile.kind", { "hitscan", "projectile" })
	for _, item in ipairs({
		{ "Manual delay (s)", "manualDelaySeconds", 0, 0.6, 3 },
		{ "Profile latency offset (s)", "latencyOffsetSeconds", -0.2, 0.2, 3 },
		{ "Projectile speed (studs/s)", "speed", 0, 20000, 1 },
		{ "Gravity (studs/s²)", "gravity", 0, 1000, 2 },
		{ "Shot cooldown (s)", "cooldown", 0.01, 10, 3 },
		{ "Spread (radians)", "spreadRadians", 0, math.pi, 4 },
		{ "Projectile radius (studs)", "radius", 0, 20, 2 },
	}) do self:_number(weapons, item[1], "profile." .. item[2], item[3], item[4], item[5]) end
	self:_section(weapons, "Range offsets · seconds")
	for _, range in ipairs({ "close", "medium", "long" }) do
		self:_number(weapons, range, "profile.rangeOffsets." .. range, -0.15, 0.15, 3)
	end
	self:_note(weapons, "Los perfiles conservan ajustes independientes. Revolver, Default y Custom describen supuestos del laboratorio. Hitscan no añade vuelo; projectile usa velocidad y gravedad.", 55)

	local diagnostics = self.pages.DIAGNOSTICS
	for _, item in ipairs({
		{ "rtt", "Current Ping · RTT" }, { "ping", "Estimated one-way / smoothed" },
		{ "delay", "Applied prediction delay" }, { "speed", "Target velocity" },
		{ "distance", "Target distance" }, { "range", "Distance range" },
		{ "current", "Observed position (studs)" }, { "predicted", "Predicted position (studs)" },
		{ "aimpoint", "Aim point (studs)" }, { "flight", "Projectile flight time" },
		{ "weapon", "Active weapon" }, { "error", "Current prediction error" },
		{ "autoRMSE", "Auto RMSE / samples" }, { "manualRMSE", "Manual RMSE / samples" },
		{ "measurementCount", "Measured samples" }, { "hitRate", "Shot hit rate" },
	}) do self:_metric(diagnostics, item[1], item[2]) end
	self:_metric(diagnostics, "status", "Status", 42)
	self:_note(diagnostics, "RMSE compara posiciones predichas con observaciones posteriores del objetivo. Los tiros del laboratorio añaden dispersión; su tasa de aciertos se mide por separado.", 52)
	self:_button(diagnostics, "EXPORT MEASUREMENTS · JSON", function()
		local ok, text = self:_invoke("onExportMeasurements")
		if ok and text ~= nil then self:_showText(text, "Mediciones JSON listas para copiar.") end
	end, "ExportMeasurements")
	self:_button(diagnostics, "CLEAR MEASUREMENTS", function() self:_invoke("onClearMeasurements") end, "ClearMeasurements")

	local settings = self.pages.SETTINGS
	self:_toggle(settings, "Use Simulated Ping", "useSimulatedPing")
	self:_number(settings, "Simulated RTT (ms)", "simulatedRTTMilliseconds", 0, 2000, 1)
	self:_number(settings, "Simulated observation delay (s)", "simulatedObservationDelaySeconds", 0, 0.25, 3)
	self:_number(settings, "Minimum latency (s)", "core.minDelaySeconds", 0, 0.6, 3)
	self:_number(settings, "Maximum latency (s)", "core.maxDelaySeconds", 0, 0.6, 3)
	self:_number(settings, "Updates per second", "core.updateHz", 5, 60, 0)
	self:_button(settings, "SAVE CONFIGURATION · JSON", function()
		local ok, text = self:_invoke("onSave")
		if ok then self:_showText(text, "Configuración JSON lista para copiar y guardar.") end
	end, "SaveConfiguration")
	self:_note(settings, "Copia el JSON para guardarlo. Para cargarlo, pega una configuración en el campo y pulsa LOAD CONFIGURATION. Las mediciones exportadas usan el mismo campo.", 54)
	self.editorRow = self:_row(settings, 190)
	local editorScroll = make("ScrollingFrame", { Name = "JSONScroll", BackgroundColor3 = COLORS.input,
		BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
		ScrollBarImageColor3 = COLORS.accent, ScrollingDirection = Enum.ScrollingDirection.Y,
	}, self.editorRow)
	corner(editorScroll)
	self.editor = make("TextBox", { Name = "PortableJSON", BackgroundTransparency = 1,
		TextColor3 = COLORS.text, BorderSizePixel = 0, ClearTextOnFocus = false,
		MultiLine = true, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.Code, TextSize = 11,
		Text = "", PlaceholderText = "Pega aquí la configuración JSON…",
		PlaceholderColor3 = COLORS.muted, Size = UDim2.new(1, -6, 0, 180),
		AutomaticSize = Enum.AutomaticSize.Y }, editorScroll)
	make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, self.editor)
	self:_button(settings, "LOAD CONFIGURATION", function()
		local ok, accepted, message = self:_invoke("onLoad", self.editor.Text)
		if ok then self:setStatus(message or (accepted and "Configuración cargada." or "JSON no válido."), not accepted) end
	end, "LoadConfiguration")
	self:_button(settings, "RESET CONFIGURATION", function() self:_invoke("onReset") end, "ResetConfiguration")
	self:_button(settings, "HIDE MENU", function() self.panel.Visible = false; self.restore.Visible = true end, "HideMenu")
	self:_button(settings, "UNLOAD · CLEAN UP", function() self:_invoke("onUnload") end, "Unload")

	self.status = label(self.panel, "Preparando DH Prediction Lab…", 11)
	self.status.Position, self.status.Size = UDim2.fromOffset(18, HEIGHT - 78), UDim2.new(1, -36, 0, 24)
	self.status.TextColor3, self.status.TextTruncate = COLORS.muted, Enum.TextTruncate.AtEnd
	self.fireButton = button(self.panel, "DISPARAR  ·  F", { Name = "Fire",
		BackgroundColor3 = COLORS.accent, TextSize = 13,
		Size = UDim2.new(1, -36, 0, 36), Position = UDim2.fromOffset(18, HEIGHT - 48) })
	self:_connect(self.fireButton.Activated, function() self:_invoke("onFire") end)
	self:_connect(self.minimize.Activated, function() self:_setCollapsed(not self.collapsed) end)
	self:_connect(hide.Activated, function() self.panel.Visible = false; self.restore.Visible = true end)
	self:_connect(self.restore.Activated, function() self.panel.Visible = true; self.restore.Visible = false; self:_fit() end)
	self:_connect(close.Activated, function()
		if self.callbacks.onUnload then self:_invoke("onUnload") else self:destroy() end
	end)

	local dragInput, dragStart, startPosition
	self:_connect(dragHandle.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragInput, dragStart, startPosition = input, input.Position, self.panel.Position
		end
	end)
	self:_connect(UserInputService.InputEnded, function(input) if input == dragInput then dragInput = nil end end)
	self:_connect(UserInputService.InputChanged, function(input)
		if dragInput and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput) then
			local delta = input.Position - dragStart
			self.panel.Position = UDim2.fromOffset(startPosition.X.Offset + delta.X, startPosition.Y.Offset + delta.Y)
			self:_fit()
		end
	end)
	self:_connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function() self:_fit() end)
	self:refreshControls()
	self:_showPage("MAIN")
	self:_fit()
	end)
	if not ok then self:destroy(); error("Interfaz: " .. tostring(failure), 2) end
	return self
end
function Interface:isPointerOver()
	if self.destroyed or not self.gui.Enabled then return false end
	local pointer = UserInputService:GetMouseLocation()
	for _, frame in ipairs({ self.panel, self.restore }) do
		if frame.Visible then
			local position, size = frame.AbsolutePosition, frame.AbsoluteSize
			if pointer.X >= position.X and pointer.X <= position.X + size.X
				and pointer.Y >= position.Y and pointer.Y <= position.Y + size.Y then return true end
		end
	end
	return false
end
function Interface:update(live)
	if self.destroyed then return end
	self:_fit()
	if self.pendingEditorScroll then
		local page = self.pages.SETTINGS
		local offset = (self.editorRow.AbsolutePosition.Y - page.AbsolutePosition.Y) / self.scale.Scale + page.CanvasPosition.Y
		page.CanvasPosition = Vector2.new(0, math.max(0, offset))
		self.pendingEditorScroll = false
	end
	for key, value in pairs(live or {}) do
		for _, metric in ipairs(self.metrics[key] or {}) do metric.Text = tostring(value) end
	end
end
function Interface:destroy()
	if self.destroyed then return end
	self.destroyed = true
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	table.clear(self.connections)
	if self.gui then self.gui:Destroy() end
end
return Interface

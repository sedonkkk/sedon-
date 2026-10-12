--!nonstrict
-- Native Roblox UI for this place's simulator. It does not modify another game.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Interface = {}
Interface.__index = Interface

local COLORS = {
	background = Color3.fromRGB(16, 20, 29),
	surface = Color3.fromRGB(23, 29, 40),
	input = Color3.fromRGB(34, 42, 57),
	text = Color3.fromRGB(232, 238, 248),
	muted = Color3.fromRGB(146, 160, 181),
	accent = Color3.fromRGB(88, 211, 191),
	error = Color3.fromRGB(250, 157, 125),
}

local function make(className, properties, parent)
	local instance = Instance.new(className)
	for key, value in pairs(properties) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function corner(parent, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius or 7) }, parent)
end

local function label(parent, text, size)
	return make("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = COLORS.text,
		Font = Enum.Font.Gotham,
		TextSize = size or 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.fromScale(1, 1),
	}, parent)
end

function Interface:_connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(self.connections, connection)
	return connection
end

function Interface:_row(page, height)
	self.order += 1
	return make("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -4, 0, height or 42),
		LayoutOrder = self.order,
	}, page)
end

function Interface:_note(page, text)
	local row = self:_row(page, 52)
	local textLabel = label(row, text, 12)
	textLabel.TextColor3 = COLORS.muted
	textLabel.TextWrapped = true
	textLabel.TextYAlignment = Enum.TextYAlignment.Top
	return textLabel
end

function Interface:_section(page, title)
	local row = self:_row(page, 30)
	local textLabel = label(row, string.upper(title), 11)
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextColor3 = COLORS.accent
end

function Interface:_metric(page, key, title)
	local row = self:_row(page, 28)
	local titleLabel = label(row, title, 12)
	titleLabel.TextColor3 = COLORS.muted
	titleLabel.Size = UDim2.fromScale(0.45, 1)
	local valueLabel = label(row, "—", 12)
	valueLabel.Position = UDim2.fromScale(0.43, 0)
	valueLabel.Size = UDim2.fromScale(0.57, 1)
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
	self.metrics[key] = valueLabel
end

function Interface:_change(key, value)
	local accepted, message = self.callbacks.onChange(key, value)
	if not accepted then
		self:setStatus(message or "Valor no válido.", true)
	else
		self:setStatus("Configuración actualizada.")
	end
	self:refreshControls()
end

function Interface:_toggle(page, title, key)
	local row = self:_row(page)
	local titleLabel = label(row, title)
	titleLabel.Size = UDim2.fromScale(0.75, 1)
	local button = make("TextButton", {
		BackgroundColor3 = COLORS.input,
		Size = UDim2.fromOffset(72, 28),
		Position = UDim2.new(1, -72, 0.5, -14),
		AutoButtonColor = false,
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 11,
	}, row)
	corner(button)
	self:_connect(button.Activated, function()
		self:_change(key, not self.settings[key])
	end)
	self.controls[key] = { kind = "toggle", instance = button }
end

function Interface:_number(page, title, key, minimum, maximum, decimals)
	local row = self:_row(page)
	local titleLabel = label(row, title)
	titleLabel.Size = UDim2.fromScale(0.72, 1)
	local input = make("TextBox", {
		BackgroundColor3 = COLORS.input,
		TextColor3 = COLORS.text,
		ClearTextOnFocus = false,
		Text = "",
		Size = UDim2.fromOffset(92, 30),
		Position = UDim2.new(1, -92, 0.5, -15),
		Font = Enum.Font.Gotham,
		TextSize = 12,
	}, row)
	corner(input)
	self:_connect(input.FocusLost, function()
		local value = tonumber(input.Text)
		if value == nil or value ~= value or value == math.huge or value == -math.huge then
			self:setStatus("Escribe un número finito.", true)
		elseif value < minimum or value > maximum then
			self:setStatus(string.format("Rango permitido: %g a %g.", minimum, maximum), true)
		else
			self:_change(key, value)
		end
		self:refreshControls()
	end)
	self.controls[key] = { kind = "number", instance = input, decimals = decimals or 3 }
end

function Interface:_weaponDropdown(page)
	local row = self:_row(page, 44)
	local titleLabel = label(row, "Weapon Profiles")
	titleLabel.Size = UDim2.fromScale(0.5, 1)
	local button = make("TextButton", {
		BackgroundColor3 = COLORS.input,
		TextColor3 = COLORS.text,
		Text = "",
		Font = Enum.Font.Gotham,
		TextSize = 12,
		Size = UDim2.fromOffset(166, 30),
		Position = UDim2.new(1, -166, 0.5, -15),
		ZIndex = 5,
	}, row)
	corner(button)
	local options = make("Frame", {
		BackgroundColor3 = COLORS.input,
		Size = UDim2.fromOffset(166, 68),
		Position = UDim2.new(1, -166, 0.5, 18),
		Visible = false,
		ZIndex = 6,
	}, row)
	corner(options)
	for index, name in ipairs({ "RevolverLab", "ProjectileLab" }) do
		local option = make("TextButton", {
			BackgroundTransparency = 1,
			TextColor3 = COLORS.text,
			Text = name,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			Size = UDim2.new(1, 0, 0, 32),
			Position = UDim2.fromOffset(0, (index - 1) * 32 + 2),
			ZIndex = 7,
		}, options)
		self:_connect(option.Activated, function()
			options.Visible = false
			self:_change("weapon", name)
		end)
	end
	self:_connect(button.Activated, function()
		options.Visible = not options.Visible
	end)
	self.controls.weapon = { kind = "dropdown", instance = button }
	self.dropdown = options
end

function Interface:refreshControls()
	for key, control in pairs(self.controls) do
		if control.kind == "toggle" then
			local active = self.settings[key] == true
			control.instance.Text = active and "ON" or "OFF"
			control.instance.TextColor3 = active and COLORS.background or COLORS.muted
			control.instance.BackgroundColor3 = active and COLORS.accent or COLORS.input
		elseif control.kind == "number" then
			if not control.instance:IsFocused() then
				local value = self.settings[key]
				local calibrationIndex = tonumber(string.match(key, "^pingCalibration:(%d+)$"))
				if key == "weaponOffset" then
					value = self.settings.weaponOffsets[self.settings.weapon]
				elseif calibrationIndex then
					value = self.settings.pingCalibration[calibrationIndex].offsetSeconds
				end
				control.instance.Text = string.format("%." .. control.decimals .. "f", value)
			end
		else
			control.instance.Text = self.settings[key] .. "  ▾"
		end
	end
end

function Interface:setSettings(settings)
	self.settings = settings
	self:refreshControls()
end

function Interface:setStatus(message, isError)
	if self.destroyed then
		return
	end
	self.status.Text = message
	self.status.TextColor3 = isError and COLORS.error or COLORS.muted
end

function Interface:_showPage(name)
	for pageName, page in pairs(self.pages) do
		page.Visible = pageName == name
		local selected = pageName == name
		self.tabs[pageName].TextColor3 = selected and COLORS.background or COLORS.muted
		self.tabs[pageName].BackgroundColor3 = selected and COLORS.accent or COLORS.surface
	end
	self.dropdown.Visible = false
end

function Interface:_fit()
	local camera = workspace.CurrentCamera
	if camera then
		local viewport = camera.ViewportSize
		self.scale.Scale = math.clamp(math.min((viewport.X - 24) / 500, (viewport.Y - 32) / 580), 0.4, 1)
	end
end

function Interface.new(settings, callbacks)
	local self = setmetatable({
		settings = settings,
		callbacks = callbacks,
		connections = {},
		controls = {},
		metrics = {},
		pages = {},
		tabs = {},
		order = 0,
		destroyed = false,
	}, Interface)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local prior = playerGui:FindFirstChild("AimLabInterface")
	if prior then
		local stop = prior:FindFirstChild("AimLabStop")
		if stop and stop:IsA("BindableEvent") then
			stop:Fire()
		end
		prior:Destroy()
	end
	self.gui = make("ScreenGui", {
		Name = "AimLabInterface",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 20,
	}, playerGui)
	self.stopEvent = make("BindableEvent", { Name = "AimLabStop" }, self.gui)
	self.panel = make("Frame", {
		Name = "Panel",
		BackgroundColor3 = COLORS.background,
		Size = UDim2.fromOffset(500, 580),
		Position = UDim2.fromOffset(18, 48),
		BorderSizePixel = 0,
	}, self.gui)
	corner(self.panel, 12)
	make("UIStroke", { Color = Color3.fromRGB(55, 68, 86), Thickness = 1 }, self.panel)
	self.scale = make("UIScale", {}, self.panel)
	self:_fit()
	local header = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -32, 0, 52),
		Position = UDim2.fromOffset(16, 0),
		Active = true,
	}, self.panel)
	local title = label(header, "AIM LAB  /  SIMULADOR", 16)
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = COLORS.accent
	title.Size = UDim2.new(1, -44, 1, 0)
	local minimize = make("TextButton", {
		BackgroundColor3 = COLORS.input,
		Text = "−",
		TextColor3 = COLORS.text,
		Font = Enum.Font.GothamBold,
		TextSize = 20,
		Size = UDim2.fromOffset(30, 28),
		Position = UDim2.new(1, -30, 0, 12),
	}, header)
	corner(minimize)
	local tabStrip = make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 52),
		Size = UDim2.new(1, -32, 0, 32),
	}, self.panel)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tabStrip)
	local content = make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 98),
		Size = UDim2.new(1, -36, 0, 394),
	}, self.panel)
	local pageNames = { "Main", "Prediction", "Targeting", "Weapons", "Diagnostics", "Settings" }
	for index, name in ipairs(pageNames) do
		local tab = make("TextButton", {
			Name = name,
			BackgroundColor3 = COLORS.surface,
			TextColor3 = COLORS.muted,
			Text = name,
			TextSize = 10,
			Font = Enum.Font.GothamBold,
			Size = UDim2.new(1 / 6, -4, 1, 0),
			LayoutOrder = index,
		}, tabStrip)
		corner(tab, 6)
		local page = make("ScrollingFrame", {
			Name = name,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = COLORS.muted,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false,
		}, content)
		make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, page)
		self.pages[name] = page
		self.tabs[name] = tab
		self:_connect(tab.Activated, function()
			self:_showPage(name)
		end)
	end

	local main = self.pages.Main
	self:_toggle(main, "Aim assistance", "enabled")
	self:_note(main, "Mantén RMB para orientar la cámara. Dispara con F o el botón inferior. Los objetivos son los bots de este laboratorio.")
	self:_section(main, "En vivo")
	self:_metric(main, "target", "Objetivo")
	self:_metric(main, "rtt", "RTT del motor")
	self:_metric(main, "ping", "Ida estimada / suavizada")
	self:_metric(main, "delay", "Latencia de puntería")
	self:_metric(main, "speed", "Velocidad del objetivo")
	self:_metric(main, "distance", "Distancia")
	self:_metric(main, "predicted", "Posición predicha (studs)")
	self:_metric(main, "aimpoint", "Punto de puntería (studs)")
	self:_metric(main, "motion", "Estado de movimiento")
	self:_note(main, "Coloca el cursor sobre el escenario: se retiene el objetivo mientras esté visible y dentro del FOV. El botón de disparo usa la última selección.")

	local prediction = self.pages.Prediction
	self:_toggle(prediction, "Auto Prediction", "autoPrediction")
	self:_number(prediction, "Manual Prediction (s)", "manualDelaySeconds", 0, 0.6, 3)
	self:_number(prediction, "Ping Smoothing (τ, s)", "pingSmoothingSeconds", 0.05, 10, 3)
	self:_toggle(prediction, "Distance Prediction", "distancePrediction")
	self:_toggle(prediction, "Velocity Prediction", "velocityPrediction")
	self:_toggle(prediction, "Acceleration Prediction", "accelerationPrediction")
	self:_toggle(prediction, "Memory Tracking", "memoryTracking")
	self:_metric(prediction, "flight", "Tiempo de vuelo estimado")
	self:_metric(prediction, "horizon", "Horizonte total")
	self:_note(prediction, "τ expresa segundos de suavizado, no un multiplicador de ping. La demora manual se usa al desactivar Auto Prediction.")
	self:_section(prediction, "Calibración por ping")
	for index, point in ipairs(settings.pingCalibration) do
		self:_number(prediction, string.format("Offset a RTT ≈ %.0f ms (s)", point.pingSeconds * 2000),
			"pingCalibration:" .. index, -0.2, 0.2, 3)
	end
	self:_note(prediction, "Se interpolan los offsets entre rangos. Déjalos en cero hasta medir un sesgo repetible; ida estimada = RTT / 2 supone latencia simétrica.")

	local targeting = self.pages.Targeting
	self:_number(targeting, "FOV (radio, píxeles)", "fovPixels", 20, 1000, 0)
	self:_number(targeting, "Distancia máxima (studs)", "maxTargetDistanceStuds", 10, 2000, 0)
	self:_toggle(targeting, "Debug Visualization", "debugVisualization")
	self:_metric(targeting, "selection", "Selección")
	self:_note(targeting, "La selección usa distancia al cursor, visibilidad y alcance. La esfera y el punto de depuración indican la solución predicha; no son la posición real futura.")

	local weapons = self.pages.Weapons
	self:_weaponDropdown(weapons)
	-- This following row leaves room for the expanded two-item menu.
	self:_row(weapons, 48)
	self:_number(weapons, "Offset del perfil activo (s)", "weaponOffset", -0.2, 0.2, 3)
	self:_section(weapons, "Perfil activo")
	self:_metric(weapons, "weaponKind", "Modelo")
	self:_metric(weapons, "weaponSpeed", "Velocidad del proyectil")
	self:_metric(weapons, "weaponSpread", "Dispersión angular")
	self:_metric(weapons, "weaponCooldown", "Intervalo entre disparos")
	self:_metric(weapons, "activeStats", "Aciertos del perfil activo")
	self:_metric(weapons, "activePrediction", "RMSE / muestras del perfil")
	self:_note(weapons, "RevolverLab es hitscan; ProjectileLab simula tiempo de vuelo y la gravedad de su perfil. Los offsets se conservan por arma; el servidor aplica dispersión y valida los tiros.")

	local diagnostics = self.pages.Diagnostics
	self:_metric(diagnostics, "shots", "Disparos / aciertos")
	self:_metric(diagnostics, "hitRate", "Tasa de aciertos")
	self:_metric(diagnostics, "rmse", "RMSE de predicción (studs)")
	self:_metric(diagnostics, "measurementCount", "Muestras de predicción")
	self:_metric(diagnostics, "miss", "Distancia media de fallo")
	self:_metric(diagnostics, "lastShot", "Último disparo")
	self:_metric(diagnostics, "lastSpread", "Dispersión del último tiro")
	self:_metric(diagnostics, "revolverStats", "Revolver: disparos / aciertos")
	self:_metric(diagnostics, "projectileStats", "Projectile: disparos / aciertos")
	self:_note(diagnostics, "La tasa cuenta aciertos en el objetivo elegido y excluye rechazos. RMSE mide la predicción sin dispersión; la distancia de fallo describe los disparos aceptados.")
	local exportRow = self:_row(diagnostics, 38)
	local exportButton = make("TextButton", {
		BackgroundColor3 = COLORS.input,
		TextColor3 = COLORS.text,
		Text = "Export Measurements · Studio Output",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		Size = UDim2.new(1, 0, 0, 34),
	}, exportRow)
	corner(exportButton)
	self:_connect(exportButton.Activated, callbacks.onExport)
	local clearRow = self:_row(diagnostics, 38)
	local clearButton = make("TextButton", {
		BackgroundColor3 = COLORS.input,
		TextColor3 = COLORS.text,
		Text = "Clear Measurements",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		Size = UDim2.new(1, 0, 0, 34),
	}, clearRow)
	corner(clearButton)
	self:_connect(clearButton.Activated, callbacks.onClearMeasurements)

	local settingsPage = self.pages.Settings
	self:_number(settingsPage, "Demora simulada (s)", "simulationDelaySeconds", 0, 0.25, 3)
	self:_number(settingsPage, "Offset de latencia (s)", "latencyOffsetSeconds", -0.2, 0.2, 3)
	self:_number(settingsPage, "Latencia mínima (s)", "minDelaySeconds", 0, 0.6, 3)
	self:_number(settingsPage, "Latencia máxima (s)", "maxDelaySeconds", 0, 0.6, 3)
	self:_number(settingsPage, "Actualizaciones / s", "updateHz", 5, 60, 0)
	self:_note(settingsPage, "La demora simulada retrasa las observaciones del bot, sin alterar el RTT. La edad de cada muestra compensa ese retraso. Los cambios duran esta sesión.")
	local resetRow = self:_row(settingsPage, 38)
	local resetButton = make("TextButton", {
		BackgroundColor3 = COLORS.input,
		TextColor3 = COLORS.text,
		Text = "Reset Settings",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		Size = UDim2.new(1, 0, 0, 34),
	}, resetRow)
	corner(resetButton)
	self:_connect(resetButton.Activated, callbacks.onReset)

	self.status = label(self.panel, "Conectando con el laboratorio…", 11)
	self.status.Position = UDim2.fromOffset(18, 498)
	self.status.Size = UDim2.new(1, -36, 0, 24)
	self.status.TextColor3 = COLORS.muted
	self.status.TextTruncate = Enum.TextTruncate.AtEnd
	local fireButton = make("TextButton", {
		BackgroundColor3 = COLORS.accent,
		TextColor3 = COLORS.background,
		Text = "DISPARAR  ·  F",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		Size = UDim2.new(1, -36, 0, 36),
		Position = UDim2.fromOffset(18, 530),
	}, self.panel)
	corner(fireButton)
	self:_connect(fireButton.Activated, callbacks.onFire)
	self:_connect(minimize.Activated, function()
		self.collapsed = not self.collapsed
		content.Visible = not self.collapsed
		tabStrip.Visible = not self.collapsed
		self.status.Visible = not self.collapsed
		fireButton.Visible = not self.collapsed
		self.panel.Size = UDim2.fromOffset(500, self.collapsed and 52 or 580)
		minimize.Text = self.collapsed and "+" or "−"
	end)

	local dragInput, dragStart, startPosition
	self:_connect(header.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
			dragStart = input.Position
			startPosition = self.panel.Position
		end
	end)
	self:_connect(UserInputService.InputEnded, function(input)
		if input == dragInput then
			dragInput = nil
		end
	end)
	self:_connect(UserInputService.InputChanged, function(input)
		if dragInput and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput) then
			local delta = input.Position - dragStart
			local camera = workspace.CurrentCamera
			local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
			self.panel.Position = UDim2.fromOffset(
				math.clamp(startPosition.X.Offset + delta.X, 0, math.max(0, viewport.X - self.panel.AbsoluteSize.X)),
				math.clamp(startPosition.Y.Offset + delta.Y, 0, math.max(0, viewport.Y - self.panel.AbsoluteSize.Y))
			)
		end
	end)
	self:_connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
		self:_fit()
	end)
	self:refreshControls()
	self:_showPage("Main")
	return self
end

function Interface:isPointerOver()
	local mouse = UserInputService:GetMouseLocation()
	local position = self.panel.AbsolutePosition
	local size = self.panel.AbsoluteSize
	return mouse.X >= position.X and mouse.X <= position.X + size.X
		and mouse.Y >= position.Y and mouse.Y <= position.Y + size.Y
end

function Interface:update(live)
	if self.destroyed then
		return
	end
	self:_fit()
	for key, value in pairs(live) do
		local metric = self.metrics[key]
		if metric then
			metric.Text = tostring(value)
		end
	end
end

function Interface:destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.gui:Destroy()
end

return Interface

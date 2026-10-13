--!nonstrict
-- Reuse the existing elapsed-time fade without adding tweens or input handlers.
local Overlay = if script then require(script.Parent.Parent.pink.Overlay) else require("../pink/Overlay")
local Branding = if script then require(script.Parent.Branding) else require("./Branding")
local NotificationSystem = {}
NotificationSystem.__index = NotificationSystem
local FADE_SECONDS, MIN_VISIBLE_SECONDS, MAX_PENDING = 0.18, 0.6, 4
local MIN_EVENT_DURATION = MIN_VISIBLE_SECONDS + 2 * FADE_SECONDS

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function NotificationSystem.new(playerGui, config)
	local self = setmetatable({destroyed = false, queue = {},recent={},connections={},config=config}, NotificationSystem)
	local ok, problem = pcall(function()
		self.overlay = Overlay.new(playerGui, {ShowDot = false, DotOutline = false,
			ShowNotifications = not config or config.ShowNotifications ~= false, NotificationDuration = 2})
		local overlay, colors = self.overlay, Branding.Colors
		self.gui, self.toast, self.title, self.body = overlay.gui, overlay.toast, overlay.title, overlay.body
		self.gui.Name = "SedwareCamLock_Notifications"
		-- The previous display-only overlay owns a dot; remove its inert instance
		-- for this camera variant while leaving the original module unchanged.
		overlay.dot:Destroy()
		self.toast.Name = "CamLockNotification"
		self.toast.BackgroundColor3 = colors.Background
		self.toast.BackgroundTransparency = 0.05
		self.toast.Size = UDim2.new(0.85, 0, 0, 58)
		local limit = self.toast:FindFirstChildOfClass("UISizeConstraint")
		if limit then limit.MaxSize = Vector2.new(284, 58) end
		local corner = self.toast:FindFirstChildOfClass("UICorner")
		if corner then corner.CornerRadius = UDim.new(0, 4) end
		local accent = self.toast:FindFirstChild("PinkAccent")
		if accent then accent.BackgroundColor3 = colors.Neon end
		self.logo = Branding.addLogo(self.toast, function(className, properties, parent)
			local instance = Instance.new(className)
			table.insert(overlay.owned, instance)
			for key, value in pairs(properties) do instance[key] = value end
			instance.Parent = parent
			return instance
		end, UDim2.fromOffset(15, 15), UDim2.fromOffset(23, 26), 7,config,function(signal,callback)
   local connection=signal:Connect(callback);table.insert(self.connections,connection);return connection
  end)
		self.title.TextColor3 = colors.White
		self.title.TextSize = 13
		self.body.TextColor3 = colors.Pink
		self.body.TextSize = 11
		self.body.TextWrapped = false
		self.body.TextTruncate = Enum.TextTruncate.AtEnd
	end)
	if not ok then self:destroy(); error("SEDWARE Cam Lock notifications: " .. tostring(problem), 2) end
	return self
end

function NotificationSystem:_show(notice, now)
	local duration = notice.duration
	if not notice.welcome and #self.queue > 0 then duration = math.min(duration, MIN_EVENT_DURATION) end
	local accepted = self.overlay:notify(Branding.Title, now, duration, notice.subtitle)
	if not accepted then return false end
	notice.startedAt, notice.duration = now, duration
	self.current = notice
	self.title.Position, self.title.Size = UDim2.fromOffset(49, 7), UDim2.new(1, -62, 0, 23)
	self.body.Position, self.body.Size = UDim2.fromOffset(49, 30), UDim2.new(1, -62, 0, 20)
	return true
end

function NotificationSystem:notify(subtitle, now, duration)
	if self.destroyed or not finite(now) then return false end
	subtitle = tostring(subtitle or "")
	local welcome = subtitle == "Successfully Loaded"
	duration = duration or (welcome and 3 or 2)
	if not finite(duration) or duration <= 0 then return false end
	-- Search outcomes never enter the notification pipeline. Events are deduped
	-- against active/pending messages and have a bounded recent-message cache.
 if subtitle:find("No valid target",1,true) then return false end
 local state=if subtitle=="Lock Enabled" then "ON" elseif subtitle=="Lock Disabled" then "OFF" else nil
 if state and self.lockState~=state then
  self.lockState=state;self.recent[subtitle]=nil
  if state=="ON" and self.current and self.current.subtitle=="Lock Disabled" then
   self.current=nil;self.overlay.noticeStart=nil;table.clear(self.queue)
  end
 end
 if self.current and self.current.subtitle==subtitle then return false end
 for _,pending in self.queue do if pending.subtitle==subtitle then return false end end
 local cooldown=self.config.NotificationCooldown or 3
 if self.recent[subtitle] and now-self.recent[subtitle]<cooldown then return false end
 local count=0
 for message,time in self.recent do
  if now-time>=cooldown then self.recent[message]=nil else count+=1 end
 end
 if count>=32 then table.clear(self.recent) end
 self.recent[subtitle]=now
	if self.overlay.config.ShowNotifications == false then
		self.current = nil
		table.clear(self.queue)
		return self.overlay:notify(Branding.Title, now, duration, subtitle)
	end
	local notice = {subtitle = subtitle, duration = welcome and duration or math.max(duration, MIN_EVENT_DURATION), welcome = welcome}
	-- OFF is an immediate state correction. Pending lock notices must never
	-- reappear after the camera has already been released.
	if subtitle == "Lock Disabled" then
		table.clear(self.queue)
		self.current = nil
		return self:_show(notice, now)
	end
	-- Remove stale acquisition events before step can promote a pending toast.
	if subtitle == "Target Lost" then
		for index = #self.queue, 1, -1 do
			if self.queue[index].subtitle == "Target Locked" then table.remove(self.queue, index) end
		end
	end
	self:step(now)
	if not self.current then return self:_show(notice, now) end
	if #self.queue == MAX_PENDING then table.remove(self.queue, 1) end
	table.insert(self.queue, notice)
	local current = self.current
	-- Welcome retains its full configured duration. Other messages yield soon
	-- while still allowing 0.6 seconds at full opacity plus both existing fades.
	if not current.welcome then
		current.duration = math.min(current.duration,
			math.max(MIN_EVENT_DURATION, now - current.startedAt + FADE_SECONDS))
		self.overlay.noticeDuration = current.duration
	end
	return true
end
function NotificationSystem:step(now)
	if self.destroyed or not finite(now) then return end
	self.overlay:step(now)
	if self.overlay.config.ShowNotifications == false then
		self.current = nil
		table.clear(self.queue)
		return
	end
	if self.current and now - self.current.startedAt < self.current.duration then return end
	self.current = nil
	if #self.queue > 0 then
		-- Start at the observed frame time; a long frame cannot consume unseen
		-- events or skip through the queue before the user gets to see them.
		self:_show(table.remove(self.queue, 1), now)
		self.overlay:step(now)
	end
end
function NotificationSystem:destroy()
	if self.destroyed then return end
	self.destroyed = true
	self.current = nil
	table.clear(self.queue)
	table.clear(self.recent)
 for _,connection in self.connections do connection:Disconnect() end;table.clear(self.connections)
	if self.overlay then self.overlay:destroy() end
end
function NotificationSystem:setLogo(asset) Branding.setLogo(self.logo,asset) end

return NotificationSystem

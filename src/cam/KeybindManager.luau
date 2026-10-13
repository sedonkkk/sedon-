--!nonstrict
local Config=if script then require(script.Parent.Config) else require("./Config")
local Cleanup=if script then require(script.Parent.Cleanup) else require("./Cleanup")
local KeybindManager={}
KeybindManager.__index=KeybindManager
function KeybindManager.new(config,input,callbacks)
 local self=setmetatable({config=config,input=input,callbacks=callbacks,keys={},cleanup=Cleanup.new(),destroyed=false},KeybindManager)
 local ok,problem=pcall(function()
  self.cleanup:connect(input.InputBegan,function(event,processed) self:_began(event,processed) end)
  self.cleanup:connect(input.InputEnded,function(event) if event.KeyCode then self.keys[event.KeyCode]=nil end end)
  self.cleanup:connect(input.WindowFocusReleased,function() self:clear();self:cancelCapture() end)
  self.cleanup:connect(input.TextBoxFocused,function() self:clear();self:cancelCapture() end)
 end)
 if not ok then self:destroy();error(problem,2) end
 return self
end
function KeybindManager:capture(field)
 if field~="FlyKeybind" and field~="SpeedKeybind" then return false,"Unsupported keybind field" end
 self:cancelCapture();self:clear();self.capturing=field;self.callbacks.capture(field,true);return true
end
function KeybindManager:cancelCapture()
 local field=self.capturing;self.capturing=nil
 if field then self.callbacks.capture(field,false) end
end
function KeybindManager:clear() table.clear(self.keys) end
function KeybindManager:_began(event,processed)
 if self.destroyed or processed or self.input:GetFocusedTextBox() then return end
 local key=event.KeyCode
 if key==nil or key==Enum.KeyCode.Unknown then return end
 if self.capturing then
  if key==Enum.KeyCode.Escape then self:cancelCapture();return end
  local field=self.capturing
  local ok,reason=self.callbacks.change(field,key)
  if ok then self:cancelCapture() else self.callbacks.notice(reason) end
  return
 end
 self.keys[key]=true
 if key==self.config.LockKey then self.callbacks.lock()
 elseif key==self.config.FlyKeybind then self.callbacks.toggle("Fly")
 elseif key==self.config.SpeedKeybind then self.callbacks.toggle("Speed") end
end
function KeybindManager:movement()
 if self.capturing or self.input:GetFocusedTextBox() then return {} end
 return {W=self.keys[Enum.KeyCode.W],A=self.keys[Enum.KeyCode.A],S=self.keys[Enum.KeyCode.S],D=self.keys[Enum.KeyCode.D],
  up=self.keys[self.config.FlyUpKey],down=self.keys[self.config.FlyDownKey]}
end
function KeybindManager:destroy()
 if self.destroyed then return end
 self.destroyed=true;self:cancelCapture();self:clear();self.cleanup:destroy()
end
return KeybindManager

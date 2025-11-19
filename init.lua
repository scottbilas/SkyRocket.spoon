local function scriptPath()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end

local SkyRocket = {}

SkyRocket.author = "David Balatero <d@balatero.com>"
SkyRocket.homepage = "https://github.com/dbalatero/SkyRocket.spoon"
SkyRocket.license = "MIT"
SkyRocket.name = "SkyRocket"
SkyRocket.version = "1.0.2"
SkyRocket.spoonPath = scriptPath()

-- Usage:
--   resizer = SkyRocket:new({
--     moveColor = { red = 0, green = 0, blue = 0, alpha = 0.3 },
--     resizeEdgeColor = { red = 0.2, green = 0.4, blue = 0.8, alpha = 0.3 },
--     resizeCornerColor = { red = 0.2, green = 0.7, blue = 0.5, alpha = 0.3 },
--     moveModifiers = {'cmd', 'shift'},
--     moveMouseButton = 'left',
--     resizeModifiers = {'ctrl', 'shift'}
--     resizeMouseButton = 'left',
--     regionRatio = 1/3,  -- size (as ratio) of edges for 9-slice resizing vs move
--     focusWindowOnClick = false,
--     printWindowInfo = true,
--     disabledApps = {
--       'com.apple.finder',  -- simple string (defaults to 'block' action)
--       { bundleID = 'us.zoom.xos', title = 'Annotation - Zoom', action = 'block' },  -- blocks the click
--       { bundleID = 'us.zoom.xos', title = 'zoom share statusbar window', action = 'passthrough' },  -- ignores window, tries next
--     },
--   })
--
function SkyRocket:new(options)
  options = options or {}
  options.moveColor = options.moveColor or { red = 0, green = 0, blue = 0, alpha = 0.3 }
  options.resizeEdgeColor = options.resizeEdgeColor or { red = 0.2, green = 0.4, blue = 0.8, alpha = 0.3 }
  options.resizeCornerColor = options.resizeCornerColor or { red = 0.2, green = 0.7, blue = 0.5, alpha = 0.3 }
  options.moveModifiers = options.moveModifiers or {'cmd', 'shift'}
  options.moveMouseButton = options.moveMouseButton or 'left'
  options.resizeModifiers = options.resizeModifiers or {'ctrl', 'shift'}
  options.resizeMouseButton = options.resizeMouseButton or 'left'
  options.regionRatio = options.regionRatio or 1/3
  options.focusWindowOnClick = options.focusWindowOnClick or false
  options.printWindowInfo = options.printWindowInfo or false
  options.disabledApps = options.disabledApps or {}

  local function buttonNameToEventType(name, optionName)
    if name == 'left'  then return hs.eventtap.event.types.leftMouseDown  end
    if name == 'right' then return hs.eventtap.event.types.rightMouseDown end
    error(optionName .. ': only "left" and "right" mouse button supported, got ' .. name)
  end

  local resizer = {
    options = options,
    dragType = nil,
    windowCanvas = nil,
    moveStartMouseEvent = buttonNameToEventType(options.moveMouseButton, 'moveMouseButton'),
    resizeStartMouseEvent = buttonNameToEventType(options.resizeMouseButton, 'resizeMouseButton'),
    targetWindow = nil,
  }

  setmetatable(resizer, self)
  self.__index = self

  resizer.clickHandler = hs.eventtap.new(
    {
      hs.eventtap.event.types.leftMouseDown,
      hs.eventtap.event.types.rightMouseDown,
    },
    resizer:handleClick()
  )

  resizer.cancelHandler = hs.eventtap.new(
    {
      hs.eventtap.event.types.leftMouseUp,
      hs.eventtap.event.types.rightMouseUp,
    },
    resizer:handleCancel()
  )

  resizer.dragHandler = hs.eventtap.new(
    {
      hs.eventtap.event.types.leftMouseDragged,
      hs.eventtap.event.types.rightMouseDragged,
    },
    resizer:handleDrag()
  )

  resizer.clickHandler:start()

  return resizer
end

function SkyRocket:stop()
  self.dragType = nil

  self.windowCanvas:hide()
  self.cancelHandler:stop()
  self.dragHandler:stop()
  self.clickHandler:start()
end

local dragTypes = {
  move = 1,
  resize_left = 2,
  resize_right = 3,
  resize_top = 4,
  resize_bottom = 5,
  resize_topleft = 6,
  resize_topright = 7,
  resize_bottomleft = 8,
  resize_bottomright = 9,
}

-- determine 9-slice region
local function getDragRegion(window, mousePos, regionRatio)
  local frame = window:frame()
  local x, y, w, h = frame.x, frame.y, frame.w, frame.h
  local mx, my = mousePos.x, mousePos.y

  local edgeW = w * regionRatio
  local edgeH = h * regionRatio
  local centerLeft = x + edgeW
  local centerRight = x + w - edgeW
  local centerTop = y + edgeH
  local centerBottom = y + h - edgeH

  local inCenterX = mx >= centerLeft and mx <= centerRight
  local inCenterY = my >= centerTop and my <= centerBottom

  if inCenterX and inCenterY then
    return dragTypes.move
  end
  if mx < centerLeft and my < centerTop then return dragTypes.resize_topleft end
  if mx > centerRight and my < centerTop then return dragTypes.resize_topright end
  if mx < centerLeft and my > centerBottom then return dragTypes.resize_bottomleft end
  if mx > centerRight and my > centerBottom then return dragTypes.resize_bottomright end
  if mx < centerLeft then return dragTypes.resize_left end
  if mx > centerRight then return dragTypes.resize_right end
  if my < centerTop then return dragTypes.resize_top end
  if my > centerBottom then return dragTypes.resize_bottom end
  return dragTypes.move -- fallback
end

function SkyRocket:isResizing()
  return self.dragType ~= dragTypes.move
end

function SkyRocket:isMoving()
  return self.dragType == dragTypes.move
end

function SkyRocket:handleDrag()
  return function(event)
    if not self.dragType then return nil end

    local dx = event:getProperty(hs.eventtap.event.properties.mouseEventDeltaX)
    local dy = event:getProperty(hs.eventtap.event.properties.mouseEventDeltaY)
    local current = self.windowCanvas:topLeft()
    local currentSize = self.windowCanvas:size()

    if self.dragType == dragTypes.move then
      self.windowCanvas:topLeft({
        x = current.x + dx,
        y = current.y + dy,
      })
      return true
    elseif self.dragType == dragTypes.resize_left then
      self.windowCanvas:topLeft({ x = current.x + dx, y = current.y })
      self.windowCanvas:size({ w = currentSize.w - dx, h = currentSize.h })
      return true
    elseif self.dragType == dragTypes.resize_right then
      self.windowCanvas:size({ w = currentSize.w + dx, h = currentSize.h })
      return true
    elseif self.dragType == dragTypes.resize_top then
      self.windowCanvas:topLeft({ x = current.x, y = current.y + dy })
      self.windowCanvas:size({ w = currentSize.w, h = currentSize.h - dy })
      return true
    elseif self.dragType == dragTypes.resize_bottom then
      self.windowCanvas:size({ w = currentSize.w, h = currentSize.h + dy })
      return true
    elseif self.dragType == dragTypes.resize_topleft then
      self.windowCanvas:topLeft({ x = current.x + dx, y = current.y + dy })
      self.windowCanvas:size({ w = currentSize.w - dx, h = currentSize.h - dy })
      return true
    elseif self.dragType == dragTypes.resize_topright then
      self.windowCanvas:topLeft({ x = current.x, y = current.y + dy })
      self.windowCanvas:size({ w = currentSize.w + dx, h = currentSize.h - dy })
      return true
    elseif self.dragType == dragTypes.resize_bottomleft then
      self.windowCanvas:topLeft({ x = current.x + dx, y = current.y })
      self.windowCanvas:size({ w = currentSize.w - dx, h = currentSize.h + dy })
      return true
    elseif self.dragType == dragTypes.resize_bottomright then
      self.windowCanvas:size({ w = currentSize.w + dx, h = currentSize.h + dy })
      return true
    else
      return nil
    end
  end
end

function SkyRocket:handleCancel()
  return function()
    if not self.dragType then return end

    if self:isResizing() then
      self:resizeWindowToCanvas()
    else
      self:moveWindowToCanvas()
    end

    self:stop()
  end
end

function SkyRocket:resizeCanvasToWindow()
  local position = self.targetWindow:topLeft()
  local size = self.targetWindow:size()

  self.windowCanvas:topLeft({ x = position.x, y = position.y })
  self.windowCanvas:size({ w = size.w, h = size.h })
end

function SkyRocket:resizeWindowToCanvas()
  if not self.targetWindow then return end
  if not self.windowCanvas then return end

  local size = self.windowCanvas:size()
  local pos = self.windowCanvas:topLeft()
  -- For left/top/corners, move window as well as resize
  if self.dragType == dragTypes.resize_left or self.dragType == dragTypes.resize_top or
     self.dragType == dragTypes.resize_topleft or self.dragType == dragTypes.resize_topright or
     self.dragType == dragTypes.resize_bottomleft then
    self.targetWindow:move(hs.geometry.new({x = pos.x, y = pos.y, w = size.w, h = size.h}), nil, false, 0)
  else
    self.targetWindow:setSize(size.w, size.h)
  end
end

function SkyRocket:moveWindowToCanvas()
  if not self.targetWindow then return end
  if not self.windowCanvas then return end

  local frame = self.windowCanvas:frame()
  local point = self.windowCanvas:topLeft()

  local moveTo = {
    x = point.x,
    y = point.y,
    w = frame.w,
    h = frame.h,
  }

  self.targetWindow:move(hs.geometry.new(moveTo), nil, false, 0)
end

function SkyRocket:createResizeCanvas()
  local color
  if self.dragType == dragTypes.move then
    color = self.options.moveColor
  elseif self.dragType == dragTypes.resize_left or self.dragType == dragTypes.resize_right or self.dragType == dragTypes.resize_top or self.dragType == dragTypes.resize_bottom then
    color = self.options.resizeEdgeColor
  else
    color = self.options.resizeCornerColor
  end
  local canvas = hs.canvas.new{}
  canvas:insertElement(
    {
      id = 'opaque_layer',
      action = 'fill',
      type = 'rectangle',
      fillColor = color,
      roundedRectRadii = { xRadius = 5.0, yRadius = 5.0 },
    },
    1
  )
  return canvas
end

local function matchesDisabledApp(window, disabledAppEntry)
  local app = window:application()
  if type(disabledAppEntry) == "string" then
    return app and (app:bundleID() == disabledAppEntry or app:name() == disabledAppEntry)
  end
  if type(disabledAppEntry) == "table" then
    if disabledAppEntry.bundleID and (not app or app:bundleID() ~= disabledAppEntry.bundleID) then return false end
    if disabledAppEntry.name     and (not app or app:name()     ~= disabledAppEntry.name)     then return false end
    if disabledAppEntry.title    and window:title()             ~= disabledAppEntry.title     then return false end
    if disabledAppEntry.subrole  and window:subrole()           ~= disabledAppEntry.subrole   then return false end
    if disabledAppEntry.role     and window:role()              ~= disabledAppEntry.role      then return false end
    return true
  end
  return false
end

local function getWindowUnderMouse(disabledApps)
  -- Invoke `hs.application` because `hs.window.orderedWindows()` doesn't do it
  -- and breaks itself
  local _ = hs.application

  local my_pos = hs.geometry.new(hs.mouse.absolutePosition())
  local my_screen = hs.mouse.getCurrentScreen()

  -- Find all windows under mouse, checking disabled apps with passthrough action
  for _, w in ipairs(hs.window.orderedWindows()) do
    if my_screen == w:screen() and my_pos:inside(w:frame()) then
      -- Check if this window should be skipped (passthrough)
      local shouldSkip = false
      for _, disabledAppEntry in pairs(disabledApps or {}) do
        if matchesDisabledApp(w, disabledAppEntry) then
          local action = type(disabledAppEntry) == "table" and disabledAppEntry.action or 'block'
          if action == 'passthrough' then
            shouldSkip = true
            break
          end
        end
      end
      
      if not shouldSkip then
        return w
      end
    end
  end
  
  return nil
end

function SkyRocket:handleClick()
  return function(event)
    if self.dragType then return true end

    local flags = event:getFlags()
    local eventType = event:getType()
    local isActive =
      (eventType == self.moveStartMouseEvent and flags:containExactly(self.options.moveModifiers)) or
      (eventType == self.resizeStartMouseEvent and flags:containExactly(self.options.resizeModifiers))

    if isActive then
  local currentWindow = getWindowUnderMouse(self.options.disabledApps)

  if self.options.printWindowInfo and currentWindow then
        local app = currentWindow:application()
        print("=== Window detected ===")
        print("Title:", currentWindow:title())
        print("Role:", currentWindow:role())
        print("Subrole:", currentWindow:subrole())
        if app then
          print("Bundle ID:", app:bundleID())
          print("App Name:", app:name())
        end
        print("======================")
      end

      if currentWindow then
        for _, disabledAppEntry in pairs(self.options.disabledApps) do
          if matchesDisabledApp(currentWindow, disabledAppEntry) then
            local action = type(disabledAppEntry) == "table" and disabledAppEntry.action or 'block'
            if action == 'block' then
              return true  -- eat the click
            end
          end
        end
      end
      if not currentWindow then
        return nil
      end

      local mousePos = hs.mouse.absolutePosition()
      if eventType == self.moveStartMouseEvent and flags:containExactly(self.options.moveModifiers) then
        self.dragType = dragTypes.move
      else
        self.dragType = getDragRegion(currentWindow, mousePos, self.options.regionRatio)
      end
      self.windowCanvas = self:createResizeCanvas()
      self.targetWindow = currentWindow

      self:resizeCanvasToWindow()
      self.windowCanvas:show()

      self.cancelHandler:start()
      self.dragHandler:start()
      self.clickHandler:stop()

      if self.options.focusWindowOnClick then
        currentWindow:focus()
      end
      return true
    else
      return nil
    end
  end
end

return SkyRocket

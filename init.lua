local function scriptPath()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end

local MoonRocket = {}

MoonRocket.author = "Scott Bilas"
MoonRocket.homepage = "https://github.com/scottbilas/MoonRocket"
MoonRocket.license = "MIT"
MoonRocket.name = "MoonRocket"
MoonRocket.version = "2"
MoonRocket.spoonPath = scriptPath()

-- Derived from SkyRocket.spoon by David Balatero.

-- Usage:
--   resizer = MoonRocket:new({
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
function MoonRocket:new(options)
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
    moveStartMouseEvent = buttonNameToEventType(options.moveMouseButton, 'moveMouseButton'),
    previewCanvases = nil,
    previewFrame = nil,
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

function MoonRocket:stop()
  self.dragType = nil
  self.previewFrame = nil

  for _, previewCanvas in ipairs(self.previewCanvases or {}) do
    previewCanvas.canvas:hide()
  end
  self.previewCanvases = nil
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

function MoonRocket:isResizing()
  return self.dragType ~= dragTypes.move
end

function MoonRocket:isMoving()
  return self.dragType == dragTypes.move
end

function MoonRocket:handleDrag()
  return function(event)
    if not self.dragType then return nil end

    -- Hammerspoon already reports mouse deltas in desktop points. Applying a
    -- display scale again makes Retina drags move the preview at half speed.
    if self.dragType == dragTypes.move then
      local dx = event:getProperty(hs.eventtap.event.properties.mouseEventDeltaX)
      local dy = event:getProperty(hs.eventtap.event.properties.mouseEventDeltaY)
      local currentFrame = self.previewFrame
      local frame = {
        x = currentFrame.x,
        y = currentFrame.y,
        w = currentFrame.w,
        h = currentFrame.h,
      }

      frame.x = frame.x + dx
      frame.y = frame.y + dy
      self.previewFrame = frame
    else
      -- Absolute mouse coordinates use a different vertical orientation from Canvas frames.
      -- Resizing must therefore remain incremental, rather than using drag-start coordinates.
      local dx = event:getProperty(hs.eventtap.event.properties.mouseEventDeltaX)
      local dy = event:getProperty(hs.eventtap.event.properties.mouseEventDeltaY)
      local currentFrame = self.previewFrame
      local frame = {
        x = currentFrame.x,
        y = currentFrame.y,
        w = currentFrame.w,
        h = currentFrame.h,
      }

      if self.dragType == dragTypes.resize_left then
        frame.x = frame.x + dx
        frame.w = frame.w - dx
      elseif self.dragType == dragTypes.resize_right then
        frame.w = frame.w + dx
      elseif self.dragType == dragTypes.resize_top then
        frame.y = frame.y + dy
        frame.h = frame.h - dy
      elseif self.dragType == dragTypes.resize_bottom then
        frame.h = frame.h + dy
      elseif self.dragType == dragTypes.resize_topleft then
        frame.x = frame.x + dx
        frame.y = frame.y + dy
        frame.w = frame.w - dx
        frame.h = frame.h - dy
      elseif self.dragType == dragTypes.resize_topright then
        frame.y = frame.y + dy
        frame.w = frame.w + dx
        frame.h = frame.h - dy
      elseif self.dragType == dragTypes.resize_bottomleft then
        frame.x = frame.x + dx
        frame.w = frame.w - dx
        frame.h = frame.h + dy
      elseif self.dragType == dragTypes.resize_bottomright then
        frame.w = frame.w + dx
        frame.h = frame.h + dy
      else
        return nil
      end

      self.previewFrame = frame
    end

    self:updatePreviewCanvases()
    return true
  end
end

function MoonRocket:handleCancel()
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

function MoonRocket:resizeCanvasToWindow()
  local frame = self.targetWindow:frame()
  self.previewFrame = { x = frame.x, y = frame.y, w = frame.w, h = frame.h }
  self.previewCanvases = self:createResizeCanvases()

  self:updatePreviewCanvases()
end

function MoonRocket:resizeWindowToCanvas()
  if not self.targetWindow then return end
  if not self.previewFrame then return end

  self.targetWindow:move(hs.geometry.new(self.previewFrame), nil, false, 0)
end

function MoonRocket:moveWindowToCanvas()
  if not self.targetWindow then return end
  if not self.previewFrame then return end

  self.targetWindow:move(hs.geometry.new(self.previewFrame), nil, false, 0)
end

local function intersectFrames(first, second)
  local left = math.max(first.x, second.x)
  local top = math.max(first.y, second.y)
  local right = math.min(first.x + first.w, second.x + second.w)
  local bottom = math.min(first.y + first.h, second.y + second.h)

  if right <= left or bottom <= top then return nil end

  return { x = left, y = top, w = right - left, h = bottom - top }
end

function MoonRocket:createResizeCanvases()
  local color
  if self.dragType == dragTypes.move then
    color = self.options.moveColor
  elseif self.dragType == dragTypes.resize_left or self.dragType == dragTypes.resize_right or self.dragType == dragTypes.resize_top or self.dragType == dragTypes.resize_bottom then
    color = self.options.resizeEdgeColor
  else
    color = self.options.resizeCornerColor
  end
  local canvases = {}

  -- Keep each Canvas on its native display. Moving a Canvas window between
  -- displays changes its backing scale and makes the preview jump or bounce.
  for _, screen in ipairs(hs.screen.allScreens()) do
    local screenFrame = screen:fullFrame()
    local canvas = hs.canvas.new(screenFrame)
    canvas:insertElement(
      {
        id = 'opaque_layer',
        action = 'fill',
        type = 'rectangle',
        frame = { x = 0, y = 0, w = 0, h = 0 },
        fillColor = color,
        roundedRectRadii = { xRadius = 5.0, yRadius = 5.0 },
      },
      1
    )
    table.insert(canvases, { canvas = canvas, screenFrame = screenFrame })
  end

  return canvases
end

function MoonRocket:updatePreviewCanvases()
  for _, previewCanvas in ipairs(self.previewCanvases) do
    -- previewFrame is global; Canvas element frames are local to each display.
    local intersection = intersectFrames(self.previewFrame, previewCanvas.screenFrame)
    local frame = { x = 0, y = 0, w = 0, h = 0 }

    if intersection then
      frame = {
        x = intersection.x - previewCanvas.screenFrame.x,
        y = intersection.y - previewCanvas.screenFrame.y,
        w = intersection.w,
        h = intersection.h,
      }
    end

    previewCanvas.canvas:elementAttribute(1, 'frame', frame)
  end
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

local function isPassthroughWindow(window, disabledApps)
  for _, disabledAppEntry in pairs(disabledApps or {}) do
    if matchesDisabledApp(window, disabledAppEntry) then
      local action = type(disabledAppEntry) == "table" and disabledAppEntry.action or 'block'
      if action == 'passthrough' then
        return true
      end
    end
  end
  return false
end

-- Fast path: a single accessibility hit-test to find the topmost window under
-- the mouse. This avoids hs.window.orderedWindows(), which enumerates every
-- window of every running app and can take seconds when the system is under
-- heavy load (Unity, Zoom, etc.). That enumeration runs synchronously inside
-- the click event tap, so it is the main cause of the long delay before a drag
-- begins.
local function fastWindowUnderMouse()
  local pos = hs.mouse.absolutePosition()
  local element = hs.axuielement.systemWideElement():elementAtPosition(pos.x, pos.y)

  -- The hit element may be a control deep inside the window; walk up to AXWindow.
  local guard = 0
  while element and guard < 25 do
    if element:attributeValue("AXRole") == "AXWindow" then
      return element:asHSWindow()
    end
    element = element:attributeValue("AXParent")
    guard = guard + 1
  end

  return nil
end

-- Slow path: enumerate every window. Only needed when the topmost window is a
-- 'passthrough' disabled app and we must find the window beneath it.
local function slowWindowUnderMouse(disabledApps)
  -- Invoke `hs.application` because `hs.window.orderedWindows()` doesn't do it
  -- and breaks itself
  local _ = hs.application

  local my_pos = hs.geometry.new(hs.mouse.absolutePosition())
  local my_screen = hs.mouse.getCurrentScreen()

  -- Find all windows under mouse, checking disabled apps with passthrough action
  for _, w in ipairs(hs.window.orderedWindows()) do
    if my_screen == w:screen() and my_pos:inside(w:frame()) then
      if not isPassthroughWindow(w, disabledApps) then
        return w
      end
    end
  end

  return nil
end

local function getWindowUnderMouse(disabledApps)
  local window = fastWindowUnderMouse()

  -- Use the fast result unless it is a passthrough window, in which case we
  -- fall back to the slower enumeration to find the window underneath it.
  if window and not isPassthroughWindow(window, disabledApps) then
    return window
  end

  return slowWindowUnderMouse(disabledApps)
end

function MoonRocket:handleClick()
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
      self.targetWindow = currentWindow

      self:resizeCanvasToWindow()
      self.dragStartMousePosition = mousePos
      for _, previewCanvas in ipairs(self.previewCanvases) do
        previewCanvas.canvas:show()
      end

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

return MoonRocket

# MoonRocket.spoon

This Hammerspoon tool lets you **resize** and **move** windows by clicking + dragging them while holding down modifier keys.

MoonRocket is maintained by Scott Bilas. It retains the MIT license.

## Attribution

MoonRocket is derived from [SkyRocket.spoon](https://github.com/dbalatero/SkyRocket.spoon) by David Balatero. Its original implementation provided the foundation for this Spoon.

## Inspiration

* BetterTouchTool resize/move functions
* Coderage Software's abandoned Zooom/2 software
* Linux desktop move/resize hot keys

## Installation

This tool requires [Hammerspoon](https://www.hammerspoon.org/) to be installed and running.

Place `MoonRocket.spoon` in `~/.hammerspoon/Spoons/`.

## Usage

Once you've installed it, add this to your `~/.hammerspoon/init.lua` file:

```lua
local MoonRocket = hs.loadSpoon("MoonRocket")

moon = MoonRocket:new({
  -- Opacity of resize canvas
  opacity = 0.3,

  -- Which modifiers to hold to move a window?
  moveModifiers = {'cmd', 'shift'},

  -- Which mouse button to hold to move a window?
  moveMouseButton = 'left',

  -- Which modifiers to hold to resize a window?
  resizeModifiers = {'ctrl', 'shift'},

  -- Which mouse button to hold to resize a window?
  resizeMouseButton = 'left',

  -- Should the current window be focused & brought to the front when you click on it?
  focusWindowOnClick = false,
})
```

### Moving

To move a window, hold your `moveModifiers` down, then click `moveMouseButton` and drag a window.

### Resizing

To resize a window, hold your `resizeModifiers` down, then click `resizeMouseButton` and drag a window.

### Disabling move/resize for apps

You can disable move/resize for any app by adding it to the `disabledApps` option:

```lua
moon = MoonRocket:new({
  -- For example, if you run your terminal in full-screen mode you might not
  -- to accidentally resize it:
  disabledApps = {"Alacritty"},
})
```

## Thanks

I took initial inspiration from [this gist](https://gist.github.com/kizzx2/e542fa74b80b7563045a) by @kizzx2, and heavily modified it to be packaged up in this Spoon. I also came up with a different technique for resizing to address the low frame-rate when attempting to resize in real time.

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
  moveModifiers = {'cmd', 'shift'},
  moveMouseButton = 'left',
  resizeModifiers = {'ctrl', 'shift'},
  resizeMouseButton = 'left',
  regionRatio = 1 / 3,
  moveColor = { red = 0, green = 0, blue = 0, alpha = 0.3 },
  resizeEdgeColor = { red = 0.2, green = 0.4, blue = 0.8, alpha = 0.3 },
  resizeCornerColor = { red = 0.2, green = 0.7, blue = 0.5, alpha = 0.3 },
  focusWindowOnClick = false,
})
```

### Moving

To move a window, hold your `moveModifiers` down, then click `moveMouseButton` and drag a window.

### Resizing

To resize a window, hold your `resizeModifiers` down, then click `resizeMouseButton` and drag a window.

## Options

`moveModifiers` and `resizeModifiers` are arrays containing any of `cmd`, `alt`, `ctrl`, `shift`, and `fn`. The modifiers must match exactly. `moveMouseButton` and `resizeMouseButton` accept `left` or `right`.

`regionRatio` controls the nine-slice resize zones. The center region moves the window. The outer portion of each edge and corner resizes it. A value of `1 / 3` leaves the middle third for moving; `0.25` leaves a larger center region.

The preview colors use Hammerspoon color tables with `red`, `green`, `blue`, and `alpha` values from `0` through `1`.

| Option | Default | Effect |
| --- | --- | --- |
| `moveColor` | black at 30% opacity | Preview color while moving. |
| `resizeEdgeColor` | blue at 30% opacity | Preview color while resizing from an edge. |
| `resizeCornerColor` | green at 30% opacity | Preview color while resizing from a corner. |
| `focusWindowOnClick` | `false` | Focuses the target window when a MoonRocket drag begins. |
| `printWindowInfo` | `false` | Prints the matched window's title, role, subrole, bundle ID, and application name to the Hammerspoon Console. |
| `disabledApps` | `{}` | Ignores selected applications or windows. |

### Ignoring applications and windows

`disabledApps` accepts a bundle ID or application name as a string. That shorthand blocks MoonRocket from acting on a matching window.

```lua
disabledApps = {
  "com.apple.finder",
  "Alacritty",
}
```

Use a table when a rule needs to match a particular window. All supplied fields must match. Supported fields are `bundleID`, `name`, `title`, `role`, and `subrole`.

```lua
disabledApps = {
  {
    bundleID = "us.zoom.xos",
    title = "Annotation - Zoom",
    action = "passthrough",
  },
}
```

`action = "block"` is the default. MoonRocket consumes the modified click and leaves that window alone. `action = "passthrough"` skips the matched topmost window and looks for the window underneath it. This is useful for transient overlays such as Zoom's sharing controls.

### Debugging window rules

Set `printWindowInfo = true` temporarily, begin a MoonRocket drag, and inspect the Hammerspoon Console. Use the reported bundle ID, title, role, and subrole to build a `disabledApps` rule.

```lua
moon = MoonRocket:new({
  printWindowInfo = true,
})
```

## Thanks

I took initial inspiration from [this gist](https://gist.github.com/kizzx2/e542fa74b80b7563045a) by @kizzx2, and heavily modified it to be packaged up in this Spoon. I also came up with a different technique for resizing to address the low frame-rate when attempting to resize in real time.

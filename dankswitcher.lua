-- Dank Switcher binds for Hyprland >= 0.55 (Lua config).
-- Load from hyprland.lua with:
--   dofile(os.getenv("HOME") .. "/.config/DankMaterialShell/plugins/dankswitcher/dankswitcher.lua")
-- or paste the lines below into your binds.

-- If SUPER + Tab is already bound (e.g. to next workspace), free it first.
hl.unbind("SUPER + Tab")
hl.unbind("SUPER + SHIFT + Tab")

-- Open / cycle forward. No key repeat: holding Super+Tab opens sticky mode.
hl.bind("SUPER + Tab",         hl.dsp.global("dankswitcher:next"))
-- Cycle backward.
hl.bind("SUPER + SHIFT + Tab", hl.dsp.global("dankswitcher:prev"))

-- Releasing Super confirms the selection. The overlay also sees the release
-- through its keyboard grab; this bind covers a release that lands before the
-- overlay has the keyboard.
hl.bind("SUPER + SUPER_L", hl.dsp.global("dankswitcher:select"), { release = true })
hl.bind("SUPER + SUPER_R", hl.dsp.global("dankswitcher:select"), { release = true })

-- Don't animate the overlay layer in/out.
hl.layer_rule({ match = { namespace = "dankswitcher" }, no_anim = true })

--!strict
-- Settings popup opened from the Settings tile (lobby and match): sound effects and screen
-- shake toggles. Styled as a v2 panel with green/gray toggle buttons.

local Motion = require(script.Parent.Motion)
local Prefs = require(script.Parent.Prefs)
local UI = require(script.Parent.UI)

local SettingsPanel = {}

local V = UI.V2
local panelHolder: GuiObject? = nil

local function build(root: Frame)
	local panel = UI.panel({
		Name = "Settings",
		Size = UDim2.fromOffset(520, 330),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		accent = V.Blue,
		Visible = false,
		Parent = root,
	})
	UI.icon("settings", { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(24, 18), Parent = panel.face })
	UI.text({ Text = "Settings", font = "label", size = 36, Position = UDim2.fromOffset(92, 30), Parent = panel.face })
	UI.button(
		{
			Name = "Close",
			icon = "close",
			style = "red",
			Size = UDim2.fromOffset(56, 56),
			Position = UDim2.new(1, -20, 0, 18),
			AnchorPoint = Vector2.new(1, 0),
			Parent = panel.face,
		},
		function()
			panel.holder.Visible = false
		end
	)
	local rows = { { "Sound effects", "sfx" }, { "Screen shake", "shake" } }
	for i, row in rows do
		local label, key = row[1], row[2]
		local y = 100 + (i - 1) * 96
		UI.text({
			Text = label,
			font = "label",
			size = 24,
			Position = UDim2.fromOffset(32, y + 30),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = panel.face,
		})
		local toggle: TextButton
		toggle = UI.button(
			{
				Name = "Toggle_" .. key,
				Text = "On",
				style = "green",
				Size = UDim2.fromOffset(140, 60),
				Position = UDim2.new(1, -32, 0, y),
				AnchorPoint = Vector2.new(1, 0),
				Parent = panel.face,
			},
			function()
				local prefs = Prefs :: any
				prefs[key] = not prefs[key]
				UI.setButtonText(toggle, if prefs[key] then "On" else "Off")
				UI.setButtonStyle(toggle, if prefs[key] then "green" else "gray")
			end
		)
	end
	return panel.holder
end

function SettingsPanel.toggle(root: Frame)
	if not panelHolder or not panelHolder.Parent then
		panelHolder = build(root)
	end
	local holder = panelHolder :: GuiObject
	if holder.Visible then
		holder.Visible = false
	else
		Motion.popIn(holder, 0.7, 0.3)
	end
end

return SettingsPanel

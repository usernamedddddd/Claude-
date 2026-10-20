--!strict
-- UI kit implementing the Figma "Style v2 (reference)" page:
--   * panels: dark purple gradient, thick bright accent border, hard black drop "lip"
--   * buttons: bright gradient face, white border, black lip; press pushes the face down
--   * labels: heavy UPPERCASE Montserrat, white with a black outline; numbers in Fredoka One
--   * tiles: wide menu tiles (icon + label) and square icon tiles with the label overlapping the
--     bottom edge and an optional red notification badge
--   * a root UIScale: layouts are authored at 1920x1080 and scale to any screen, with a floor
--     that keeps phones readable

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Data.Theme)
local Motion = require(script.Parent.Motion)
local Sound = require(script.Parent.Sound)

local UI = {}

UI.Colors = Theme.Colors
UI.V2 = Theme.V2
UI.LIP = 5

local V = Theme.V2
local WHITE = Color3.new(1, 1, 1)

export type Style = "green" | "red" | "blue" | "gold" | "purple" | "gray"
local STYLES: { [string]: { top: Color3, bottom: Color3 } } = {
	green = { top = V.GreenTop, bottom = V.GreenBottom },
	red = { top = V.RedTop, bottom = V.RedBottom },
	blue = { top = Color3.fromHex("#6FAEFF"), bottom = Color3.fromHex("#1F5FD6") },
	gold = { top = Color3.fromHex("#FFE27A"), bottom = Color3.fromHex("#E59A00") },
	purple = { top = Color3.fromHex("#B98CFF"), bottom = Color3.fromHex("#6A3CCB") },
	gray = { top = Color3.fromHex("#8A8098"), bottom = Color3.fromHex("#4E465E") },
}

---------------------------------------------------------------------------
-- Basics
---------------------------------------------------------------------------

function UI.screen(name: string, displayOrder: number?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder or 0
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

-- Full-screen root authored in 1920x1080 design pixels.
function UI.root(gui: ScreenGui): Frame
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Name = "DesignScale"
	scale.Parent = root
	local function update()
		local camera = Workspace.CurrentCamera
		local height = if camera then camera.ViewportSize.Y else 1080
		-- 1080p = 1.0; phones (~390 px tall) get ~0.62 so tiles stay thumb-sized.
		local s = math.clamp(math.max(height / 1080, math.min(height / 600, 0.62)), 0.45, 2)
		scale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	update()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return root
end

function UI.new(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function UI.corner(parent: Instance, radius: number?): UICorner
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 16), Parent = parent })
end

function UI.stroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return UI.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or V.Outline,
		ApplyStrokeMode = if parent:IsA("TextLabel") or parent:IsA("TextButton")
			then Enum.ApplyStrokeMode.Contextual
			else Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

function UI.aspect(parent: Instance, ratio: number, dominant: Enum.DominantAxis?): UIAspectRatioConstraint
	return UI.new("UIAspectRatioConstraint", {
		AspectRatio = ratio,
		DominantAxis = dominant or Enum.DominantAxis.Width,
		Parent = parent,
	})
end

function UI.list(
	parent: Instance,
	direction: Enum.FillDirection,
	padding: number,
	align: Enum.HorizontalAlignment?
): UIListLayout
	return UI.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, padding),
		HorizontalAlignment = align or Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function UI.padding(parent: Instance, top: number, right: number?, bottom: number?, left: number?)
	UI.new("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right or top),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, left or right or top),
		Parent = parent,
	})
end

function UI.gradient(parent: Instance, top: Color3, bottom: Color3): UIGradient
	return UI.new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90, Parent = parent })
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------

-- props.font: "label" (heavy UPPERCASE Montserrat) or "number" (Fredoka One, default).
-- Text is white with a black outline unless props.stroke == false.
function UI.text(props: { [string]: any }): TextLabel
	local isLabel = props.font == "label"
	local size = props.size or 24
	local text = props.Text or ""
	local label = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = if isLabel then Theme.LabelFont else Theme.NumberFont,
		TextSize = size,
		TextScaled = props.scaled == true,
		TextColor3 = props.color or WHITE,
		Text = if isLabel then string.upper(text) else text,
		Size = props.Size or UDim2.new(0, 0, 0, size + 6),
		AutomaticSize = props.AutomaticSize or (if props.Size then Enum.AutomaticSize.None else Enum.AutomaticSize.X),
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center,
		TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center,
		TextWrapped = props.TextWrapped == true,
		Name = props.Name or "Text",
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Visible = if props.Visible == nil then true else props.Visible,
		Parent = props.Parent,
	})
	label:SetAttribute("Upper", isLabel)
	if props.stroke ~= false then
		UI.stroke(label, props.strokeThickness or math.clamp(math.floor(size / 9 + 0.5), 2, 6))
	end
	if props.scaled then
		UI.new("UITextSizeConstraint", { MaxTextSize = size, Parent = label })
	end
	return label
end

-- Sets text, keeping labels uppercase.
function UI.setText(label: TextLabel, text: string)
	label.Text = if label:GetAttribute("Upper") == true then string.upper(text) else text
end

-- An icon from Theme.Icons: an image once uploaded, a glyph until then.
function UI.icon(key: string, props: { [string]: any }): GuiObject
	local icon = Theme.Icons[key] or Theme.Icons.star
	local node: GuiObject
	if icon.image ~= "" then
		node = UI.new("ImageLabel", {
			BackgroundTransparency = 1,
			Image = icon.image,
			ScaleType = Enum.ScaleType.Fit,
			Size = props.Size or UDim2.fromScale(1, 1),
			Position = props.Position or UDim2.fromScale(0, 0),
			AnchorPoint = props.AnchorPoint or Vector2.zero,
			LayoutOrder = props.LayoutOrder or 0,
			Name = props.Name or "Icon",
			Parent = props.Parent,
		})
	else
		node = UI.new("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.FredokaOne,
			Text = icon.glyph,
			TextScaled = true,
			TextColor3 = WHITE,
			Size = props.Size or UDim2.fromScale(1, 1),
			Position = props.Position or UDim2.fromScale(0, 0),
			AnchorPoint = props.AnchorPoint or Vector2.zero,
			LayoutOrder = props.LayoutOrder or 0,
			Name = props.Name or "Icon",
			Parent = props.Parent,
		})
	end
	UI.aspect(node, 1)
	return node
end

---------------------------------------------------------------------------
-- Panels
---------------------------------------------------------------------------

export type Chunky = { holder: GuiObject, face: Frame, shadow: Frame, stroke: UIStroke }

local function layer(holder: GuiObject, props: { [string]: any }): Chunky
	local radius = props.radius or 18
	local lip = if props.lip == nil then UI.LIP else props.lip
	local shadow = UI.new("Frame", {
		Name = "Shadow",
		BackgroundColor3 = V.Outline,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, lip),
		Visible = lip > 0,
		Parent = holder,
	})
	UI.corner(shadow, radius)
	local face = UI.new("Frame", {
		Name = "Face",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = props.transparency or 0,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	})
	UI.corner(face, radius)
	UI.gradient(face, props.top, props.bottom).Name = "Fill"
	local stroke = UI.stroke(face, props.strokeWidth or 5, props.ring or V.Purple)
	return { holder = holder, face = face, shadow = shadow, stroke = stroke }
end

-- Dark gradient panel with a bright accent border. Put content in `.face`.
function UI.panel(props: { [string]: any }): Chunky
	local holder = UI.new("Frame", {
		Name = props.Name or "Panel",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(100, 100),
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Visible = if props.Visible == nil then true else props.Visible,
		Parent = props.Parent,
	})
	return layer(holder, {
		top = V.PanelTop,
		bottom = V.PanelBottom,
		transparency = V.PanelTransparency,
		ring = props.accent or V.Purple,
		strokeWidth = props.strokeWidth or 5,
		radius = props.radius or 20,
		lip = props.lip,
	})
end

-- Back-compat name used by older screens.
UI.surface = UI.panel

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------

local function attachPress(button: TextButton, face: Frame, onClick: () -> ())
	local scale = Motion.scaleOf(button)
	local pressed = UDim2.fromOffset(0, math.max(UI.LIP - 1, 0))
	local function press()
		Motion.tween(face, Motion.T.press, { Position = pressed })
		Motion.tween(scale, Motion.T.press, { Scale = 0.95 })
	end
	local function release()
		Motion.tween(face, Motion.T.release, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
		Motion.tween(scale, Motion.T.release, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	button.MouseButton1Down:Connect(press)
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.Activated:Connect(function()
		release()
		Sound.play("click")
		onClick()
	end)
end

local function holderButton(props: { [string]: any }, default: UDim2): TextButton
	return UI.new("TextButton", {
		Name = props.Name or "Button",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Text = "",
		Size = props.Size or default,
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Selectable = true,
		Visible = if props.Visible == nil then true else props.Visible,
		Parent = props.Parent,
	})
end

-- Bright gradient button with a white border (PLAY, upgrade, sell...). props.style picks the
-- colour: "green" | "red" | "blue" | "gold" | "purple" | "gray".
function UI.button(props: { [string]: any }, onClick: () -> ()): TextButton
	local button = holderButton(props, UDim2.fromOffset(240, 66))
	local style = STYLES[props.style or "green"] or STYLES.green
	local chunky = layer(button, {
		top = style.top,
		bottom = style.bottom,
		ring = WHITE,
		strokeWidth = props.strokeWidth or 4,
		radius = props.radius or 12,
		lip = props.lip,
	})
	local content = UI.new(
		"Frame",
		{ Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = chunky.face }
	)
	UI.list(content, Enum.FillDirection.Horizontal, 8)
	UI.padding(content, 4, 12, 6, 12)
	if props.icon then
		UI.icon(
			props.icon,
			{ Size = UDim2.fromOffset(props.iconSize or 34, props.iconSize or 34), LayoutOrder = 1, Parent = content }
		)
	end
	if props.Text then
		UI.text({
			Text = props.Text,
			Name = "Label",
			font = "label",
			size = props.textSize or 24,
			LayoutOrder = 2,
			Parent = content,
		})
	end
	button:SetAttribute("Style", props.style or "green")
	attachPress(button, chunky.face, onClick)
	return button
end

function UI.setButtonText(button: Instance, text: string)
	local label = button:FindFirstChild("Label", true)
	if label and label:IsA("TextLabel") then
		UI.setText(label, text)
	end
end

function UI.setButtonStyle(button: Instance, style: Style)
	if button:GetAttribute("Style") == style then
		return
	end
	local s = STYLES[style]
	local face = button:FindFirstChild("Face")
	local fill = face and face:FindFirstChild("Fill")
	if s and fill and fill:IsA("UIGradient") then
		fill.Color = ColorSequence.new(s.top, s.bottom)
	end
	button:SetAttribute("Style", style)
end

-- Wide menu tile (Figma MenuTile): dark face, accent border, big icon + UPPERCASE label.
function UI.menuTile(props: { [string]: any }, onClick: () -> ()): TextButton
	local button = holderButton(props, UDim2.fromOffset(260, 80))
	local chunky = layer(
		button,
		{ top = V.PanelTop, bottom = V.PanelBottom, ring = props.accent or V.Red, strokeWidth = 5, radius = 16 }
	)
	UI.icon(props.icon, {
		Size = UDim2.fromOffset(70, 70),
		Position = UDim2.new(0, 6, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = chunky.face,
	})
	UI.text({
		Text = props.Text or "",
		Name = "Label",
		font = "label",
		size = props.textSize or 24,
		Position = UDim2.new(0, 86, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = chunky.face,
	})
	attachPress(button, chunky.face, onClick)
	return button
end

export type SquareTile = { button: TextButton, label: TextLabel, badge: Frame, badgeLabel: TextLabel, face: Frame }

-- Square icon tile (Figma SquareTile): label overlapping the bottom edge, optional badge.
function UI.squareTile(props: { [string]: any }, onClick: () -> ()): SquareTile
	local button = holderButton(props, UDim2.fromOffset(108, 104))
	local chunky = layer(
		button,
		{ top = V.PanelTop, bottom = V.PanelBottom, ring = props.accent or V.Blue, strokeWidth = 5, radius = 20 }
	)
	UI.icon(props.icon, {
		Size = UDim2.fromOffset(66, 66),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = chunky.face,
	})
	local label = UI.text({
		Text = props.Text or "",
		Name = "Label",
		font = "label",
		size = props.textSize or 18,
		Position = UDim2.new(0.5, 0, 1, 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 3,
		Parent = button,
	})
	local badge = UI.new("Frame", {
		Name = "Badge",
		BackgroundColor3 = V.Badge,
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(1, 8, 0, -10),
		AnchorPoint = Vector2.new(1, 0),
		Visible = props.badge ~= nil,
		ZIndex = 3,
		Parent = button,
	})
	UI.corner(badge, 999)
	UI.stroke(badge, 3, WHITE)
	UI.padding(badge, 0, 9, 0, 9)
	local badgeLabel = UI.text({
		Text = props.badge or "",
		Name = "BadgeText",
		font = "label",
		size = 16,
		Size = UDim2.new(0, 0, 1, 0),
		ZIndex = 4,
		Parent = badge,
	})
	attachPress(button, chunky.face, onClick)
	return { button = button, label = label, badge = badge, badgeLabel = badgeLabel, face = chunky.face }
end

---------------------------------------------------------------------------
-- Display widgets
---------------------------------------------------------------------------

-- Currency counter (Figma Currency): icon + big outlined number, no background.
function UI.currency(props: { [string]: any }): (Frame, TextLabel)
	local frame = UI.new("Frame", {
		Name = props.Name or "Currency",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 64),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	UI.list(frame, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left)
	UI.icon(
		props.icon,
		{ Size = UDim2.fromOffset(props.iconSize or 58, props.iconSize or 58), LayoutOrder = 1, Parent = frame }
	)
	local value = UI.text({
		Text = props.Text or "0",
		Name = "Value",
		size = props.size or 40,
		color = props.color or V.CoinText,
		LayoutOrder = 2,
		Parent = frame,
	})
	return frame, value
end

-- Dark pill with an accent ring and an outlined label (toasts, chips, queue status).
function UI.chip(props: { [string]: any }): (Frame, TextLabel)
	local chip = UI.new("Frame", {
		Name = props.Name or "Chip",
		BackgroundColor3 = props.fill or V.Slot,
		BackgroundTransparency = props.fillTransparency or 0.3,
		Size = UDim2.fromOffset(0, props.height or 44),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Visible = if props.Visible == nil then true else props.Visible,
		Parent = props.Parent,
	})
	UI.corner(chip, 999)
	UI.stroke(chip, props.ringWidth or 3, props.ring or V.Gold)
	UI.padding(chip, 0, 18, 0, 18)
	UI.list(chip, Enum.FillDirection.Horizontal, 8)
	if props.icon then
		UI.icon(props.icon, {
			Size = UDim2.fromOffset((props.height or 44) - 10, (props.height or 44) - 10),
			LayoutOrder = 1,
			Parent = chip,
		})
	end
	local label = UI.text({
		Text = props.Text or "",
		Name = "Label",
		font = "label",
		size = props.textSize or 18,
		color = props.color,
		LayoutOrder = 2,
		Parent = chip,
	})
	return chip, label
end

-- Progress bar: translucent black track, black outline, gradient fill, optional ticks.
function UI.bar(props: { [string]: any }): (Frame, Frame)
	local track = UI.new("Frame", {
		Name = props.Name or "Bar",
		BackgroundColor3 = V.Slot,
		BackgroundTransparency = 0.25,
		Size = props.Size or UDim2.fromOffset(360, 18),
		Position = props.Position or UDim2.fromScale(0, 0),
		LayoutOrder = props.LayoutOrder or 0,
		ClipsDescendants = false,
		Parent = props.Parent,
	})
	UI.corner(track, 999)
	UI.stroke(track, 3)
	local fill = UI.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = WHITE,
		Size = UDim2.fromScale(math.clamp(props.value or 0, 0, 1), 1),
		Parent = track,
	})
	UI.corner(fill, 999)
	UI.new("UIGradient", { Color = ColorSequence.new(props.from or V.GooText, props.to or V.Green), Parent = fill })
	for i = 1, (props.ticks or 0) - 1 do
		UI.new("Frame", {
			Name = "Tick",
			BackgroundColor3 = V.Outline,
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 3, 1, 0),
			Position = UDim2.fromScale(i / props.ticks, 0),
			ZIndex = 2,
			Parent = track,
		})
	end
	return track, fill
end

export type XpBar = { holder: Frame, level: TextLabel, nextLevel: TextLabel, fill: Frame, exp: TextLabel, max: TextLabel }

-- Level + segmented XP bar (Figma XPBar).
function UI.xpBar(props: { [string]: any }): XpBar
	local holder = UI.new("Frame", {
		Name = props.Name or "XpBar",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(760, 64),
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Parent = props.Parent,
	})
	UI.text({ Text = "Lv.", font = "label", size = 14, Position = UDim2.fromOffset(18, 0), Parent = holder })
	local level = UI.text({
		Name = "Level",
		Text = "1",
		size = 40,
		color = V.Xp,
		Size = UDim2.fromOffset(70, 44),
		Position = UDim2.fromOffset(0, 16),
		Parent = holder,
	})
	local track, fill = UI.bar({
		Name = "Track",
		Size = UDim2.fromOffset(600, 28),
		Position = UDim2.fromOffset(80, 22),
		from = Color3.fromHex("#1F5FFF"),
		to = Color3.fromHex("#7FD0FF"),
		ticks = 7,
		Parent = holder,
	})
	local exp = UI.text({
		Name = "Exp",
		Text = "0 Exp",
		font = "label",
		size = 14,
		Position = UDim2.new(0, 14, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 3,
		Parent = track,
	})
	local max = UI.text({
		Name = "Max",
		Text = "500",
		font = "label",
		size = 14,
		Position = UDim2.new(1, -14, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		ZIndex = 3,
		Parent = track,
	})
	local nextLevel = UI.text({
		Name = "NextLevel",
		Text = "2",
		size = 34,
		color = V.Xp,
		Size = UDim2.fromOffset(70, 40),
		Position = UDim2.fromOffset(690, 18),
		Parent = holder,
	})
	return { holder = holder, level = level, nextLevel = nextLevel, fill = fill, exp = exp, max = max }
end

function UI.formatCash(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(formatted, 1, 1) == "," then
		formatted = string.sub(formatted, 2)
	end
	return "$" .. formatted
end

return UI

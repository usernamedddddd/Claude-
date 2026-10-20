--!strict
-- UI kit implementing the Figma "Slime Siege UI" design system:
--   * chunky surfaces: a face with a 3-4 px ink outline sitting on an ink "lip" (the Figma
--     Chunky shadow: 0, 6 px, no blur)
--   * Fredoka One text; white labels with an ink outline on saturated fills, ink labels on gold
--     and light cards (all pairs >= 4.5:1 contrast)
--   * a root UIScale so layouts are authored at 1920x1080 and scale to any screen, with a
--     floor that keeps phones readable (matches the Figma phone frame)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Data.Theme)
local Motion = require(script.Parent.Motion)
local Sound = require(script.Parent.Sound)

local UI = {}

UI.Colors = Theme.Colors
UI.FONT = Theme.FONT
UI.LIP = 6

local C = Theme.Colors

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

-- Full-screen root authored in 1920x1080 "design pixels". Children position with scale anchors
-- (e.g. top-right = Position (1, -32, 0, 28), AnchorPoint (1, 0)) and size in design pixels.
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
		-- 1080p = 1.0; phones (~390 px tall) get ~0.62 like the Figma phone frame.
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
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 18), Parent = parent })
end

function UI.stroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return UI.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or C.Ink,
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

-- Text in the game font. Light-on-dark text gets an ink outline for readability over the 3D
-- scene; dark text on light/gold surfaces does not.
function UI.text(props: { [string]: any }): TextLabel
	local color = props.color or C.Text
	local label = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.FONT,
		TextScaled = props.size == nil,
		TextSize = props.size or 24,
		TextColor3 = color,
		Text = props.Text or "",
		Size = props.Size or UDim2.fromScale(1, 1),
		AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.None,
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center,
		TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center,
		TextWrapped = props.TextWrapped ~= false,
		Name = props.Name or "Text",
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	local wantsStroke = if props.stroke ~= nil then props.stroke else color ~= C.TextDark and color ~= C.Ink
	if wantsStroke then
		UI.stroke(label, props.strokeThickness or 2)
	end
	if props.size == nil then
		UI.new("UITextSizeConstraint", { MaxTextSize = props.maxTextSize or 48, Parent = label })
	end
	return label
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
		node = UI.text({
			Text = icon.glyph,
			Size = props.Size,
			Position = props.Position,
			AnchorPoint = props.AnchorPoint,
			LayoutOrder = props.LayoutOrder,
			Name = props.Name or "Icon",
			Parent = props.Parent,
			stroke = false,
			maxTextSize = 120,
		})
	end
	UI.aspect(node, 1)
	return node
end

export type Chunky = { holder: GuiObject, face: Frame, shadow: Frame, stroke: UIStroke }

local function makeChunky(holder: GuiObject, props: { [string]: any }): Chunky
	local radius = props.radius or 18
	local lip = if props.lip == nil then UI.LIP else props.lip
	local shadow = UI.new("Frame", {
		Name = "Shadow",
		BackgroundColor3 = C.Ink,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, lip),
		Visible = lip > 0,
		Parent = holder,
	})
	UI.corner(shadow, radius)
	local face = UI.new("Frame", {
		Name = "Face",
		BackgroundColor3 = props.color or C.Panel,
		BackgroundTransparency = props.transparency or 0,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	})
	UI.corner(face, radius)
	local stroke = UI.stroke(face, props.strokeWidth or 4, props.ring or C.Ink)
	return { holder = holder, face = face, shadow = shadow, stroke = stroke }
end

-- A chunky panel/card. Put content in `.face`.
function UI.surface(props: { [string]: any }): Chunky
	local holder = UI.new("Frame", {
		Name = props.Name or "Surface",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(100, 100),
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.None,
		LayoutOrder = props.LayoutOrder or 0,
		Visible = if props.Visible == nil then true else props.Visible,
		Parent = props.Parent,
	})
	return makeChunky(holder, props)
end

function UI.labelColorFor(fill: Color3): Color3
	return if fill == C.Gold
			or fill == C.Card
			or fill == C.Pink
			or fill == C.Cyan
			or fill == C.Lime
		then C.TextDark
		else C.Text
end

-- Chunky button: icon + label on a coloured face over an ink lip. Pressing pushes the face
-- into the lip and squishes it (Figma motion spec: 80 ms in, 180 ms Back-Out out).
function UI.button(props: { [string]: any }, onClick: () -> ()): TextButton
	local button = UI.new("TextButton", {
		Name = props.Name or "Button",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Text = "",
		Size = props.Size or UDim2.fromOffset(220, 64),
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Selectable = true,
		Visible = if props.Visible == nil then true else props.Visible,
		Parent = props.Parent,
	})
	local fill = props.color or C.Green
	local chunky = makeChunky(button, { color = fill, radius = props.radius or 18, lip = props.lip, strokeWidth = 4 })
	local content = UI.new(
		"Frame",
		{ Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = chunky.face }
	)
	UI.list(content, Enum.FillDirection.Horizontal, 10)
	UI.padding(content, 6, 16, 8, 16)
	if props.icon then
		UI.icon(
			props.icon,
			{ Size = UDim2.new(0, props.iconSize or 34, 0, props.iconSize or 34), LayoutOrder = 1, Parent = content }
		)
	end
	if props.Text then
		local label = UI.text({
			Text = props.Text,
			Name = "Label",
			color = UI.labelColorFor(fill),
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			size = props.textSize or 28,
			TextWrapped = false,
			LayoutOrder = 2,
			Parent = content,
		})
		label:SetAttribute("Fill", fill:ToHex())
	end
	button:SetAttribute("Fill", fill:ToHex())

	local face = chunky.face
	local scale = Motion.scaleOf(button)
	local pressedOffset = UDim2.fromOffset(0, math.max(UI.LIP - 2, 0))
	local function press()
		Motion.tween(face, Motion.T.press, { Position = pressedOffset })
		Motion.tween(scale, Motion.T.press, { Scale = 0.94 })
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
	return button
end

local function faceOf(button: Instance): Frame?
	local face = button:FindFirstChild("Face")
	return if face and face:IsA("Frame") then face else nil
end

function UI.setButtonText(button: Instance, text: string)
	local label = button:FindFirstChild("Label", true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

-- Recolours a chunky button (e.g. to Disabled) and keeps the label readable.
function UI.setButtonColor(button: Instance, fill: Color3)
	local face = faceOf(button)
	if face then
		face.BackgroundColor3 = fill
	end
	button:SetAttribute("Fill", fill:ToHex())
	local label = button:FindFirstChild("Label", true)
	if label and label:IsA("TextLabel") then
		local color = UI.labelColorFor(fill)
		label.TextColor3 = color
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = color == C.Text
		elseif color == C.Text then
			UI.stroke(label, 2)
		end
	end
end

function UI.setRing(chunkyFace: Frame, color: Color3, thickness: number?)
	local stroke = chunkyFace:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = thickness or stroke.Thickness
	end
end

-- Stat pill (Figma StatPill): dark pill, raised icon bubble, white value.
export type Pill = { holder: GuiObject, value: TextLabel, bubble: Frame, face: Frame }
function UI.pill(props: { [string]: any }): Pill
	local chunky = UI.surface({
		Name = props.Name or "Pill",
		Size = UDim2.fromOffset(props.width or 200, props.height or 64),
		LayoutOrder = props.LayoutOrder,
		radius = 999,
		color = C.Panel,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Parent = props.Parent,
	})
	local h = props.height or 64
	local bubble = UI.new("Frame", {
		Name = "Bubble",
		BackgroundColor3 = C.PanelRaised,
		Size = UDim2.fromOffset(h - 12, h - 12),
		Position = UDim2.fromOffset(6, 6),
		Parent = chunky.face,
	})
	UI.corner(bubble, 999)
	UI.icon(props.icon, {
		Size = UDim2.fromScale(0.78, 0.78),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = bubble,
	})
	local value = UI.text({
		Text = props.Text or "",
		Name = "Value",
		size = props.textSize or 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -(h + 14), 1, 0),
		Position = UDim2.fromOffset(h + 2, 0),
		TextWrapped = false,
		Parent = chunky.face,
	})
	return { holder = chunky.holder, value = value, bubble = bubble, face = chunky.face }
end

-- Small rounded chip (vote counts, countdowns, hints).
function UI.chip(props: { [string]: any }): (Frame, TextLabel)
	local fill = props.color or C.Panel
	local chip = UI.new("Frame", {
		Name = props.Name or "Chip",
		BackgroundColor3 = fill,
		Size = UDim2.fromOffset(0, props.height or 34),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Visible = if props.Visible == nil then true else props.Visible,
		Parent = props.Parent,
	})
	UI.corner(chip, 999)
	UI.stroke(chip, 3)
	UI.padding(chip, 2, 14, 4, 14)
	local label = UI.text({
		Text = props.Text or "",
		Name = "Label",
		color = UI.labelColorFor(fill),
		size = props.textSize or 18,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		TextWrapped = false,
		Parent = chip,
	})
	return chip, label
end

-- Horizontal progress bar (wave progress, XP). Returns the bar and its fill.
function UI.bar(props: { [string]: any }): (Frame, Frame)
	local track = UI.new("Frame", {
		Name = props.Name or "Bar",
		BackgroundColor3 = C.PanelRaised,
		Size = props.Size or UDim2.fromOffset(260, 14),
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	UI.corner(track, 999)
	if props.outline then
		UI.stroke(track, 3)
	end
	local fill = UI.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = props.color or C.Lime,
		Size = UDim2.fromScale(math.clamp(props.value or 0, 0, 1), 1),
		Parent = track,
	})
	UI.corner(fill, 999)
	return track, fill
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

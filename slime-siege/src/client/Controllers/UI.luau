--!strict
-- Tiny UI kit for chunky, cartoony, scale-based UI. Everything is sized with scale +
-- UIAspectRatioConstraint so it works from phones to TVs; ScreenGuis respect safe areas.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Data.Theme)
local Sound = require(script.Parent.Sound)

local UI = {}

UI.Colors = Theme.Colors
UI.FONT = Theme.FONT

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

function UI.corner(parent: Instance, scale: number?): UICorner
	return UI.new("UICorner", { CornerRadius = UDim.new(scale or 0.25, 0), Parent = parent })
end

function UI.stroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return UI.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or Theme.Colors.Stroke,
		ApplyStrokeMode = if parent:IsA("TextLabel") or parent:IsA("TextButton")
			then Enum.ApplyStrokeMode.Contextual
			else Enum.ApplyStrokeMode.Border,
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

function UI.gradient(parent: Instance, top: Color3, bottom: Color3)
	UI.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = 90,
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
		Padding = UDim.new(padding, 0),
		HorizontalAlignment = align or Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function UI.padding(parent: Instance, scale: number)
	UI.new("UIPadding", {
		PaddingTop = UDim.new(scale, 0),
		PaddingBottom = UDim.new(scale, 0),
		PaddingLeft = UDim.new(scale, 0),
		PaddingRight = UDim.new(scale, 0),
		Parent = parent,
	})
end

function UI.panel(props: { [string]: any }): Frame
	local frame = UI.new("Frame", {
		BackgroundColor3 = props.color or Theme.Colors.PanelDark,
		BorderSizePixel = 0,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Visible = if props.Visible == nil then true else props.Visible,
		Name = props.Name or "Panel",
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	UI.corner(frame, props.corner or 0.12)
	UI.stroke(frame, 4)
	return frame
end

function UI.text(props: { [string]: any }): TextLabel
	local label = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.FONT,
		TextScaled = true,
		TextColor3 = props.color or Theme.Colors.Text,
		Text = props.Text or "",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center,
		TextWrapped = true,
		Name = props.Name or "Text",
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	if props.stroke ~= false then
		UI.stroke(label, props.strokeThickness or 2)
	end
	UI.new("UITextSizeConstraint", { MaxTextSize = props.maxTextSize or 48, Parent = label })
	return label
end

-- An icon from Theme.Icons: an image once uploaded, a glyph until then.
function UI.icon(key: string, props: { [string]: any }): GuiObject
	local icon = Theme.Icons[key] or Theme.Icons.star
	if icon.image ~= "" then
		return UI.new("ImageLabel", {
			BackgroundTransparency = 1,
			Image = icon.image,
			ScaleType = Enum.ScaleType.Fit,
			Size = props.Size or UDim2.fromScale(1, 1),
			Position = props.Position or UDim2.fromScale(0, 0),
			AnchorPoint = props.AnchorPoint or Vector2.zero,
			LayoutOrder = props.LayoutOrder or 0,
			Parent = props.Parent,
		})
	end
	local label = UI.text({
		Text = icon.glyph,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		Parent = props.Parent,
		stroke = false,
		maxTextSize = 100,
	})
	UI.aspect(label, 1)
	return label
end

-- Chunky button with a press "squish". onClick works for mouse, touch and gamepad (A button).
function UI.button(props: { [string]: any }, onClick: () -> ()): TextButton
	local button = UI.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = props.color or Theme.Colors.Green,
		BorderSizePixel = 0,
		Text = "",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Selectable = true,
		Name = props.Name or "Button",
		Visible = if props.Visible == nil then true else props.Visible,
		Parent = props.Parent,
	})
	UI.corner(button, props.corner or 0.3)
	UI.stroke(button, 4)
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205)),
		Rotation = 90,
		Parent = button,
	})
	local scale = UI.new("UIScale", { Parent = button })
	if props.Text then
		UI.text({
			Text = props.Text,
			Size = UDim2.fromScale(0.9, 0.8),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Name = "Label",
			Parent = button,
		})
	end
	local info = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, info, { Scale = 0.9 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, info, { Scale = 1 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, info, { Scale = 1 }):Play()
	end)
	button.Activated:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		Sound.play("click")
		onClick()
	end)
	return button
end

function UI.setButtonText(button: GuiObject, text: string)
	local label = button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
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

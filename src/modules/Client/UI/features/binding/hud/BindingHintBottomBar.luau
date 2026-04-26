--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local TextLabel = require(script:FindFirstAncestor("game").Client.UI.core.primitives.TextLabel)
local bindingSlice = require(script:FindFirstAncestor("game").Client.UI.features.binding.state.bindingSlice)

type BindingHintEntry = bindingSlice.BindingHintEntry

type BindingHintBottomBarProps = {
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	hints: { BindingHintEntry }?,
	deviceClass: string?,
}

type Metrics = {
	promptHeight: number,
	promptMinWidth: number,
	promptTextSize: number,
	labelTextSize: number,
	detailTextSize: number,
	promptGap: number,
	itemGap: number,
	labelGap: number,
	leftInset: number,
	bottomInset: number,
}

local e: typeof(React.createElement) = React.createElement

local function resolveMetrics(deviceClassRaw: any): Metrics
	if deviceClassRaw == "Console" then
		return {
			promptHeight = 42,
			promptMinWidth = 42,
			promptTextSize = 24,
			labelTextSize = 20,
			detailTextSize = 15,
			promptGap = 8,
			itemGap = 14,
			labelGap = 2,
			leftInset = 20,
			bottomInset = 12,
		}
	end
	if deviceClassRaw == "Phone" then
		return {
			promptHeight = 30,
			promptMinWidth = 30,
			promptTextSize = 16,
			labelTextSize = 14,
			detailTextSize = 11,
			promptGap = 6,
			itemGap = 10,
			labelGap = 1,
			leftInset = 10,
			bottomInset = 8,
		}
	end
	if deviceClassRaw == "Tablet" then
		return {
			promptHeight = 34,
			promptMinWidth = 34,
			promptTextSize = 19,
			labelTextSize = 15,
			detailTextSize = 12,
			promptGap = 6,
			itemGap = 11,
			labelGap = 1,
			leftInset = 12,
			bottomInset = 9,
		}
	end
	return {
		promptHeight = 38,
		promptMinWidth = 38,
		promptTextSize = 20,
		labelTextSize = 15,
		detailTextSize = 11,
		promptGap = 6,
		itemGap = 12,
		labelGap = 1,
		leftInset = 12,
		bottomInset = 9,
	}
end

local function resolvePromptIconWidth(hint: BindingHintEntry, metrics: Metrics): number
	local promptText = hint.promptText or ""
	local widthFactor = 1

	if promptText == "Space" then
		widthFactor = 2.35
	elseif promptText == "Enter" or promptText == "Shift" or promptText == "Ctrl" or promptText == "Alt" then
		widthFactor = 1.65
	elseif string.find(promptText, "D-Pad", 1, true) ~= nil or string.find(promptText, "Stick", 1, true) ~= nil then
		widthFactor = 1.5
	elseif #promptText >= 4 then
		widthFactor = 1.3
	elseif #promptText >= 2 then
		widthFactor = 1.1
	end

	return math.max(metrics.promptMinWidth, math.floor(metrics.promptHeight * widthFactor + 0.5))
end

local function resolvePromptGap(hint: BindingHintEntry, metrics: Metrics): number
	local promptText = hint.promptText or ""
	if promptText == "Space" then
		return math.max(2, metrics.promptGap - 2)
	end
	if #promptText >= 4 or string.find(promptText, "D-Pad", 1, true) ~= nil or string.find(promptText, "Stick", 1, true) ~= nil then
		return math.max(3, metrics.promptGap - 1)
	end
	return metrics.promptGap
end

local function HintPrompt(props: {
	hint: BindingHintEntry,
	metrics: Metrics,
	zIndex: number,
}): React.ReactNode
	local hasPromptIcon = props.hint.promptIcon ~= nil and props.hint.promptIcon ~= ""
	local hasPromptText = props.hint.promptText ~= nil and props.hint.promptText ~= ""
	local enabled = props.hint.enabled == true

	if hasPromptIcon then
		return e("ImageLabel", {
			Size = UDim2.fromOffset(resolvePromptIconWidth(props.hint, props.metrics), props.metrics.promptHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = props.hint.promptIcon,
			ScaleType = Enum.ScaleType.Fit,
			ImageTransparency = if enabled then 0 else 0.45,
			LayoutOrder = 1,
			ZIndex = props.zIndex + 1,
		})
	end

	if hasPromptText then
		return e(TextLabel, {
			name = "PromptText",
			text = props.hint.promptText,
			size = UDim2.fromOffset(0, 0),
			automaticSize = Enum.AutomaticSize.XY,
			backgroundTransparency = 1,
			font = Enum.Font.GothamBold,
			textSize = props.metrics.promptTextSize,
			textColor3 = if enabled then Color3.fromRGB(244, 248, 255) else Color3.fromRGB(176, 182, 192),
			textXAlignment = Enum.TextXAlignment.Left,
			textYAlignment = Enum.TextYAlignment.Center,
			layoutOrder = 1,
			zIndex = props.zIndex + 1,
			effects = {
				shadow = {
					enabled = true,
					color = Color3.fromRGB(0, 0, 0),
					transparency = 0.7,
					offset = Vector2.new(1, 1),
					layers = 1,
				},
			},
		})
	end

	return nil
end

local function HintBody(props: {
	hint: BindingHintEntry,
	metrics: Metrics,
	zIndex: number,
}): React.ReactNode
	local enabled = props.hint.enabled == true
	local children: { [string]: React.ReactNode } = {
		ListLayout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, props.metrics.labelGap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Label = e(TextLabel, {
			name = "HintLabel",
			text = props.hint.label,
			size = UDim2.fromOffset(0, 0),
			automaticSize = Enum.AutomaticSize.XY,
			backgroundTransparency = 1,
			font = Enum.Font.GothamBold,
			textSize = props.metrics.labelTextSize,
			textColor3 = if enabled then Color3.fromRGB(246, 249, 255) else Color3.fromRGB(182, 187, 196),
			textXAlignment = Enum.TextXAlignment.Left,
			textYAlignment = Enum.TextYAlignment.Center,
			layoutOrder = 1,
			zIndex = props.zIndex + 1,
			effects = {
				shadow = {
					enabled = true,
					color = Color3.fromRGB(0, 0, 0),
					transparency = 0.72,
					offset = Vector2.new(1, 1),
					layers = 1,
				},
			},
		}),
	}

	if props.hint.detail ~= nil and props.hint.detail ~= "" then
		children.Detail = e(TextLabel, {
			name = "HintDetail",
			text = props.hint.detail,
			size = UDim2.fromOffset(0, 0),
			automaticSize = Enum.AutomaticSize.XY,
			backgroundTransparency = 1,
			font = Enum.Font.Gotham,
			textSize = props.metrics.detailTextSize,
			textColor3 = if enabled then Color3.fromRGB(160, 198, 235) else Color3.fromRGB(205, 155, 155),
			textXAlignment = Enum.TextXAlignment.Left,
			textYAlignment = Enum.TextYAlignment.Center,
			layoutOrder = 2,
			zIndex = props.zIndex + 1,
		})
	end

	return e("Frame", {
		Size = UDim2.fromOffset(0, props.metrics.promptHeight),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = 2,
		Active = false,
		Selectable = false,
		ZIndex = props.zIndex,
	}, children)
end

local function HintItem(props: {
	hint: BindingHintEntry,
	metrics: Metrics,
	zIndex: number,
	layoutOrder: number,
}): React.ReactNode
	local children: { [string]: React.ReactNode } = {
		ListLayout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, resolvePromptGap(props.hint, props.metrics)),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Body = e(HintBody, {
			hint = props.hint,
			metrics = props.metrics,
			zIndex = props.zIndex + 1,
		}),
	}

	local prompt = HintPrompt({
		hint = props.hint,
		metrics = props.metrics,
		zIndex = props.zIndex + 1,
	})
	if prompt ~= nil then
		children.Prompt = prompt
	end

	return e("Frame", {
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		Active = false,
		Selectable = false,
		ZIndex = props.zIndex,
	}, children)
end

return function(props: BindingHintBottomBarProps): React.ReactNode
	local hints = props.hints or {}
	if props.visible == false or #hints <= 0 then
		return nil
	end

	local zIndex = props.zIndex or 180
	local metrics = resolveMetrics(props.deviceClass)
	local children: { [string]: React.ReactNode } = {
		ListLayout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, metrics.itemGap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, hint in hints do
		children["Hint_" .. hint.id] = e(HintItem, {
			hint = hint,
			metrics = metrics,
			zIndex = zIndex + 1,
			layoutOrder = index,
		})
	end

	return e("Frame", {
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Position = props.position or UDim2.new(0, metrics.leftInset, 1, -metrics.bottomInset),
		AnchorPoint = props.anchorPoint or Vector2.new(0, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 1,
		Active = false,
		Selectable = false,
		ZIndex = zIndex,
		Visible = true,
	}, children)
end

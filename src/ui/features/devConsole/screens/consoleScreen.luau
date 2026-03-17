--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local Charm = require(ReplicatedStorage.Packages.Charm)
local RichTextFormatter = require(ReplicatedStorage.Shared.Modules.UI.RichTextFormatter)
local DevPromptServiceUtils = require(ReplicatedStorage.Shared.Services.DevPromptService.DevPromptServiceUtils)
local Role = require(ReplicatedStorage.Shared.Services.DevPromptService.Role)
local TextLabel = require(ReplicatedStorage.UI.core.primitives.TextLabel)
local Prompt = require(ReplicatedStorage.UI.features.devConsole.components.prompt)
local devConsoleSlice = require(ReplicatedStorage.UI.features.devConsole.state.devConsoleSlice)
local devConsoleThunks = require(ReplicatedStorage.UI.features.devConsole.state.devConsoleThunks)

type ConsoleEntry = DevPromptServiceUtils.ConsoleEntry
type DevConsoleState = devConsoleSlice.DevConsoleState
type RoleId = Role.RoleId
type ScrollMetrics = {
	contentHeight: number,
	viewportHeight: number,
	canvasPositionY: number,
}

type ConsoleScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

local e: typeof(React.createElement) = React.createElement

local PROMPT_BOTTOM_INSET = 74
local PROMPT_HEIGHT = 36
local OUTPUT_PANEL_HEIGHT = 156
local OUTPUT_CONTENT_WIDTH_PADDING = 12
local OUTPUT_PREFIX_TEXT_SIZE = 13
local OUTPUT_PREFIX_MIN_WIDTH = 136
local OUTPUT_PREFIX_MAX_WIDTH = 248
local OUTPUT_PREFIX_GAP = 8
local OUTPUT_PANEL_BACKGROUND_TRANSPARENCY = 0.38
local OUTPUT_SCROLL_TRACK_WIDTH = 6
local OUTPUT_SCROLL_TRACK_RIGHT_PADDING = 6
local OUTPUT_SCROLL_TRACK_VERTICAL_PADDING = 6
local OUTPUT_SCROLL_WHEEL_STEP = 36
local OUTPUT_AUTO_SCROLL_SNAP_PADDING = 12
local PROMPT_PREFIX_COLOR = Color3.fromRGB(255, 226, 98)

local function getMaxScrollY(scrollFrame: ScrollingFrame): number
	return math.max(0, scrollFrame.AbsoluteCanvasSize.Y - scrollFrame.AbsoluteWindowSize.Y)
end

local function isNearScrollBottom(scrollFrame: ScrollingFrame): boolean
	return (getMaxScrollY(scrollFrame) - scrollFrame.CanvasPosition.Y) <= OUTPUT_AUTO_SCROLL_SNAP_PADDING
end

local function scrollToBottom(scrollFrame: ScrollingFrame)
	scrollFrame.CanvasPosition = Vector2.new(scrollFrame.CanvasPosition.X, getMaxScrollY(scrollFrame))
end

local function syncScrollCanvas(scrollFrame: ScrollingFrame?, contentFrame: Frame?)
	if scrollFrame == nil or contentFrame == nil then
		return
	end

	local contentHeight = math.max(0, contentFrame.AbsoluteSize.Y)
	scrollFrame.CanvasSize = UDim2.fromOffset(0, contentHeight)
end

local function resolvePromptFlavor(roleIdRaw: any): string
	local roleId = Role.getDefinition(roleIdRaw).id
	if roleId == "Member" then
		return "default"
	end
	return "developer"
end

local function buildPromptPrefix(userNameRaw: any, roleIdRaw: any): string
	local userName = DevPromptServiceUtils.trim(userNameRaw)
	if userName == "" then
		return ""
	end
	return ("%s-%s$"):format(userName, resolvePromptFlavor(roleIdRaw))
end

local function measurePromptPrefixWidth(prefixText: string): number
	local measuredSize = TextService:GetTextSize(
		prefixText,
		OUTPUT_PREFIX_TEXT_SIZE,
		Enum.Font.Code,
		Vector2.new(1000, PROMPT_HEIGHT)
	)
	return math.clamp(math.ceil(measuredSize.X) + 4, OUTPUT_PREFIX_MIN_WIDTH, OUTPUT_PREFIX_MAX_WIDTH)
end

local function resolveKindColor(entry: ConsoleEntry): Color3
	if entry.kind == "success" then
		return Color3.fromRGB(153, 243, 162)
	end
	if entry.kind == "warning" then
		return Color3.fromRGB(255, 218, 117)
	end
	if entry.kind == "error" then
		return Color3.fromRGB(255, 142, 142)
	end
	if entry.kind == "command" then
		return Color3.fromRGB(238, 243, 252)
	end
	if entry.kind == "system" then
		return Color3.fromRGB(164, 225, 255)
	end
	return Color3.fromRGB(220, 225, 233)
end

local function buildEntryRichText(entry: ConsoleEntry): string
	local formatter = RichTextFormatter.new()
	if entry.userName ~= nil and entry.userName ~= "" then
		formatter:color(PROMPT_PREFIX_COLOR, buildPromptPrefix(entry.userName, entry.roleId))
		formatter:append(" ")
	end
	formatter:color(resolveKindColor(entry), entry.text)
	return formatter:toString()
end

return function(props: ConsoleScreenProps): React.ReactNode
	local consoleState, setConsoleState = React.useState(function(): DevConsoleState
		return devConsoleSlice.devConsoleStateAtom()
	end)
	local localPlayer = Players.LocalPlayer
	local scrollRef = React.useRef(nil :: ScrollingFrame?)
	local scrollContentRef = React.useRef(nil :: Frame?)
	local outputHoveredRef = React.useRef(false)
	local followOutputRef = React.useRef(true)
	local scrollMetrics, setScrollMetrics = React.useState({
		contentHeight = 0,
		viewportHeight = 0,
		canvasPositionY = 0,
	} :: ScrollMetrics)

	local function refreshScrollMetrics(scrollFrame: ScrollingFrame?, contentFrame: Frame?)
		if scrollFrame == nil or contentFrame == nil then
			return
		end

		syncScrollCanvas(scrollFrame, contentFrame)
		local nextMetrics = {
			contentHeight = math.max(0, contentFrame.AbsoluteSize.Y),
			viewportHeight = math.max(0, scrollFrame.AbsoluteWindowSize.Y),
			canvasPositionY = scrollFrame.CanvasPosition.Y,
		}
		setScrollMetrics(function(current: ScrollMetrics): ScrollMetrics
			if math.abs(current.contentHeight - nextMetrics.contentHeight) <= 0.5
				and math.abs(current.viewportHeight - nextMetrics.viewportHeight) <= 0.5
				and math.abs(current.canvasPositionY - nextMetrics.canvasPositionY) <= 0.5 then
				return current
			end
			return nextMetrics
		end)
	end

	React.useEffect(function()
		local stop = devConsoleThunks.start()
		local unsubscribe = Charm.subscribe(devConsoleSlice.devConsoleStateAtom, function(nextState: DevConsoleState)
			setConsoleState(nextState)
		end, {
			inclusive = true,
		})

		return function()
			unsubscribe()
			stop()
		end
	end, {})

	React.useEffect(function()
		if consoleState.visible == true then
			followOutputRef.current = true
			task.defer(function()
				local scrollFrame = scrollRef.current
				if scrollFrame == nil or scrollFrame.Parent == nil then
					return
				end
				scrollToBottom(scrollFrame)
			end)
		else
			outputHoveredRef.current = false
			followOutputRef.current = true
		end
	end, { consoleState.visible })

	local zIndex = props.zIndex or 210
	local entries = consoleState.serviceState.entries
	local showOutputPanel = #entries > 0 or consoleState.serviceState.canUseCommands ~= true
	local localPromptPrefix = buildPromptPrefix(localPlayer.Name, consoleState.serviceState.localRoleId)
	local outputPrefixWidth = measurePromptPrefixWidth(localPromptPrefix)

	React.useEffect(function()
		if consoleState.visible ~= true or not showOutputPanel then
			return
		end
		task.defer(function()
			local scrollFrame = scrollRef.current
			local contentFrame = scrollContentRef.current
			if scrollFrame == nil or scrollFrame.Parent == nil then
				return
			end
			refreshScrollMetrics(scrollFrame, contentFrame)
			if followOutputRef.current then
				scrollToBottom(scrollFrame)
				refreshScrollMetrics(scrollFrame, contentFrame)
			end
		end)
	end, { consoleState.visible, showOutputPanel, #entries, consoleState.serviceState.canUseCommands })

	React.useEffect(function()
		if consoleState.visible ~= true or not showOutputPanel then
			return
		end

		local connection = UserInputService.InputChanged:Connect(function(inputObject: InputObject)
			if inputObject.UserInputType ~= Enum.UserInputType.MouseWheel then
				return
			end
			if not outputHoveredRef.current then
				return
			end

			local scrollFrame = scrollRef.current
			if scrollFrame == nil or scrollFrame.Parent == nil then
				return
			end

			local wheelDelta = inputObject.Position.Z
			if wheelDelta == 0 then
				return
			end

			local maxScrollY = getMaxScrollY(scrollFrame)
			if maxScrollY <= 0 then
				followOutputRef.current = true
				return
			end

			local nextScrollY = math.clamp(
				scrollFrame.CanvasPosition.Y - wheelDelta * OUTPUT_SCROLL_WHEEL_STEP,
				0,
				maxScrollY
			)
			scrollFrame.CanvasPosition = Vector2.new(scrollFrame.CanvasPosition.X, nextScrollY)
			followOutputRef.current = (maxScrollY - nextScrollY) <= OUTPUT_AUTO_SCROLL_SNAP_PADDING
			refreshScrollMetrics(scrollFrame, scrollContentRef.current)
		end)

		return function()
			connection:Disconnect()
		end
	end, { consoleState.visible, showOutputPanel })

	if props.visible == false or consoleState.visible ~= true then
		return nil
	end

	local canScrollOutput = scrollMetrics.contentHeight > (scrollMetrics.viewportHeight + 1)
	local scrollTrackHeight = OUTPUT_PANEL_HEIGHT - OUTPUT_SCROLL_TRACK_VERTICAL_PADDING * 2
	local minimumThumbScale = math.min(1, 24 / scrollTrackHeight)
	local scrollThumbSizeScale = if canScrollOutput and scrollMetrics.contentHeight > 0
		then math.clamp(scrollMetrics.viewportHeight / scrollMetrics.contentHeight, minimumThumbScale, 1)
		else 1
	local scrollRange = math.max(1, scrollMetrics.contentHeight - scrollMetrics.viewportHeight)
	local scrollThumbPositionScale = if canScrollOutput
		then (scrollMetrics.canvasPositionY / scrollRange) * (1 - scrollThumbSizeScale)
		else 0

	local outputChildren = {
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
		}),
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
	}

	for index, entry in entries do
		if entry.kind == "command" and entry.userName ~= nil and entry.userName ~= "" then
			outputChildren[`Entry_{entry.id}_{index}`] = e("Frame", {
				Name = "CommandEntry",
				Size = UDim2.new(1, -4, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = zIndex + 3,
				LayoutOrder = index,
			}, {
				Prefix = e(TextLabel, {
					name = "Prefix",
					text = buildPromptPrefix(entry.userName, entry.roleId),
					size = UDim2.fromOffset(outputPrefixWidth, 0),
					automaticSize = Enum.AutomaticSize.Y,
					backgroundTransparency = 1,
					font = Enum.Font.Code,
					textSize = OUTPUT_PREFIX_TEXT_SIZE,
					textColor3 = PROMPT_PREFIX_COLOR,
					textWrapped = true,
					textXAlignment = Enum.TextXAlignment.Left,
					textYAlignment = Enum.TextYAlignment.Top,
					zIndex = zIndex + 4,
				}),
				Text = e(TextLabel, {
					name = "Text",
					text = entry.text,
					size = UDim2.new(1, -(outputPrefixWidth + OUTPUT_PREFIX_GAP), 0, 0),
					position = UDim2.fromOffset(outputPrefixWidth + OUTPUT_PREFIX_GAP, 0),
					automaticSize = Enum.AutomaticSize.Y,
					backgroundTransparency = 1,
					font = Enum.Font.Code,
					textSize = OUTPUT_PREFIX_TEXT_SIZE,
					textColor3 = resolveKindColor(entry),
					textWrapped = true,
					textXAlignment = Enum.TextXAlignment.Left,
					textYAlignment = Enum.TextYAlignment.Top,
					zIndex = zIndex + 4,
				}),
			})
		else
			outputChildren[`Entry_{entry.id}_{index}`] = e(TextLabel, {
				name = "Entry",
				text = buildEntryRichText(entry),
				richText = true,
				size = UDim2.new(1, -4, 0, 0),
				automaticSize = Enum.AutomaticSize.Y,
				backgroundTransparency = 1,
				font = Enum.Font.Code,
				textSize = 13,
				textColor3 = resolveKindColor(entry),
				textWrapped = true,
				textXAlignment = Enum.TextXAlignment.Left,
				textYAlignment = Enum.TextYAlignment.Top,
				zIndex = zIndex + 3,
				layoutOrder = index,
			})
		end
	end

	if consoleState.serviceState.canUseCommands ~= true then
		outputChildren.OwnerHint = e(TextLabel, {
			name = "OwnerHint",
			text = if consoleState.serviceState.ownerName ~= ""
				then ("Only %s can execute developer commands in this server."):format(consoleState.serviceState.ownerName)
				else "Only the resolved owner can execute developer commands in this server.",
			size = UDim2.new(1, -4, 0, 0),
			automaticSize = Enum.AutomaticSize.Y,
			backgroundTransparency = 1,
			font = Enum.Font.Gotham,
			textSize = 12,
			textColor3 = Color3.fromRGB(255, 218, 117),
			textWrapped = true,
			textXAlignment = Enum.TextXAlignment.Left,
			textYAlignment = Enum.TextYAlignment.Top,
			zIndex = zIndex + 3,
			layoutOrder = #entries + 1,
		})
	end

	return e("Frame", {
		Name = "DevConsoleScreen",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		LayoutOrder = props.layoutOrder or 980,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		Selectable = false,
		ZIndex = zIndex,
	}, {
		OutputPanel = if showOutputPanel
			then e("Frame", {
				Name = "OutputPanel",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -(PROMPT_BOTTOM_INSET + PROMPT_HEIGHT + 10)),
				Size = UDim2.new(1, -24, 0, OUTPUT_PANEL_HEIGHT),
				BackgroundColor3 = Color3.fromRGB(58, 58, 58),
				BackgroundTransparency = OUTPUT_PANEL_BACKGROUND_TRANSPARENCY,
				BorderSizePixel = 0,
				ZIndex = zIndex + 1,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 2),
				}),
				Stroke = e("UIStroke", {
					Color = Color3.fromRGB(117, 126, 139),
					Transparency = 0.55,
					Thickness = 1,
				}),
				Scroll = e("ScrollingFrame", {
					Name = "Scroll",
					ref = scrollRef,
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Active = true,
					Selectable = true,
					ScrollingEnabled = true,
					CanvasSize = UDim2.new(0, 0, 0, 0),
					ScrollBarThickness = 0,
					ScrollBarImageColor3 = Color3.fromRGB(150, 156, 167),
					ScrollBarImageTransparency = 1,
					VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
					ScrollingDirection = Enum.ScrollingDirection.Y,
					ZIndex = zIndex + 2,
					[React.Change.CanvasPosition] = function(rbx: ScrollingFrame)
						followOutputRef.current = isNearScrollBottom(rbx)
						refreshScrollMetrics(rbx, scrollContentRef.current)
					end,
					[React.Change.AbsoluteWindowSize] = function(rbx: ScrollingFrame)
						refreshScrollMetrics(rbx, scrollContentRef.current)
					end,
					[React.Event.MouseEnter] = function()
						outputHoveredRef.current = true
					end,
					[React.Event.MouseLeave] = function()
						outputHoveredRef.current = false
					end,
				}, {
					Content = e("Frame", {
						Name = "Content",
						ref = scrollContentRef,
						Size = UDim2.new(
							1,
							-(OUTPUT_CONTENT_WIDTH_PADDING + OUTPUT_SCROLL_TRACK_WIDTH + OUTPUT_SCROLL_TRACK_RIGHT_PADDING + 2),
							0,
							0
						),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						ZIndex = zIndex + 2,
						[React.Change.AbsoluteSize] = function(rbx: Frame)
							refreshScrollMetrics(scrollRef.current, rbx)
						end,
					}, outputChildren),
				}),
				ScrollTrack = if canScrollOutput
					then e("Frame", {
						Name = "ScrollTrack",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -OUTPUT_SCROLL_TRACK_RIGHT_PADDING, 0, OUTPUT_SCROLL_TRACK_VERTICAL_PADDING),
						Size = UDim2.new(0, OUTPUT_SCROLL_TRACK_WIDTH, 1, -(OUTPUT_SCROLL_TRACK_VERTICAL_PADDING * 2)),
						BackgroundColor3 = Color3.fromRGB(132, 140, 153),
						BackgroundTransparency = 0.72,
						BorderSizePixel = 0,
						ZIndex = zIndex + 3,
					}, {
						Corner = e("UICorner", {
							CornerRadius = UDim.new(1, 0),
						}),
						Thumb = e("Frame", {
							Name = "Thumb",
							Size = UDim2.new(1, 0, scrollThumbSizeScale, 0),
							Position = UDim2.new(0, 0, scrollThumbPositionScale, 0),
							BackgroundColor3 = Color3.fromRGB(198, 206, 219),
							BackgroundTransparency = 0.08,
							BorderSizePixel = 0,
							ZIndex = zIndex + 4,
						}, {
							Corner = e("UICorner", {
								CornerRadius = UDim.new(1, 0),
							}),
						}),
					})
					else nil,
			})
			else nil,
		Prompt = e(Prompt, {
			visible = consoleState.visible,
			zIndex = zIndex + 10,
			promptText = consoleState.promptText,
			suggestions = consoleState.suggestions,
			selectedSuggestionIndex = consoleState.selectedSuggestionIndex,
			localRoleId = consoleState.serviceState.localRoleId,
			canUseCommands = consoleState.serviceState.canUseCommands,
			bottomInset = PROMPT_BOTTOM_INSET,
			onPromptTextChanged = function(nextText: string)
				devConsoleThunks.setPromptText(nextText)
			end,
			onSubmit = function(): boolean
				return devConsoleThunks.submitPrompt()
			end,
			onApplySelectedSuggestion = function(indexRaw: any?)
				devConsoleThunks.applySelectedSuggestion(indexRaw)
			end,
			onCycleSuggestion = function(delta: number)
				devConsoleThunks.cycleSuggestion(delta)
			end,
			onCycleHistory = function(delta: number)
				devConsoleThunks.stepSelection(delta)
			end,
			onClose = function()
				devConsoleThunks.close()
			end,
		}),
	})
end

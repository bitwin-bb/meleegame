--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local React = require(ReplicatedStorage.Packages.React)
local Role = require(ReplicatedStorage.Shared.Services.DevPromptService.Role)
local TextLabel = require(ReplicatedStorage.UI.core.primitives.TextLabel)
local devConsoleSlice = require(ReplicatedStorage.UI.features.devConsole.state.devConsoleSlice)

type CommandSuggestion = devConsoleSlice.CommandSuggestion
type RoleId = Role.RoleId

type PromptProps = {
	visible: boolean?,
	zIndex: number?,
	promptText: string,
	suggestions: { CommandSuggestion },
	selectedSuggestionIndex: number?,
	localRoleId: RoleId,
	canUseCommands: boolean,
	onPromptTextChanged: (nextText: string) -> (),
	onSubmit: () -> boolean,
	onApplySelectedSuggestion: (indexRaw: any?) -> (),
	onCycleSuggestion: (delta: number) -> (),
	onCycleHistory: (delta: number) -> (),
	onClose: () -> (),
	bottomInset: number?,
}

local e: typeof(React.createElement) = React.createElement

local PROMPT_HEIGHT = 36
local PROMPT_SIDE_MARGIN = 12
local PROMPT_PREFIX_TEXT_SIZE = 13
local PROMPT_PREFIX_MIN_WIDTH = 136
local PROMPT_PREFIX_MAX_WIDTH = 248
local PROMPT_PREFIX_GAP = 8
local DEFAULT_BOTTOM_INSET = 74
local SUGGESTIONS_BOTTOM_GAP = 12
local PROMPT_BAR_BACKGROUND_TRANSPARENCY = 0.34
local PROMPT_PREFIX_COLOR = Color3.fromRGB(255, 226, 98)

local function resolvePromptFlavor(roleId: RoleId): string
	if roleId == "Member" then
		return "default"
	end
	return "developer"
end

local function buildPromptPrefix(userName: string, roleId: RoleId): string
	return ("%s-%s$"):format(userName, resolvePromptFlavor(roleId))
end

local function measurePromptPrefixWidth(prefixText: string): number
	local measuredSize = TextService:GetTextSize(
		prefixText,
		PROMPT_PREFIX_TEXT_SIZE,
		Enum.Font.Code,
		Vector2.new(1000, PROMPT_HEIGHT)
	)
	return math.clamp(math.ceil(measuredSize.X) + 4, PROMPT_PREFIX_MIN_WIDTH, PROMPT_PREFIX_MAX_WIDTH)
end

local function SuggestionRow(props: {
	layoutOrder: number,
	zIndex: number,
	suggestion: CommandSuggestion,
	selected: boolean,
	onActivated: () -> (),
})
	local suggestion = props.suggestion
	local selected = props.selected
	return e("TextButton", {
		Name = `Suggestion_{suggestion.name}`,
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = if selected then Color3.fromRGB(84, 110, 142) else Color3.fromRGB(58, 58, 58),
		BackgroundTransparency = if selected then 0.08 else 0.32,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		Text = "",
		AutoButtonColor = false,
		ZIndex = props.zIndex,
		[React.Event.Activated] = props.onActivated,
	}, {
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
			PaddingTop = UDim.new(0, 2),
			PaddingBottom = UDim.new(0, 2),
		}),
		Label = e(TextLabel, {
			name = "Label",
			text = suggestion.name,
			size = UDim2.fromScale(1, 1),
			backgroundTransparency = 1,
			font = Enum.Font.Code,
			textSize = 13,
			textColor3 = if selected then Color3.fromRGB(160, 226, 255) else Color3.fromRGB(232, 236, 242),
			textXAlignment = Enum.TextXAlignment.Left,
			textYAlignment = Enum.TextYAlignment.Center,
			zIndex = props.zIndex + 1,
		}),
	})
end

return function(props: PromptProps): React.ReactNode
	if props.visible == false then
		return nil
	end

	local localPlayer = Players.LocalPlayer
	local zIndex = props.zIndex or 210
	local bottomInset = props.bottomInset or DEFAULT_BOTTOM_INSET
	local inputRef = React.useRef(nil :: TextBox?)
	local suggestions = props.suggestions
	local selectedSuggestionIndex = props.selectedSuggestionIndex or 1
	local selectedSuggestion = suggestions[selectedSuggestionIndex]
	local promptPrefix = buildPromptPrefix(localPlayer.Name, props.localRoleId)
	local promptPrefixWidth = measurePromptPrefixWidth(promptPrefix)

	React.useEffect(function()
		if props.visible ~= true then
			return
		end
		task.defer(function()
			local input = inputRef.current
			if input ~= nil and input.Parent ~= nil then
				input:CaptureFocus()
			end
		end)
	end, { props.visible })

	local suggestionRows = {}
	for index, suggestion in suggestions do
		suggestionRows[`Suggestion_{suggestion.name}_{index}`] = e(SuggestionRow, {
			layoutOrder = index,
			zIndex = zIndex + 6,
			suggestion = suggestion,
			selected = index == selectedSuggestionIndex,
			onActivated = function()
				props.onApplySelectedSuggestion(index)
				task.defer(function()
					local input = inputRef.current
					if input ~= nil and input.Parent ~= nil then
						input:CaptureFocus()
					end
				end)
			end,
		})
	end

	return e("Frame", {
		Name = "DevConsolePromptRoot",
		Size = UDim2.new(1, 0, 0, 0),
		Position = UDim2.new(0.5, 0, 1, -bottomInset),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Suggestions = if #suggestions > 0
			then e("Frame", {
				Name = "Suggestions",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(
					0,
					promptPrefixWidth + PROMPT_PREFIX_GAP + PROMPT_SIDE_MARGIN,
					0,
					-(PROMPT_HEIGHT + SUGGESTIONS_BOTTOM_GAP)
				),
				Size = UDim2.fromOffset(264, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = Color3.fromRGB(72, 72, 72),
				BackgroundTransparency = 0.14,
				BorderSizePixel = 0,
				ZIndex = zIndex + 3,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 2),
				}),
				Stroke = e("UIStroke", {
					Color = Color3.fromRGB(118, 128, 144),
					Transparency = 0.5,
					Thickness = 1,
				}),
				Header = e("Frame", {
					Name = "Header",
					Size = UDim2.new(1, 0, 0, 56),
					BackgroundColor3 = Color3.fromRGB(63, 63, 63),
					BackgroundTransparency = 0.08,
					BorderSizePixel = 0,
					ZIndex = zIndex + 4,
				}, {
					Padding = e("UIPadding", {
						PaddingLeft = UDim.new(0, 10),
						PaddingRight = UDim.new(0, 10),
						PaddingTop = UDim.new(0, 8),
						PaddingBottom = UDim.new(0, 8),
					}),
					Title = e(TextLabel, {
						name = "Title",
						text = if selectedSuggestion ~= nil then selectedSuggestion.name else "developer console",
						size = UDim2.new(1, 0, 0, 18),
						backgroundTransparency = 1,
						font = Enum.Font.Code,
						textSize = 16,
						textColor3 = Color3.fromRGB(255, 255, 255),
						textXAlignment = Enum.TextXAlignment.Left,
						textYAlignment = Enum.TextYAlignment.Top,
						zIndex = zIndex + 5,
						effects = {
							shadow = {
								enabled = true,
								color = Color3.fromRGB(0, 0, 0),
								transparency = 0.5,
								offset = Vector2.new(1, 1),
								layers = 1,
							},
						},
					}),
					Description = e(TextLabel, {
						name = "Description",
						text = if selectedSuggestion ~= nil and selectedSuggestion.description ~= ""
							then selectedSuggestion.description
							else "Use Tab to autocomplete and Enter to run the current command.",
						size = UDim2.new(1, 0, 0, 24),
						position = UDim2.fromOffset(0, 22),
						backgroundTransparency = 1,
						font = Enum.Font.Gotham,
						textSize = 12,
						textColor3 = Color3.fromRGB(220, 224, 231),
						textTransparency = 0.05,
						textWrapped = true,
						textXAlignment = Enum.TextXAlignment.Left,
						textYAlignment = Enum.TextYAlignment.Top,
						zIndex = zIndex + 5,
					}),
				}),
				Usage = if selectedSuggestion ~= nil
					then e(TextLabel, {
						name = "Usage",
						text = selectedSuggestion.usage,
						size = UDim2.new(1, -16, 0, 16),
						position = UDim2.fromOffset(8, 58),
						backgroundTransparency = 1,
						font = Enum.Font.Code,
						textSize = 11,
						textColor3 = Color3.fromRGB(196, 244, 255),
						textXAlignment = Enum.TextXAlignment.Left,
						textYAlignment = Enum.TextYAlignment.Center,
						zIndex = zIndex + 5,
					})
					else nil,
				List = e("Frame", {
					Name = "List",
					Position = UDim2.fromOffset(0, if selectedSuggestion ~= nil then 80 else 60),
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ZIndex = zIndex + 4,
				}, {
					ListLayout = e("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					Suggestions = e(React.Fragment, nil, suggestionRows),
				}),
			})
			else nil,
		PromptBar = e("Frame", {
			Name = "PromptBar",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.new(1, -(PROMPT_SIDE_MARGIN * 2), 0, PROMPT_HEIGHT),
			BackgroundColor3 = Color3.fromRGB(80, 80, 80),
			BackgroundTransparency = PROMPT_BAR_BACKGROUND_TRANSPARENCY,
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, {
			Stroke = e("UIStroke", {
				Color = Color3.fromRGB(135, 143, 156),
				Transparency = 0.55,
				Thickness = 1,
			}),
			PromptPadding = e("UIPadding", {
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
			}),
			Prefix = e(TextLabel, {
				name = "Prefix",
				text = promptPrefix,
				size = UDim2.fromOffset(promptPrefixWidth, PROMPT_HEIGHT),
				backgroundTransparency = 1,
				font = Enum.Font.Code,
				textSize = PROMPT_PREFIX_TEXT_SIZE,
				textXAlignment = Enum.TextXAlignment.Left,
				textYAlignment = Enum.TextYAlignment.Center,
				zIndex = zIndex + 2,
				textColor3 = PROMPT_PREFIX_COLOR,
			}),
			Input = e("TextBox", {
				Name = "Input",
				ref = inputRef,
				Size = UDim2.new(1, -(promptPrefixWidth + PROMPT_PREFIX_GAP + 6), 1, 0),
				Position = UDim2.fromOffset(promptPrefixWidth + PROMPT_PREFIX_GAP, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClearTextOnFocus = false,
				Font = Enum.Font.Code,
				ShouldEmitTabEvents = true,
				ShouldEmitUpAndDownArrowEvents = true,
				Text = props.promptText,
				PlaceholderText = if props.canUseCommands
					then "Type a developer command..."
					else "Developer commands are owner-only in this server.",
				TextColor3 = Color3.fromRGB(245, 248, 255),
				PlaceholderColor3 = Color3.fromRGB(176, 182, 194),
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				ZIndex = zIndex + 2,
				[React.Change.Text] = function(rbx: TextBox)
					props.onPromptTextChanged(rbx.Text)
				end,
				[React.Event.FocusLost] = function(_rbx: TextBox, enterPressed: boolean)
					if enterPressed then
						local didSubmit = props.onSubmit()
						if didSubmit then
							local input = inputRef.current
							if input ~= nil then
								input.Text = ""
							end
							task.defer(function()
								local currentInput = inputRef.current
								if currentInput ~= nil and currentInput.Parent ~= nil then
									currentInput:CaptureFocus()
								end
							end)
						end
					end
				end,
				[React.Event.InputBegan] = function(_rbx: GuiObject, inputObject: InputObject)
					if inputObject.KeyCode == Enum.KeyCode.Tab then
						props.onApplySelectedSuggestion(nil)
						task.defer(function()
							local input = inputRef.current
							if input ~= nil and input.Parent ~= nil then
								input:CaptureFocus()
							end
						end)
					elseif inputObject.KeyCode == Enum.KeyCode.Up then
						props.onCycleSuggestion(-1)
					elseif inputObject.KeyCode == Enum.KeyCode.Down then
						props.onCycleSuggestion(1)
					elseif inputObject.KeyCode == Enum.KeyCode.PageUp then
						props.onCycleHistory(-1)
					elseif inputObject.KeyCode == Enum.KeyCode.PageDown then
						props.onCycleHistory(1)
					elseif inputObject.KeyCode == Enum.KeyCode.Escape then
						props.onClose()
					end
				end,
			}),
		}),
	})
end

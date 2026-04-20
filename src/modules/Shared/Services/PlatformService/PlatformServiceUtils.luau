--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ImageIds = require(script:FindFirstAncestor("game").Client.UI.core.ImageIds)

local PlatformServiceUtils = {}

export type PlatformKind = "KeyboardMouse" | "Gamepad" | "Touch"
export type DeviceClass = "Phone" | "Tablet" | "Desktop" | "Console"

export type CapabilitySnapshot = {
	touchEnabled: boolean,
	keyboardEnabled: boolean,
	mouseEnabled: boolean,
	gamepadEnabled: boolean,
	basePrimaryInputType: string?,
}

export type PlatformState = CapabilitySnapshot & {
	platform: PlatformKind,
	deviceClass: DeviceClass,
	preferredInputName: string,
	lastInputTypeName: string,
	viewport: Vector2,
	isTenFootInterface: boolean,
}

export type ActionBinding = {
	keyCode: Enum.KeyCode?,
	inputType: Enum.UserInputType?,
	playerAction: Enum.PlayerActions?,
	axis: "X" | "Y"?,
	axisSign: number?,
	deadzone: number?,
	label: string?,
	icon: string?,
}

export type ActionDefinition = {
	actionName: string,
	displayName: string,
	description: string?,
	priority: number?,
	consume: boolean?,
	allowWhileTyping: boolean?,
	blockWhenPointerOverGui: boolean?,
	blockWhenGuiSelected: boolean?,
	bindingsByPlatform: { [string]: { ActionBinding } }?,
	promptBindingsByPlatform: { [string]: { ActionBinding } }?,
	touchPrompt: string?,
}

export type PromptBinding = {
	actionName: string,
	displayName: string,
	platform: PlatformKind,
	deviceClass: DeviceClass,
	text: string,
	icon: string?,
	keyCode: Enum.KeyCode?,
	inputType: Enum.UserInputType?,
	playerAction: Enum.PlayerActions?,
}

local KEYCODE_TEXT_OVERRIDES: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.MouseLeftButton] = "LMB",
	[Enum.KeyCode.MouseRightButton] = "RMB",
	[Enum.KeyCode.MouseMiddleButton] = "MMB",
	[Enum.KeyCode.Space] = "Space",
	[Enum.KeyCode.Return] = "Enter",
	[Enum.KeyCode.LeftControl] = "Ctrl",
	[Enum.KeyCode.RightControl] = "Ctrl",
	[Enum.KeyCode.LeftShift] = "Shift",
	[Enum.KeyCode.RightShift] = "Shift",
	[Enum.KeyCode.LeftAlt] = "Alt",
	[Enum.KeyCode.RightAlt] = "Alt",
	[Enum.KeyCode.ButtonA] = "A",
	[Enum.KeyCode.ButtonB] = "B",
	[Enum.KeyCode.ButtonX] = "X",
	[Enum.KeyCode.ButtonY] = "Y",
	[Enum.KeyCode.ButtonL1] = "LB",
	[Enum.KeyCode.ButtonR1] = "RB",
	[Enum.KeyCode.ButtonL2] = "LT",
	[Enum.KeyCode.ButtonR2] = "RT",
	[Enum.KeyCode.ButtonL3] = "L3",
	[Enum.KeyCode.ButtonR3] = "R3",
	[Enum.KeyCode.ButtonStart] = "Menu",
	[Enum.KeyCode.ButtonSelect] = "View",
	[Enum.KeyCode.DPadUp] = "D-Pad Up",
	[Enum.KeyCode.DPadDown] = "D-Pad Down",
	[Enum.KeyCode.DPadLeft] = "D-Pad Left",
	[Enum.KeyCode.DPadRight] = "D-Pad Right",
	[Enum.KeyCode.Thumbstick1] = "L Stick",
	[Enum.KeyCode.Thumbstick2] = "R Stick",
	[Enum.KeyCode.Zero] = "0",
	[Enum.KeyCode.One] = "1",
	[Enum.KeyCode.Two] = "2",
	[Enum.KeyCode.Three] = "3",
	[Enum.KeyCode.Four] = "4",
	[Enum.KeyCode.Five] = "5",
	[Enum.KeyCode.Six] = "6",
	[Enum.KeyCode.Seven] = "7",
	[Enum.KeyCode.Eight] = "8",
	[Enum.KeyCode.Nine] = "9",
}

local PLAYER_ACTION_TEXT_OVERRIDES: { [Enum.PlayerActions]: string } = {
	[Enum.PlayerActions.CharacterLeft] = "Move Left",
	[Enum.PlayerActions.CharacterRight] = "Move Right",
	[Enum.PlayerActions.CharacterForward] = "Move Up",
	[Enum.PlayerActions.CharacterBackward] = "Move Down",
}

local HINTS = if typeof((ImageIds :: any).hints) == "table" then (ImageIds :: any).hints else {}

local DEFAULT_GAMEPAD_FAMILY = "xbox"

local ACTIONS = {
	MOVE = "Player.Move",
	MOVE_LEFT = "Player.MoveLeft",
	MOVE_RIGHT = "Player.MoveRight",
	MOVE_VERTICAL = "Player.MoveVertical",
	MOVE_UP = "Player.MoveUp",
	MOVE_DOWN = "Player.MoveDown",
	JUMP = "Player.Jump",
	BUILD_PRIMARY = "BuildService.Primary",
	MELEE_ATTACK = "MeleeService.Attack",
	MAGIC_CAST = "MagicService.Cast",
	HOTBAR_SELECT = "Inventory.SelectHotbar",
	HOTBAR_CYCLE = "Inventory.CycleHotbar",
	PLACE_DEPLOYABLE = "Inventory.PlaceDeployable",
}

PlatformServiceUtils.ACTIONS = ACTIONS

local function cloneBinding(binding: ActionBinding): ActionBinding
	return {
		keyCode = binding.keyCode,
		inputType = binding.inputType,
		playerAction = binding.playerAction,
		axis = binding.axis,
		axisSign = binding.axisSign,
		deadzone = binding.deadzone,
		label = binding.label,
		icon = binding.icon,
	}
end

local function cloneBindings(bindingsRaw: { ActionBinding }?): { ActionBinding }
	local output: { ActionBinding } = {}
	if typeof(bindingsRaw) ~= "table" then
		return output
	end
	for index = 1, #bindingsRaw do
		local binding = bindingsRaw[index]
		if typeof(binding) == "table" then
			output[#output + 1] = cloneBinding(binding)
		end
	end
	return output
end

local function cloneActionDefinition(definition: ActionDefinition): ActionDefinition
	local bindingsByPlatform = {}
	if typeof(definition.bindingsByPlatform) == "table" then
		for platform, bindings in definition.bindingsByPlatform do
			bindingsByPlatform[platform] = cloneBindings(bindings)
		end
	end
	local promptBindingsByPlatform = {}
	if typeof(definition.promptBindingsByPlatform) == "table" then
		for platform, bindings in definition.promptBindingsByPlatform do
			promptBindingsByPlatform[platform] = cloneBindings(bindings)
		end
	end
	return {
		actionName = definition.actionName,
		displayName = definition.displayName,
		description = definition.description,
		priority = definition.priority,
		consume = definition.consume,
		allowWhileTyping = definition.allowWhileTyping,
		blockWhenPointerOverGui = definition.blockWhenPointerOverGui,
		blockWhenGuiSelected = definition.blockWhenGuiSelected,
		bindingsByPlatform = bindingsByPlatform,
		promptBindingsByPlatform = promptBindingsByPlatform,
		touchPrompt = definition.touchPrompt,
	}
end

local function formatEnumName(name: string): string
	if #name <= 1 then
		return string.upper(name)
	end
	local withSpaces = string.gsub(name, "(%l)(%u)", "%1 %2")
	withSpaces = string.gsub(withSpaces, "(%u)(%u%l)", "%1 %2")
	return withSpaces
end

local function preferredInputName(preferredInputRaw: any): string
	if typeof(preferredInputRaw) == "EnumItem" then
		return preferredInputRaw.Name
	end
	return ""
end

local function lastInputTypeName(lastInputTypeRaw: any): string
	if typeof(lastInputTypeRaw) == "EnumItem" then
		return lastInputTypeRaw.Name
	end
	return ""
end

local function preferredLooksLikeGamepad(preferredInputRaw: any): boolean
	local name = preferredInputName(preferredInputRaw)
	return string.find(name, "Gamepad", 1, true) ~= nil
end

local function preferredLooksLikeTouch(preferredInputRaw: any): boolean
	local name = preferredInputName(preferredInputRaw)
	return string.find(name, "Touch", 1, true) ~= nil
end

local function preferredLooksLikeKeyboardMouse(preferredInputRaw: any): boolean
	local name = preferredInputName(preferredInputRaw)
	return string.find(name, "Keyboard", 1, true) ~= nil or string.find(name, "Mouse", 1, true) ~= nil
end

local function clampNumber(valueRaw: any, fallback: number, minValue: number, maxValue: number): number
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then valueRaw else fallback
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function sanitizeViewport(viewportRaw: any): Vector2
	if typeof(viewportRaw) == "Vector2" then
		return Vector2.new(math.max(1, viewportRaw.X), math.max(1, viewportRaw.Y))
	end
	return Vector2.new(1920, 1080)
end

function PlatformServiceUtils.IsGamepadInputType(inputTypeRaw: any): boolean
	if typeof(inputTypeRaw) ~= "EnumItem" then
		return false
	end
	return string.sub((inputTypeRaw :: Enum.UserInputType).Name, 1, 7) == "Gamepad"
end

function PlatformServiceUtils.IsTouchInputType(inputTypeRaw: any): boolean
	return inputTypeRaw == Enum.UserInputType.Touch
end

function PlatformServiceUtils.IsKeyboardInputType(inputTypeRaw: any): boolean
	return inputTypeRaw == Enum.UserInputType.Keyboard
end

function PlatformServiceUtils.IsMouseInputType(inputTypeRaw: any): boolean
	return inputTypeRaw == Enum.UserInputType.MouseButton1
		or inputTypeRaw == Enum.UserInputType.MouseButton2
		or inputTypeRaw == Enum.UserInputType.MouseButton3
		or inputTypeRaw == Enum.UserInputType.MouseMovement
		or inputTypeRaw == Enum.UserInputType.MouseWheel
end

function PlatformServiceUtils.IsPointerInputType(inputTypeRaw: any): boolean
	return PlatformServiceUtils.IsMouseInputType(inputTypeRaw) or PlatformServiceUtils.IsTouchInputType(inputTypeRaw)
end

function PlatformServiceUtils.ResolvePlatformKind(
	preferredInputRaw: any,
	lastInputTypeRaw: any,
	capabilitiesRaw: CapabilitySnapshot?
): PlatformKind
	local capabilities = if typeof(capabilitiesRaw) == "table"
		then capabilitiesRaw
		else {
			touchEnabled = false,
			keyboardEnabled = true,
			mouseEnabled = true,
			gamepadEnabled = false,
			basePrimaryInputType = nil,
		}

	if preferredLooksLikeGamepad(preferredInputRaw) then
		return "Gamepad"
	end
	if preferredLooksLikeTouch(preferredInputRaw) then
		return "Touch"
	end
	if preferredLooksLikeKeyboardMouse(preferredInputRaw) then
		return "KeyboardMouse"
	end

	if PlatformServiceUtils.IsGamepadInputType(lastInputTypeRaw) then
		return "Gamepad"
	end
	if PlatformServiceUtils.IsTouchInputType(lastInputTypeRaw) then
		return "Touch"
	end
	if
		PlatformServiceUtils.IsKeyboardInputType(lastInputTypeRaw)
		or PlatformServiceUtils.IsMouseInputType(lastInputTypeRaw)
	then
		return "KeyboardMouse"
	end

	if capabilities.basePrimaryInputType == "Gamepad" then
		return "Gamepad"
	end
	if capabilities.basePrimaryInputType == "Touch" then
		return "Touch"
	end
	if capabilities.touchEnabled and not capabilities.keyboardEnabled and not capabilities.mouseEnabled then
		return "Touch"
	end
	if capabilities.gamepadEnabled and not capabilities.keyboardEnabled and not capabilities.mouseEnabled then
		return "Gamepad"
	end

	return "KeyboardMouse"
end

function PlatformServiceUtils.ResolveDeviceClass(
	platformKindRaw: any,
	viewportRaw: any,
	capabilitiesRaw: CapabilitySnapshot?,
	isTenFootInterfaceRaw: any
): DeviceClass
	local platformKind = if platformKindRaw == "Touch" or platformKindRaw == "Gamepad"
		then platformKindRaw
		else "KeyboardMouse"
	local viewport = sanitizeViewport(viewportRaw)
	local capabilities = if typeof(capabilitiesRaw) == "table"
		then capabilitiesRaw
		else {
			touchEnabled = false,
			keyboardEnabled = true,
			mouseEnabled = true,
			gamepadEnabled = false,
			basePrimaryInputType = nil,
		}
	local isTenFootInterface = isTenFootInterfaceRaw == true

	if platformKind == "Gamepad" or (isTenFootInterface and capabilities.gamepadEnabled) then
		return "Console"
	end

	if platformKind == "Touch" then
		local minAxis = math.min(viewport.X, viewport.Y)
		local maxAxis = math.max(viewport.X, viewport.Y)
		if minAxis >= 700 or maxAxis >= 1280 then
			return "Tablet"
		end
		return "Phone"
	end

	return "Desktop"
end

function PlatformServiceUtils.CreatePlatformState(
	preferredInputRaw: any,
	lastInputTypeRaw: any,
	capabilitiesRaw: CapabilitySnapshot?,
	viewportRaw: any,
	isTenFootInterfaceRaw: any
): PlatformState
	local capabilities = if typeof(capabilitiesRaw) == "table"
		then capabilitiesRaw
		else {
			touchEnabled = false,
			keyboardEnabled = true,
			mouseEnabled = true,
			gamepadEnabled = false,
			basePrimaryInputType = nil,
		}
	local viewport = sanitizeViewport(viewportRaw)
	local platform = PlatformServiceUtils.ResolvePlatformKind(preferredInputRaw, lastInputTypeRaw, capabilities)
	local deviceClass = PlatformServiceUtils.ResolveDeviceClass(platform, viewport, capabilities, isTenFootInterfaceRaw)
	return {
		platform = platform,
		deviceClass = deviceClass,
		preferredInputName = preferredInputName(preferredInputRaw),
		lastInputTypeName = lastInputTypeName(lastInputTypeRaw),
		viewport = viewport,
		isTenFootInterface = isTenFootInterfaceRaw == true,
		touchEnabled = capabilities.touchEnabled == true,
		keyboardEnabled = capabilities.keyboardEnabled == true,
		mouseEnabled = capabilities.mouseEnabled == true,
		gamepadEnabled = capabilities.gamepadEnabled == true,
		basePrimaryInputType = capabilities.basePrimaryInputType,
	}
end

function PlatformServiceUtils.PlatformStatesEqual(a: PlatformState?, b: PlatformState?): boolean
	if a == nil or b == nil then
		return false
	end
	return a.platform == b.platform
		and a.deviceClass == b.deviceClass
		and a.preferredInputName == b.preferredInputName
		and a.lastInputTypeName == b.lastInputTypeName
		and a.viewport == b.viewport
		and a.isTenFootInterface == b.isTenFootInterface
		and a.touchEnabled == b.touchEnabled
		and a.keyboardEnabled == b.keyboardEnabled
		and a.mouseEnabled == b.mouseEnabled
		and a.gamepadEnabled == b.gamepadEnabled
		and a.basePrimaryInputType == b.basePrimaryInputType
end

function PlatformServiceUtils.ClonePlatformState(state: PlatformState): PlatformState
	return {
		platform = state.platform,
		deviceClass = state.deviceClass,
		preferredInputName = state.preferredInputName,
		lastInputTypeName = state.lastInputTypeName,
		viewport = state.viewport,
		isTenFootInterface = state.isTenFootInterface,
		touchEnabled = state.touchEnabled,
		keyboardEnabled = state.keyboardEnabled,
		mouseEnabled = state.mouseEnabled,
		gamepadEnabled = state.gamepadEnabled,
		basePrimaryInputType = state.basePrimaryInputType,
	}
end

function PlatformServiceUtils.ApplyThumbstickDeadzone(vectorRaw: any, deadzoneRaw: any): Vector2
	local vector = if typeof(vectorRaw) == "Vector2" then vectorRaw else Vector2.zero
	local deadzone = clampNumber(deadzoneRaw, 0.2, 0, 0.99)
	local magnitude = vector.Magnitude
	if magnitude <= deadzone then
		return Vector2.zero
	end
	if magnitude <= 0 then
		return Vector2.zero
	end
	local normalized = vector / magnitude
	local scaledMagnitude = (magnitude - deadzone) / (1 - deadzone)
	return normalized * math.clamp(scaledMagnitude, 0, 1)
end

function PlatformServiceUtils.HasThumbstickPassedDeadzone(vectorRaw: any, deadzoneRaw: any): boolean
	return PlatformServiceUtils.ApplyThumbstickDeadzone(vectorRaw, deadzoneRaw).Magnitude > 0
end

local function bindingKeyCodeForPrompt(binding: ActionBinding): Enum.KeyCode?
	if binding.keyCode ~= nil then
		return binding.keyCode
	end
	if binding.inputType == Enum.UserInputType.MouseButton1 then
		return Enum.KeyCode.MouseLeftButton
	end
	if binding.inputType == Enum.UserInputType.MouseButton2 then
		return Enum.KeyCode.MouseRightButton
	end
	if binding.inputType == Enum.UserInputType.MouseButton3 then
		return Enum.KeyCode.MouseMiddleButton
	end
	if binding.inputType == Enum.UserInputType.Touch then
		return Enum.KeyCode.Touch
	end
	return nil
end

local function resolvePromptText(binding: ActionBinding, touchPromptRaw: any): string
	if typeof(binding.label) == "string" and binding.label ~= "" then
		return binding.label
	end
	local keyCode = bindingKeyCodeForPrompt(binding)
	if keyCode ~= nil then
		local override = KEYCODE_TEXT_OVERRIDES[keyCode]
		if override ~= nil then
			return override
		end
		return formatEnumName(keyCode.Name)
	end
	if binding.playerAction ~= nil then
		local override = PLAYER_ACTION_TEXT_OVERRIDES[binding.playerAction]
		if override ~= nil then
			return override
		end
		return formatEnumName(binding.playerAction.Name)
	end
	if typeof(touchPromptRaw) == "string" and touchPromptRaw ~= "" then
		return touchPromptRaw
	end
	return "Action"
end

local function resolvePromptIcon(binding: ActionBinding, platformKind: PlatformKind, gamepadFamilyRaw: any): string?
	if typeof(binding.icon) == "string" and binding.icon ~= "" then
		return binding.icon
	end
	local keyCode = bindingKeyCodeForPrompt(binding)
	if keyCode == nil then
		return nil
	end
	if platformKind == "Gamepad" then
		local family = if gamepadFamilyRaw == "playstation" then "playstation" else DEFAULT_GAMEPAD_FAMILY
		local familyHints = if typeof(HINTS[family]) == "table" then HINTS[family] else HINTS[DEFAULT_GAMEPAD_FAMILY]
		if typeof(familyHints) == "table" then
			local icon = familyHints[keyCode]
			if typeof(icon) == "string" and icon ~= "" then
				return icon
			end
		end
		return nil
	end
	if platformKind == "Touch" then
		local mobileHints = HINTS.mobile
		if typeof(mobileHints) == "table" then
			local icon = mobileHints[keyCode]
			if typeof(icon) == "string" and icon ~= "" then
				return icon
			end
		end
		return nil
	end
	local keyboardHints = HINTS.keyboard
	if typeof(keyboardHints) == "table" then
		local icon = keyboardHints[keyCode]
		if typeof(icon) == "string" and icon ~= "" then
			return icon
		end
	end
	return nil
end

local function gameplayPointerBindings(
	mouseTouchLabel: string
): ({ [string]: { ActionBinding } }, { [string]: { ActionBinding } })
	return {
		KeyboardMouse = {
			{
				inputType = Enum.UserInputType.MouseButton1,
			},
		},
		Gamepad = {
			{
				keyCode = Enum.KeyCode.ButtonR2,
			},
		},
		Touch = {
			{
				inputType = Enum.UserInputType.Touch,
			},
		},
	}, {
		KeyboardMouse = {
			{
				keyCode = Enum.KeyCode.MouseLeftButton,
			},
		},
		Gamepad = {
			{
				keyCode = Enum.KeyCode.ButtonR2,
			},
		},
		Touch = {
			{
				inputType = Enum.UserInputType.Touch,
				label = mouseTouchLabel,
			},
		},
	}
end

local BUILD_BINDINGS, BUILD_PROMPTS = gameplayPointerBindings("Tap to Mine")
local MELEE_BINDINGS, MELEE_PROMPTS = gameplayPointerBindings("Tap to Attack")
local MAGIC_BINDINGS, MAGIC_PROMPTS = gameplayPointerBindings("Tap to Cast")

local DEFAULT_ACTION_DEFINITIONS: { [string]: ActionDefinition } = {
	[ACTIONS.MOVE] = {
		actionName = ACTIONS.MOVE,
		displayName = "Move",
		description = "Move the player.",
		priority = 3000,
		consume = true,
		allowWhileTyping = false,
		blockWhenPointerOverGui = false,
		blockWhenGuiSelected = false,
		touchPrompt = "Move",
		promptBindingsByPlatform = {
			KeyboardMouse = {
				{
					keyCode = Enum.KeyCode.A,
					label = "A / D",
				},
			},
			Gamepad = {
				{
					keyCode = Enum.KeyCode.Thumbstick1,
					label = "L Stick",
				},
			},
			Touch = {
				{
					inputType = Enum.UserInputType.Touch,
					label = "Move",
				},
			},
		},
	},
	[ACTIONS.MOVE_LEFT] = {
		actionName = ACTIONS.MOVE_LEFT,
		displayName = "Move Left",
		description = "Move the player left.",
		priority = 3000,
		consume = true,
		allowWhileTyping = false,
		blockWhenPointerOverGui = false,
		blockWhenGuiSelected = false,
		touchPrompt = "Move Left",
		bindingsByPlatform = {
			KeyboardMouse = {
				{
					playerAction = Enum.PlayerActions.CharacterLeft,
					axis = "X",
					axisSign = -1,
					deadzone = 0.14,
				},
			},
			Gamepad = {
				{
					playerAction = Enum.PlayerActions.CharacterLeft,
					axis = "X",
					axisSign = -1,
					deadzone = 0.2,
				},
				{
					keyCode = Enum.KeyCode.DPadLeft,
				},
			},
			Touch = {
				{
					playerAction = Enum.PlayerActions.CharacterLeft,
					axis = "X",
					axisSign = -1,
					deadzone = 0.22,
				},
			},
		},
		promptBindingsByPlatform = {
			KeyboardMouse = {
				{
					keyCode = Enum.KeyCode.A,
					label = "A / Left",
				},
			},
			Gamepad = {
				{
					keyCode = Enum.KeyCode.Thumbstick1,
					label = "L Stick Left",
				},
			},
			Touch = {
				{
					inputType = Enum.UserInputType.Touch,
					label = "Move Left",
				},
			},
		},
	},
	[ACTIONS.MOVE_RIGHT] = {
		actionName = ACTIONS.MOVE_RIGHT,
		displayName = "Move Right",
		description = "Move the player right.",
		priority = 3000,
		consume = true,
		allowWhileTyping = false,
		blockWhenPointerOverGui = false,
		blockWhenGuiSelected = false,
		touchPrompt = "Move Right",
		bindingsByPlatform = {
			KeyboardMouse = {
				{
					playerAction = Enum.PlayerActions.CharacterRight,
					axis = "X",
					axisSign = 1,
					deadzone = 0.14,
				},
			},
			Gamepad = {
				{
					playerAction = Enum.PlayerActions.CharacterRight,
					axis = "X",
					axisSign = 1,
					deadzone = 0.2,
				},
				{
					keyCode = Enum.KeyCode.DPadRight,
				},
			},
			Touch = {
				{
					playerAction = Enum.PlayerActions.CharacterRight,
					axis = "X",
					axisSign = 1,
					deadzone = 0.22,
				},
			},
		},
		promptBindingsByPlatform = {
			KeyboardMouse = {
				{
					keyCode = Enum.KeyCode.D,
					label = "D / Right",
				},
			},
			Gamepad = {
				{
					keyCode = Enum.KeyCode.Thumbstick1,
					label = "L Stick Right",
				},
			},
			Touch = {
				{
					inputType = Enum.UserInputType.Touch,
					label = "Move Right",
				},
			},
		},
	},
	[ACTIONS.MOVE_UP] = {
		actionName = ACTIONS.MOVE_UP,
		displayName = "Move Up",
		description = "Move upward while flying.",
		priority = 3000,
		consume = true,
		allowWhileTyping = false,
		blockWhenPointerOverGui = false,
		blockWhenGuiSelected = false,
		touchPrompt = "Move Up",
		bindingsByPlatform = {
			KeyboardMouse = {
				{
					playerAction = Enum.PlayerActions.CharacterForward,
					axis = "Y",
					axisSign = 1,
					deadzone = 0.14,
				},
			},
			Gamepad = {
				{
					playerAction = Enum.PlayerActions.CharacterForward,
					axis = "Y",
					axisSign = 1,
					deadzone = 0.2,
				},
				{
					keyCode = Enum.KeyCode.DPadUp,
				},
			},
			Touch = {
				{
					playerAction = Enum.PlayerActions.CharacterForward,
					axis = "Y",
					axisSign = 1,
					deadzone = 0.22,
				},
			},
		},
		promptBindingsByPlatform = {
			KeyboardMouse = {
				{
					keyCode = Enum.KeyCode.W,
					label = "W",
				},
			},
			Gamepad = {
				{
					keyCode = Enum.KeyCode.Thumbstick1,
					label = "L Stick Up",
				},
			},
			Touch = {
				{
					inputType = Enum.UserInputType.Touch,
					label = "Move Up",
				},
			},
		},
	},
	[ACTIONS.MOVE_DOWN] = {
		actionName = ACTIONS.MOVE_DOWN,
		displayName = "Move Down",
		description = "Move downward while flying.",
		priority = 3000,
		consume = true,
		allowWhileTyping = false,
		blockWhenPointerOverGui = false,
		blockWhenGuiSelected = false,
		touchPrompt = "Move Down",
		bindingsByPlatform = {
			KeyboardMouse = {
				{
					playerAction = Enum.PlayerActions.CharacterBackward,
					axis = "Y",
					axisSign = -1,
					deadzone = 0.14,
				},
				{
					keyCode = Enum.KeyCode.LeftControl,
				},
				{
					keyCode = Enum.KeyCode.RightControl,
				},
			},
			Gamepad = {
				{
					playerAction = Enum.PlayerActions.CharacterBackward,
					axis = "Y",
					axisSign = -1,
					deadzone = 0.2,
				},
				{
					keyCode = Enum.KeyCode.DPadDown,
				},
			},
			Touch = {
				{
					playerAction = Enum.PlayerActions.CharacterBackward,
					axis = "Y",
					axisSign = -1,
					deadzone = 0.22,
				},
			},
		},
		promptBindingsByPlatform = {
			KeyboardMouse = {
				{
					keyCode = Enum.KeyCode.LeftControl,
					label = "S / Ctrl",
				},
			},
			Gamepad = {
				{
					keyCode = Enum.KeyCode.Thumbstick1,
					label = "L Stick Down",
				},
			},
			Touch = {
				{
					inputType = Enum.UserInputType.Touch,
					label = "Move Down",
				},
			},
		},
	},
	[ACTIONS.JUMP] = {
		actionName = ACTIONS.JUMP,
		displayName = "Jump",
		description = "Jump while grounded.",
		priority = 3000,
		consume = true,
		allowWhileTyping = false,
		blockWhenPointerOverGui = false,
		blockWhenGuiSelected = false,
		touchPrompt = "Jump",
		bindingsByPlatform = {
			KeyboardMouse = {
				{
					playerAction = Enum.PlayerActions.CharacterJump,
				},
			},
			Gamepad = {
				{
					playerAction = Enum.PlayerActions.CharacterJump,
				},
			},
			Touch = {
				{
					playerAction = Enum.PlayerActions.CharacterJump,
				},
			},
		},
		promptBindingsByPlatform = {
			KeyboardMouse = {
				{
					keyCode = Enum.KeyCode.Space,
				},
			},
			Gamepad = {
				{
					keyCode = Enum.KeyCode.ButtonA,
				},
			},
			Touch = {
				{
					inputType = Enum.UserInputType.Touch,
					label = "Jump",
				},
			},
		},
	},
	[ACTIONS.BUILD_PRIMARY] = {
		actionName = ACTIONS.BUILD_PRIMARY,
		displayName = "Mine / Place",
		description = "Mine terrain or place the selected build item.",
		priority = 2000,
		consume = false,
		allowWhileTyping = false,
		blockWhenPointerOverGui = true,
		blockWhenGuiSelected = true,
		touchPrompt = "Tap to Mine",
		bindingsByPlatform = BUILD_BINDINGS,
		promptBindingsByPlatform = BUILD_PROMPTS,
	},
	[ACTIONS.MELEE_ATTACK] = {
		actionName = ACTIONS.MELEE_ATTACK,
		displayName = "Attack",
		description = "Use the equipped melee weapon.",
		priority = 2000,
		consume = false,
		allowWhileTyping = false,
		blockWhenPointerOverGui = true,
		blockWhenGuiSelected = true,
		touchPrompt = "Tap to Attack",
		bindingsByPlatform = MELEE_BINDINGS,
		promptBindingsByPlatform = MELEE_PROMPTS,
	},
	[ACTIONS.MAGIC_CAST] = {
		actionName = ACTIONS.MAGIC_CAST,
		displayName = "Cast",
		description = "Use the equipped magic weapon.",
		priority = 2000,
		consume = false,
		allowWhileTyping = false,
		blockWhenPointerOverGui = true,
		blockWhenGuiSelected = true,
		touchPrompt = "Tap to Cast",
		bindingsByPlatform = MAGIC_BINDINGS,
		promptBindingsByPlatform = MAGIC_PROMPTS,
	},
	[ACTIONS.MOVE_VERTICAL] = {
		actionName = ACTIONS.MOVE_VERTICAL,
		displayName = "Move Up / Down",
		description = "Move vertically while flying.",
		priority = 3000,
		consume = true,
		allowWhileTyping = false,
		blockWhenPointerOverGui = false,
		blockWhenGuiSelected = false,
		touchPrompt = "Fly",
		promptBindingsByPlatform = {
			KeyboardMouse = {
				{
					keyCode = Enum.KeyCode.Space,
					label = "Space / Ctrl",
				},
			},
			Gamepad = {
				{
					keyCode = Enum.KeyCode.Thumbstick1,
					label = "L Stick Up / Down",
				},
			},
			Touch = {
				{
					inputType = Enum.UserInputType.Touch,
					label = "Fly",
				},
			},
		},
	},
	[ACTIONS.HOTBAR_SELECT] = {
		actionName = ACTIONS.HOTBAR_SELECT,
		displayName = "Select Hotbar Slot",
		description = "Pick a hotbar slot directly.",
		priority = 1500,
		consume = false,
		allowWhileTyping = false,
		blockWhenPointerOverGui = false,
		blockWhenGuiSelected = false,
		promptBindingsByPlatform = {
			KeyboardMouse = {
				{
					label = "1 - 8",
				},
			},
		},
	},
	[ACTIONS.HOTBAR_CYCLE] = {
		actionName = ACTIONS.HOTBAR_CYCLE,
		displayName = "Scroll Heart Bar",
		description = "Scroll your heart bar.",
		priority = 1500,
		consume = false,
		allowWhileTyping = false,
		blockWhenPointerOverGui = false,
		blockWhenGuiSelected = false,
		promptBindingsByPlatform = {
			KeyboardMouse = {
				{
					label = "Scroll Wheel",
				},
			},
		},
	},
	[ACTIONS.PLACE_DEPLOYABLE] = {
		actionName = ACTIONS.PLACE_DEPLOYABLE,
		displayName = "Place Deployable",
		description = "Place the selected deployable item.",
		priority = 2000,
		consume = false,
		allowWhileTyping = false,
		blockWhenPointerOverGui = true,
		blockWhenGuiSelected = true,
		touchPrompt = "Tap",
		promptBindingsByPlatform = {
			KeyboardMouse = {
				{
					keyCode = Enum.KeyCode.MouseLeftButton,
				},
			},
			Touch = {
				{
					inputType = Enum.UserInputType.Touch,
					label = "Tap",
				},
			},
		},
	},
}

function PlatformServiceUtils.GetDefaultActionDefinitions(): { [string]: ActionDefinition }
	local output = {}
	for actionName, definition in DEFAULT_ACTION_DEFINITIONS do
		output[actionName] = cloneActionDefinition(definition)
	end
	return output
end

function PlatformServiceUtils.GetDefaultActionDefinition(actionNameRaw: any): ActionDefinition?
	if typeof(actionNameRaw) ~= "string" then
		return nil
	end
	local definition = DEFAULT_ACTION_DEFINITIONS[actionNameRaw]
	if definition == nil then
		return nil
	end
	return cloneActionDefinition(definition)
end

function PlatformServiceUtils.ResolveBindingsForPlatform(definitionRaw: any, platformKindRaw: any): { ActionBinding }
	if typeof(definitionRaw) ~= "table" then
		return {}
	end
	local platformKind = if platformKindRaw == "Gamepad" or platformKindRaw == "Touch"
		then platformKindRaw
		else "KeyboardMouse"
	local bindingsByPlatform = (definitionRaw :: ActionDefinition).bindingsByPlatform
	if typeof(bindingsByPlatform) ~= "table" then
		return {}
	end
	return cloneBindings(bindingsByPlatform[platformKind])
end

function PlatformServiceUtils.ResolvePromptBindingsForPlatform(
	definitionRaw: any,
	platformKindRaw: any
): { ActionBinding }
	if typeof(definitionRaw) ~= "table" then
		return {}
	end
	local platformKind = if platformKindRaw == "Gamepad" or platformKindRaw == "Touch"
		then platformKindRaw
		else "KeyboardMouse"
	local definition = definitionRaw :: ActionDefinition
	if typeof(definition.promptBindingsByPlatform) == "table" then
		local bindings = definition.promptBindingsByPlatform[platformKind]
		if typeof(bindings) == "table" and #bindings > 0 then
			return cloneBindings(bindings)
		end
	end
	return PlatformServiceUtils.ResolveBindingsForPlatform(definition, platformKind)
end

function PlatformServiceUtils.ResolvePromptForAction(
	definitionRaw: any,
	platformKindRaw: any,
	deviceClassRaw: any,
	gamepadFamilyRaw: any
): PromptBinding?
	if typeof(definitionRaw) ~= "table" then
		return nil
	end
	local definition = definitionRaw :: ActionDefinition
	local platformKind = if platformKindRaw == "Gamepad" or platformKindRaw == "Touch"
		then platformKindRaw
		else "KeyboardMouse"
	local deviceClass = if deviceClassRaw == "Phone"
			or deviceClassRaw == "Tablet"
			or deviceClassRaw == "Console"
		then deviceClassRaw
		else "Desktop"
	local bindings = PlatformServiceUtils.ResolvePromptBindingsForPlatform(definition, platformKind)
	if #bindings <= 0 then
		return nil
	end
	local binding = bindings[1]
	return {
		actionName = definition.actionName,
		displayName = definition.displayName,
		platform = platformKind,
		deviceClass = deviceClass,
		text = resolvePromptText(binding, definition.touchPrompt),
		icon = resolvePromptIcon(binding, platformKind, gamepadFamilyRaw),
		keyCode = binding.keyCode,
		inputType = binding.inputType,
		playerAction = binding.playerAction,
	}
end

PlatformServiceUtils.isGamepadInputType = PlatformServiceUtils.IsGamepadInputType
PlatformServiceUtils.isTouchInputType = PlatformServiceUtils.IsTouchInputType
PlatformServiceUtils.isKeyboardInputType = PlatformServiceUtils.IsKeyboardInputType
PlatformServiceUtils.isMouseInputType = PlatformServiceUtils.IsMouseInputType
PlatformServiceUtils.isPointerInputType = PlatformServiceUtils.IsPointerInputType
PlatformServiceUtils.resolvePlatformKind = PlatformServiceUtils.ResolvePlatformKind
PlatformServiceUtils.resolveDeviceClass = PlatformServiceUtils.ResolveDeviceClass
PlatformServiceUtils.createPlatformState = PlatformServiceUtils.CreatePlatformState
PlatformServiceUtils.platformStatesEqual = PlatformServiceUtils.PlatformStatesEqual
PlatformServiceUtils.clonePlatformState = PlatformServiceUtils.ClonePlatformState
PlatformServiceUtils.applyThumbstickDeadzone = PlatformServiceUtils.ApplyThumbstickDeadzone
PlatformServiceUtils.hasThumbstickPassedDeadzone = PlatformServiceUtils.HasThumbstickPassedDeadzone
PlatformServiceUtils.getDefaultActionDefinitions = PlatformServiceUtils.GetDefaultActionDefinitions
PlatformServiceUtils.getDefaultActionDefinition = PlatformServiceUtils.GetDefaultActionDefinition
PlatformServiceUtils.resolveBindingsForPlatform = PlatformServiceUtils.ResolveBindingsForPlatform
PlatformServiceUtils.resolvePromptBindingsForPlatform = PlatformServiceUtils.ResolvePromptBindingsForPlatform
PlatformServiceUtils.resolvePromptForAction = PlatformServiceUtils.ResolvePromptForAction

return PlatformServiceUtils

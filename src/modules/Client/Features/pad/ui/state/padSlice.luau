--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local Charm = require(ReplicatedStorage.Packages.Charm)
local GamepadNav = require(gameRoot.Shared.Features.platform.modules.GamepadNav)
local ImageIds = require(gameRoot.Client.UI.core.ImageIds)

export type PadStickState = {
	position: Vector2,
	magnitude: number,
	active: boolean,
}

export type PadState = {
	visible: boolean,
	platform: string,
	imageId: string,
	dominantStick: "Left" | "Right"?,
	leftStick: PadStickState,
	rightStick: PadStickState,
	lastInputAt: number,
	stickDeadzone: number,
	navigationDeadzone: number,
}

local DEFAULT_IMAGE_ID = if typeof((ImageIds :: any).platform) == "table"
		and typeof(((ImageIds :: any).platform :: any).gamepadNav) == "string"
	then ((ImageIds :: any).platform :: any).gamepadNav :: string
	else ""

local THUMBSTICK_ACTIVE_EPSILON = GamepadNav.THUMBSTICK_ACTIVE_EPSILON

local function sanitizeDeadzone(valueRaw: any, fallback: number): number
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then valueRaw else fallback
	return math.clamp(value, 0, 1)
end

local function createStickState(positionRaw: any, activeRaw: any): PadStickState
	local position = if typeof(positionRaw) == "Vector2" then positionRaw else Vector2.zero
	local clampedPosition = Vector2.new(math.clamp(position.X, -1, 1), math.clamp(position.Y, -1, 1))
	return {
		position = clampedPosition,
		magnitude = math.clamp(clampedPosition.Magnitude, 0, 1),
		active = activeRaw == true and clampedPosition.Magnitude > THUMBSTICK_ACTIVE_EPSILON,
	}
end

local function createDefaultState(): PadState
	return {
		visible = false,
		platform = "KeyboardMouse",
		imageId = DEFAULT_IMAGE_ID,
		dominantStick = nil,
		leftStick = createStickState(Vector2.zero, false),
		rightStick = createStickState(Vector2.zero, false),
		lastInputAt = 0,
		stickDeadzone = GamepadNav.DEFAULT_STICK_DEADZONE,
		navigationDeadzone = GamepadNav.DEFAULT_NAVIGATION_DEADZONE,
	}
end

local padStateAtom: Charm.Atom<PadState> = Charm.atom(createDefaultState())

local function getPadState(): PadState
	return padStateAtom()
end

local function setPlatform(platformRaw: any): PadState
	local current = padStateAtom()
	local platform = if typeof(platformRaw) == "string" and platformRaw ~= "" then platformRaw else current.platform
	local nextState: PadState = {
		visible = platform == "Gamepad",
		platform = platform,
		imageId = current.imageId,
		dominantStick = current.dominantStick,
		leftStick = current.leftStick,
		rightStick = current.rightStick,
		lastInputAt = current.lastInputAt,
		stickDeadzone = current.stickDeadzone,
		navigationDeadzone = current.navigationDeadzone,
	}
	padStateAtom(nextState)
	return nextState
end

local function updateThumbsticks(snapshotRaw: any): PadState
	local current = padStateAtom()
	local snapshot = if typeof(snapshotRaw) == "table" then snapshotRaw else {} :: any
	local left = if typeof((snapshot :: any).left) == "table" then (snapshot :: any).left else nil
	local right = if typeof((snapshot :: any).right) == "table" then (snapshot :: any).right else nil
	local nextState: PadState = {
		visible = current.platform == "Gamepad",
		platform = current.platform,
		imageId = current.imageId,
		dominantStick = if (snapshot :: any).dominant == "Left" or (snapshot :: any).dominant == "Right"
			then (snapshot :: any).dominant
			else nil,
		leftStick = createStickState(
			if left ~= nil then (left :: any).screen else current.leftStick.position,
			if left ~= nil then (left :: any).active else current.leftStick.active
		),
		rightStick = createStickState(
			if right ~= nil then (right :: any).screen else current.rightStick.position,
			if right ~= nil then (right :: any).active else current.rightStick.active
		),
		lastInputAt = if typeof((snapshot :: any).lastUpdatedAt) == "number"
			then (snapshot :: any).lastUpdatedAt
			else current.lastInputAt,
		stickDeadzone = sanitizeDeadzone((snapshot :: any).stickDeadzone, current.stickDeadzone),
		navigationDeadzone = sanitizeDeadzone((snapshot :: any).navigationDeadzone, current.navigationDeadzone),
	}
	padStateAtom(nextState)
	return nextState
end

local function resetPadState(): PadState
	local nextState = createDefaultState()
	padStateAtom(nextState)
	return nextState
end

return {
	padStateAtom = padStateAtom,
	getPadState = getPadState,
	setPlatform = setPlatform,
	updateThumbsticks = updateThumbsticks,
	resetPadState = resetPadState,
}

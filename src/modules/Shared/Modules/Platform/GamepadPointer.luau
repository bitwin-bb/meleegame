--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CoreRuntime = require(script.Parent.Parent.Core.Runtime)

local GamepadPointer = {}

GamepadPointer.DEFAULT_TILE_SIZE_STUDS = 2
GamepadPointer.WORLD_REACH_TILES = 5

export type PointerOwner = "Left" | "Right"

local WORLD_PLANE_EPSILON = 1e-4

local function sanitizeTileSizeStuds(tileSizeStudsRaw: any): number
	local tileSizeStuds = if typeof(tileSizeStudsRaw) == "number" and tileSizeStudsRaw == tileSizeStudsRaw
		then tileSizeStudsRaw
		else GamepadPointer.DEFAULT_TILE_SIZE_STUDS
	return math.max(0.25, tileSizeStuds)
end

local function resolveViewportOffset(camera: Camera, origin: Vector3, worldOffset: Vector3): Vector2
	local originViewportPosition = camera:WorldToViewportPoint(origin)
	local targetViewportPosition = camera:WorldToViewportPoint(origin + worldOffset)
	return Vector2.new(
		targetViewportPosition.X - originViewportPosition.X,
		targetViewportPosition.Y - originViewportPosition.Y
	)
end

local function resolveRootPart(rootPartRaw: any): BasePart?
	return if typeof(rootPartRaw) == "Instance" and rootPartRaw:IsA("BasePart") then rootPartRaw :: BasePart else nil
end

local function resolveCharacterRootPart(playerRaw: any): BasePart?
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return nil
	end

	local player = playerRaw :: Player
	local character = player.Character
	if character == nil then
		return nil
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart ~= nil and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	if character.PrimaryPart ~= nil then
		return character.PrimaryPart
	end

	return character:FindFirstChildWhichIsA("BasePart")
end

local function resolveRuntimeContext(): any?
	local runtimeContext = nil
	local ok, runtimeOrError = pcall(function()
		return CoreRuntime.getClientRuntime()
	end)
	if ok then
		runtimeContext = runtimeOrError
	end

	if runtimeContext ~= nil and typeof((runtimeContext :: any).init) == "function" then
		pcall(function()
			(runtimeContext :: any):init()
		end)
	end

	return runtimeContext
end

local function resolveGamepadNav(): any?
	local runtimeContext = resolveRuntimeContext()
	if runtimeContext == nil then
		return nil
	end

	if typeof((runtimeContext :: any).getGamepadNav) == "function" then
		local ok, gamepadNavOrError = pcall(function()
			return (runtimeContext :: any):getGamepadNav()
		end)
		if ok then
			return gamepadNavOrError
		end
	end

	return (runtimeContext :: any).gamepadNav
end

local function resolveThumbstickSnapshot(snapshotRaw: any): any?
	if typeof(snapshotRaw) == "table" then
		return snapshotRaw
	end

	local gamepadNav = resolveGamepadNav()
	if gamepadNav ~= nil and typeof((gamepadNav :: any).getThumbstickState) == "function" then
		local ok, snapshotOrError = pcall(function()
			return (gamepadNav :: any):getThumbstickState()
		end)
		if ok and typeof(snapshotOrError) == "table" then
			return snapshotOrError
		end
	end

	return nil
end

local function resolveStickVector(snapshot: any, key: PointerOwner): (Vector2?, boolean)
	if snapshot == nil then
		return nil, false
	end

	local source = if key == "Right" then (snapshot :: any).right else (snapshot :: any).left
	if typeof(source) ~= "table" then
		return nil, false
	end

	local screenVector = nil :: Vector2?
	if typeof((source :: any).screen) == "Vector2" then
		screenVector = (source :: any).screen
	elseif typeof((source :: any).raw) == "Vector2" then
		local rawVector = (source :: any).raw :: Vector2
		screenVector = Vector2.new(rawVector.X, -rawVector.Y)
	end

	if screenVector == nil then
		return nil, false
	end

	local isActive = (source :: any).active == true and screenVector.Magnitude > 1e-4
	return screenVector, isActive
end

function GamepadPointer.ResolveOwnedVector(snapshotRaw: any): (Vector2?, PointerOwner?)
	local snapshot = resolveThumbstickSnapshot(snapshotRaw)
	local rightVector, rightActive = resolveStickVector(snapshot, "Right")
	if rightActive and rightVector ~= nil then
		return rightVector, "Right"
	end

	local leftVector, leftActive = resolveStickVector(snapshot, "Left")
	if leftActive and leftVector ~= nil then
		return leftVector, "Left"
	end

	return nil, nil
end

function GamepadPointer.ResolveReachStuds(tileSizeStudsRaw: any): number
	return sanitizeTileSizeStuds(tileSizeStudsRaw) * GamepadPointer.WORLD_REACH_TILES
end

function GamepadPointer.ResolveWorldOffset(vectorRaw: any, tileSizeStudsRaw: any): Vector3?
	if typeof(vectorRaw) ~= "Vector2" then
		return nil
	end
	if vectorRaw.Magnitude <= 1e-4 then
		return nil
	end

	local reachStuds = GamepadPointer.ResolveReachStuds(tileSizeStudsRaw)
	return Vector3.new(0, -vectorRaw.Y * reachStuds, -vectorRaw.X * reachStuds)
end

function GamepadPointer.ResolveWorldOffsetForScreenVector(
	vectorRaw: any,
	tileSizeStudsRaw: any,
	rootPartRaw: any?
): Vector3?
	if typeof(vectorRaw) ~= "Vector2" then
		return nil
	end

	local vector = vectorRaw :: Vector2
	local magnitude = vector.Magnitude
	if magnitude <= WORLD_PLANE_EPSILON then
		return nil
	end

	local rootPart = resolveRootPart(rootPartRaw)
	local camera = Workspace.CurrentCamera
	if rootPart == nil or camera == nil then
		return GamepadPointer.ResolveWorldOffset(vector, tileSizeStudsRaw)
	end

	local origin = rootPart.Position
	local zScreenAxis = resolveViewportOffset(camera, origin, Vector3.zAxis)
	local yScreenAxis = resolveViewportOffset(camera, origin, Vector3.yAxis)
	local determinant = zScreenAxis.X * yScreenAxis.Y - yScreenAxis.X * zScreenAxis.Y
	if math.abs(determinant) <= WORLD_PLANE_EPSILON then
		return GamepadPointer.ResolveWorldOffset(vector, tileSizeStudsRaw)
	end

	local desiredScreenDirection = vector.Unit
	local zCoefficient = (desiredScreenDirection.X * yScreenAxis.Y - yScreenAxis.X * desiredScreenDirection.Y)
		/ determinant
	local yCoefficient = (zScreenAxis.X * desiredScreenDirection.Y - desiredScreenDirection.X * zScreenAxis.Y)
		/ determinant
	local worldDirection = Vector3.new(0, yCoefficient, zCoefficient)
	if worldDirection.Magnitude <= WORLD_PLANE_EPSILON then
		return GamepadPointer.ResolveWorldOffset(vector, tileSizeStudsRaw)
	end

	return worldDirection.Unit * GamepadPointer.ResolveReachStuds(tileSizeStudsRaw) * math.clamp(magnitude, 0, 1)
end

function GamepadPointer.ResolveWorldPosition(
	tileSizeStudsRaw: any,
	rootPartRaw: any?,
	snapshotRaw: any?
): (Vector3?, PointerOwner?, Vector2?)
	local vector, owner = GamepadPointer.ResolveOwnedVector(snapshotRaw)
	if vector == nil or owner == nil then
		return nil, nil, nil
	end

	local rootPart = if typeof(rootPartRaw) == "Instance" and rootPartRaw:IsA("BasePart")
		then rootPartRaw
		else resolveCharacterRootPart(Players.LocalPlayer)
	if rootPart == nil then
		return nil, owner, vector
	end

	local worldOffset = GamepadPointer.ResolveWorldOffset(vector, tileSizeStudsRaw)
	if worldOffset == nil then
		return nil, owner, vector
	end

	return rootPart.Position + worldOffset, owner, vector
end

function GamepadPointer.ResolveCurrentWorldPosition(
	tileSizeStudsRaw: any,
	rootPartRaw: any?
): (Vector3?, PointerOwner?, Vector2?)
	return GamepadPointer.ResolveWorldPosition(tileSizeStudsRaw, rootPartRaw, nil)
end

function GamepadPointer.ResolveScreenPosition(
	tileSizeStudsRaw: any,
	rootPartRaw: any?,
	snapshotRaw: any?
): (Vector2?, PointerOwner?, Vector2?)
	local worldPosition, owner, vector = GamepadPointer.ResolveWorldPosition(tileSizeStudsRaw, rootPartRaw, snapshotRaw)
	if worldPosition == nil then
		return nil, owner, vector
	end

	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil, owner, vector
	end

	local viewportPosition, isOnScreen = camera:WorldToViewportPoint(worldPosition)
	if not isOnScreen then
		return nil, owner, vector
	end

	return Vector2.new(viewportPosition.X, viewportPosition.Y), owner, vector
end

function GamepadPointer.ResolveCurrentScreenPosition(
	tileSizeStudsRaw: any,
	rootPartRaw: any?
): (Vector2?, PointerOwner?, Vector2?)
	return GamepadPointer.ResolveScreenPosition(tileSizeStudsRaw, rootPartRaw, nil)
end

GamepadPointer.resolveOwnedVector = GamepadPointer.ResolveOwnedVector
GamepadPointer.resolveReachStuds = GamepadPointer.ResolveReachStuds
GamepadPointer.resolveWorldOffset = GamepadPointer.ResolveWorldOffset
GamepadPointer.resolveWorldOffsetForScreenVector = GamepadPointer.ResolveWorldOffsetForScreenVector
GamepadPointer.resolveWorldPosition = GamepadPointer.ResolveWorldPosition
GamepadPointer.resolveCurrentWorldPosition = GamepadPointer.ResolveCurrentWorldPosition
GamepadPointer.resolveScreenPosition = GamepadPointer.ResolveScreenPosition
GamepadPointer.resolveCurrentScreenPosition = GamepadPointer.ResolveCurrentScreenPosition

return GamepadPointer

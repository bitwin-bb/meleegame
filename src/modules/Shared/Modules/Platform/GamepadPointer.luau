--!strict
local Workspace = game:GetService("Workspace")

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

local function resolveStickVector(snapshot: any, key: PointerOwner): (Vector2?, boolean)
	if typeof(snapshot) ~= "table" then
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

	local isActive = (source :: any).active == true and screenVector.Magnitude > WORLD_PLANE_EPSILON
	return screenVector, isActive
end

function GamepadPointer.ResolveOwnedVector(snapshotRaw: any): (Vector2?, PointerOwner?)
	local rightVector, rightActive = resolveStickVector(snapshotRaw, "Right")
	if rightActive and rightVector ~= nil then
		return rightVector, "Right"
	end

	local leftVector, leftActive = resolveStickVector(snapshotRaw, "Left")
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
	local vector = vectorRaw :: Vector2
	if vector.Magnitude <= WORLD_PLANE_EPSILON then
		return nil
	end

	local reachStuds = GamepadPointer.ResolveReachStuds(tileSizeStudsRaw)
	return Vector3.new(0, -vector.Y * reachStuds, -vector.X * reachStuds)
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

GamepadPointer.resolveOwnedVector = GamepadPointer.ResolveOwnedVector
GamepadPointer.resolveReachStuds = GamepadPointer.ResolveReachStuds
GamepadPointer.resolveWorldOffset = GamepadPointer.ResolveWorldOffset
GamepadPointer.resolveWorldOffsetForScreenVector = GamepadPointer.ResolveWorldOffsetForScreenVector

return GamepadPointer

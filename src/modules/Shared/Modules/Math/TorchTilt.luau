--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BuildService.BuildServiceUtils)

local TorchTilt = {}

export type SupportKind = "Ground" | "Wall"
export type TilePlacement = {
	tileX: number,
	tileY: number,
	supportKind: SupportKind,
	cframe: CFrame,
}

local WORLD_UP = Vector3.new(0, 1, 0)
local MIN_GROUND_UP_DOT = 0.75
local MAX_WALL_UP_DOT = 0.25
local MIN_SURFACE_OFFSET = 0.05

local function sanitizeVector3(valueRaw: any): Vector3?
	if typeof(valueRaw) ~= "Vector3" then
		return nil
	end
	if valueRaw.Magnitude <= 1e-4 then
		return nil
	end
	return valueRaw
end

local function sanitizeNumber(valueRaw: any): number?
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return nil
	end
	return valueRaw
end

local function normalizeOrFallback(vectorRaw: any, fallback: Vector3): Vector3
	local vector = sanitizeVector3(vectorRaw)
	if vector == nil then
		return fallback
	end
	return vector.Unit
end

local function projectOntoPlane(vector: Vector3, planeNormal: Vector3): Vector3
	return vector - planeNormal * vector:Dot(planeNormal)
end

local function buildFrame(position: Vector3, upVectorRaw: Vector3, forwardVectorRaw: Vector3): CFrame
	local upVector = normalizeOrFallback(upVectorRaw, WORLD_UP)
	local forwardCandidate = projectOntoPlane(normalizeOrFallback(forwardVectorRaw, Vector3.new(0, 0, -1)), upVector)
	if forwardCandidate.Magnitude <= 1e-4 then
		forwardCandidate = projectOntoPlane(Vector3.new(0, 0, -1), upVector)
	end
	if forwardCandidate.Magnitude <= 1e-4 then
		forwardCandidate = projectOntoPlane(Vector3.new(1, 0, 0), upVector)
	end

	local forwardVector = forwardCandidate.Unit
	local rightVector = forwardVector:Cross(upVector)
	if rightVector.Magnitude <= 1e-4 then
		rightVector = Vector3.new(1, 0, 0)
	else
		rightVector = rightVector.Unit
	end
	forwardVector = upVector:Cross(rightVector).Unit

	return CFrame.fromMatrix(position, rightVector, upVector, -forwardVector)
end

function TorchTilt.IsSolidSurface(instanceRaw: any): boolean
	if typeof(instanceRaw) ~= "Instance" then
		return false
	end
	if instanceRaw:IsA("Terrain") then
		return true
	end
	if instanceRaw:IsA("BasePart") then
		return instanceRaw.CanCollide == true
	end
	return false
end

function TorchTilt.IsGroundNormal(normalRaw: any): boolean
	local normal = sanitizeVector3(normalRaw)
	if normal == nil then
		return false
	end
	return normal.Unit:Dot(WORLD_UP) >= MIN_GROUND_UP_DOT
end

function TorchTilt.IsWallNormal(normalRaw: any): boolean
	local normal = sanitizeVector3(normalRaw)
	if normal == nil then
		return false
	end
	local unitNormal = normal.Unit
	return math.abs(unitNormal:Dot(WORLD_UP)) <= MAX_WALL_UP_DOT
		and math.abs(unitNormal.Z) > math.abs(unitNormal.X)
end

function TorchTilt.ResolveSupportKind(normalRaw: any): SupportKind?
	if TorchTilt.IsGroundNormal(normalRaw) then
		return "Ground"
	end
	if TorchTilt.IsWallNormal(normalRaw) then
		return "Wall"
	end
	return nil
end

function TorchTilt.ResolveTileAlignedCFrame(
	tileCenterRaw: any,
	supportNormalRaw: any,
	lookVectorRaw: any
): (CFrame?, SupportKind?)
	local tileCenter = sanitizeVector3(tileCenterRaw)
	local supportNormal = sanitizeVector3(supportNormalRaw)
	if tileCenter == nil or supportNormal == nil then
		return nil, nil
	end

	local surfaceNormal = supportNormal.Unit
	local supportKind = TorchTilt.ResolveSupportKind(surfaceNormal)
	if supportKind == nil then
		return nil, nil
	end

	local horizontalLook = projectOntoPlane(normalizeOrFallback(lookVectorRaw, Vector3.new(0, 0, -1)), WORLD_UP)
	if horizontalLook.Magnitude <= 1e-4 then
		horizontalLook = Vector3.new(0, 0, -1)
	else
		horizontalLook = horizontalLook.Unit
	end

	if supportKind == "Ground" then
		return buildFrame(tileCenter, WORLD_UP, horizontalLook), supportKind
	end

	local torchUp = (WORLD_UP + surfaceNormal).Unit
	local forwardCandidate = projectOntoPlane(horizontalLook, torchUp)
	if forwardCandidate.Magnitude <= 1e-4 then
		forwardCandidate = projectOntoPlane(-surfaceNormal, torchUp)
	end
	return buildFrame(tileCenter, torchUp, forwardCandidate), supportKind
end

function TorchTilt.ResolveTilePlacement(
	hitPositionRaw: any,
	hitNormalRaw: any,
	worldOriginRaw: any,
	tileSizeRaw: any,
	basePlaneXRaw: any,
	lookVectorRaw: any
): TilePlacement?
	local hitPosition = sanitizeVector3(hitPositionRaw)
	local hitNormal = sanitizeVector3(hitNormalRaw)
	local worldOrigin = sanitizeVector3(worldOriginRaw)
	local tileSize = sanitizeNumber(tileSizeRaw)
	local basePlaneX = sanitizeNumber(basePlaneXRaw)
	if hitPosition == nil or hitNormal == nil or worldOrigin == nil or tileSize == nil or basePlaneX == nil then
		return nil
	end
	if tileSize <= 0 then
		return nil
	end

	local surfaceNormal = hitNormal.Unit
	local supportKind = TorchTilt.ResolveSupportKind(surfaceNormal)
	if supportKind == nil then
		return nil
	end

	local supportSample = hitPosition - surfaceNormal * MIN_SURFACE_OFFSET
	local supportTileX, supportTileY = BuildServiceUtils.WorldPositionToTile(supportSample, worldOrigin, tileSize)
	local tileX = supportTileX
	local tileY = supportTileY
	if supportKind == "Ground" then
		tileY += 1
	else
		tileX += if surfaceNormal.Z >= 0 then 1 else -1
	end
	local tileCenter = BuildServiceUtils.TileToWorldCenter(tileX, tileY, worldOrigin, tileSize, basePlaneX)
	local alignedCFrame = TorchTilt.ResolveTileAlignedCFrame(tileCenter, surfaceNormal, lookVectorRaw)
	if alignedCFrame == nil then
		return nil
	end

	return {
		tileX = tileX,
		tileY = tileY,
		supportKind = supportKind,
		cframe = alignedCFrame,
	}
end

function TorchTilt.ResolvePlacementCFrame(
	hitPositionRaw: any,
	hitNormalRaw: any,
	boundingSizeRaw: any,
	lookVectorRaw: any
): (CFrame?, SupportKind?)
	local hitPosition = sanitizeVector3(hitPositionRaw)
	local hitNormal = sanitizeVector3(hitNormalRaw)
	local boundingSize = if typeof(boundingSizeRaw) == "Vector3" then boundingSizeRaw else nil
	if hitPosition == nil or hitNormal == nil or boundingSize == nil then
		return nil, nil
	end

	local supportKind = TorchTilt.ResolveSupportKind(hitNormal)
	if supportKind == nil then
		return nil, nil
	end

	local position = hitPosition
	if supportKind == "Ground" then
		position += WORLD_UP * math.max(MIN_SURFACE_OFFSET, boundingSize.Y * 0.5)
	else
		position += hitNormal.Unit * math.max(MIN_SURFACE_OFFSET, boundingSize.Z * 0.5)
	end

	return TorchTilt.ResolveTileAlignedCFrame(position, hitNormal, lookVectorRaw)
end

TorchTilt.isSolidSurface = TorchTilt.IsSolidSurface
TorchTilt.isGroundNormal = TorchTilt.IsGroundNormal
TorchTilt.isWallNormal = TorchTilt.IsWallNormal
TorchTilt.resolveSupportKind = TorchTilt.ResolveSupportKind
TorchTilt.resolveTileAlignedCFrame = TorchTilt.ResolveTileAlignedCFrame
TorchTilt.resolveTilePlacement = TorchTilt.ResolveTilePlacement
TorchTilt.resolvePlacementCFrame = TorchTilt.ResolvePlacementCFrame

return TorchTilt

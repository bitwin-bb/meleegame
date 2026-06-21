local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Maid = require("Maid")
local Table = require("Table")

local CelestialCycleConstants = require("CelestialCycleConstants")

local CelestialBodyRoot = {}
CelestialBodyRoot.__index = CelestialBodyRoot

local function computeVisibleExtentsAtDistance(camera: Camera, distance: number): (number, number)
	local viewportSize = camera.ViewportSize
	local aspectRatio = if viewportSize.Y > 0 then viewportSize.X / viewportSize.Y else 16 / 9
	local visibleHeight = 2 * distance * math.tan(math.rad(camera.FieldOfView) * 0.5)
	local visibleWidth = visibleHeight * aspectRatio
	return math.max(visibleWidth, CelestialCycleConstants.ANCHOR_WIDTH_STUDS),
		math.max(visibleHeight, CelestialCycleConstants.ANCHOR_HEIGHT_STUDS)
end

local function resolveCanvasSize(widthStuds: number, heightStuds: number): Vector2
	local pixelsPerStud = CelestialCycleConstants.SURFACE_PIXELS_PER_STUD
	local minCanvas = CelestialCycleConstants.SURFACE_MIN_CANVAS
	local maxCanvas = CelestialCycleConstants.SURFACE_MAX_CANVAS
	return Vector2.new(
		math.clamp(math.floor(widthStuds * pixelsPerStud + 0.5), minCanvas.X, maxCanvas.X),
		math.clamp(math.floor(heightStuds * pixelsPerStud + 0.5), minCanvas.Y, maxCanvas.Y)
	)
end

function CelestialBodyRoot.new(parent: Instance): CelestialBodyRoot
	local self = setmetatable({}, CelestialBodyRoot)
	self.maid = Maid.new()
	self.scope = Fusion.scoped(Fusion)
	self.canvasSize =
		resolveCanvasSize(CelestialCycleConstants.ANCHOR_WIDTH_STUDS, CelestialCycleConstants.ANCHOR_HEIGHT_STUDS)
	self.anchorPart = self.scope:New "Part" {
		Name = "CelestialBodyRoot",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Locked = true,
		Size = Vector3.new(1, CelestialCycleConstants.ANCHOR_HEIGHT_STUDS, CelestialCycleConstants.ANCHOR_WIDTH_STUDS),
		Transparency = 1,
		Parent = parent,
	}
	self.maid:GiveTask(function()
		Fusion.doCleanup(self.scope)
	end)
	return (self :: any) :: CelestialBodyRoot
end

function CelestialBodyRoot.Update(self: CelestialBodyRoot, camera: Camera?)
	local resolvedCamera = camera or Workspace.CurrentCamera
	if resolvedCamera == nil then
		return
	end

	local cameraCFrame = resolvedCamera.CFrame
	local cameraPosition = cameraCFrame.Position
	local forward = cameraCFrame.LookVector
	local flatForward = Vector3.new(forward.X, 0, forward.Z)
	if flatForward.Magnitude < 0.001 then
		flatForward = Vector3.zAxis
	end

	local forwardUnit = flatForward.Unit
	local widthStuds, heightStuds =
		computeVisibleExtentsAtDistance(resolvedCamera, CelestialCycleConstants.ANCHOR_DISTANCE_STUDS)
	local anchorCenter = Vector3.new(cameraPosition.X, CelestialCycleConstants.ANCHOR_WORLD_Y, cameraPosition.Z)
		+ forwardUnit * CelestialCycleConstants.ANCHOR_DISTANCE_STUDS

	self.anchorPart.Size = Vector3.new(1, heightStuds, widthStuds)
	self.anchorPart.CFrame = CFrame.fromMatrix(anchorCenter, -forwardUnit, Vector3.yAxis)
	self.canvasSize = resolveCanvasSize(widthStuds, heightStuds)
end

function CelestialBodyRoot.GetAdornee(self: CelestialBodyRoot): BasePart
	return self.anchorPart
end

function CelestialBodyRoot.GetCanvasSize(self: CelestialBodyRoot): Vector2
	return self.canvasSize
end

function CelestialBodyRoot.Destroy(self: CelestialBodyRoot)
	self.maid:Destroy()
end

CelestialBodyRoot.update = CelestialBodyRoot.Update
CelestialBodyRoot.getAdornee = CelestialBodyRoot.GetAdornee
CelestialBodyRoot.getCanvasSize = CelestialBodyRoot.GetCanvasSize
CelestialBodyRoot.destroy = CelestialBodyRoot.Destroy

export type CelestialBodyRoot = typeof(setmetatable(
	{} :: {
		maid: any,
		scope: any,
		anchorPart: Part,
		canvasSize: Vector2,
	},
	{} :: typeof({ __index = CelestialBodyRoot })
))

return Table.readonly(CelestialBodyRoot)

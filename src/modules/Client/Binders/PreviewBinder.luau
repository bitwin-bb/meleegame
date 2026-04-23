--!strict

local RunService = game:GetService("RunService")

local BuildServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BuildServiceUtils)
local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)

local PreviewBinder = {}
PreviewBinder.__index = PreviewBinder
setmetatable(PreviewBinder, ModelBinder)

local buildServiceClient = nil

local function getBuildServiceClient()
	if buildServiceClient == nil then
		buildServiceClient = require(script:FindFirstAncestor("game").Client.Services.BuildServiceClient)
	end
	return buildServiceClient
end

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function computeFootprintBounds(
	footprint: { any },
	fallbackTileX: number,
	fallbackTileY: number
): (number, number, number, number)
	if #footprint <= 0 then
		return fallbackTileX, fallbackTileX, fallbackTileY, fallbackTileY
	end

	local minTileX = math.huge
	local maxTileX = -math.huge
	local minTileY = math.huge
	local maxTileY = -math.huge
	for _, entry in footprint do
		local tileX = entry.tileX
		local tileY = entry.tileY
		if typeof(tileX) == "number" and typeof(tileY) == "number" then
			minTileX = math.min(minTileX, tileX)
			maxTileX = math.max(maxTileX, tileX)
			minTileY = math.min(minTileY, tileY)
			maxTileY = math.max(maxTileY, tileY)
		end
	end

	if minTileX == math.huge then
		return fallbackTileX, fallbackTileX, fallbackTileY, fallbackTileY
	end

	return minTileX, maxTileX, minTileY, maxTileY
end

function PreviewBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, PreviewBinder)
	self.part = if instance:IsA("BasePart") then instance else nil
	if self.part ~= nil then
		self.part.Name = "BuildPreviewBinder"
		self.part.Anchored = true
		self.part.CanCollide = false
		self.part.CanTouch = false
		self.part.CanQuery = false
		self.part.Material = Enum.Material.ForceField
		self.part.CastShadow = false
		self.part.Transparency = 1
	end

	self.instance:SetAttribute("PreviewTagged", true)
	self:Connect(RunService.RenderStepped, function()
		self:step()
	end)
	return self
end

function PreviewBinder.hide(self: any)
	if self.part ~= nil then
		self.part.Transparency = 1
	end
end

function PreviewBinder.step(self: any)
	if self.part == nil then
		return
	end

	local nextBuildServiceClient = getBuildServiceClient()
	local state = (nextBuildServiceClient :: any).state
	if typeof(state) ~= "table" then
		self:hide()
		return
	end

	local tileX, tileY = nextBuildServiceClient:resolveCursorTile()
	local previewColor = Color3.fromRGB(255, 209, 92)
	local footprint = {} :: { any }
	local activePlaceSource = nextBuildServiceClient:resolveActivePlaceSource()

	if activePlaceSource ~= nil then
		tileX, tileY = nextBuildServiceClient:resolveTerrainHoverTile(tileX, tileY)
		if tileX == nil or tileY == nil then
			self:hide()
			return
		end

		local canPlace, _, resolvedFootprint =
			nextBuildServiceClient:canPlaceAt(tileX, tileY, activePlaceSource.config.tileId)
		previewColor = if canPlace then Color3.fromRGB(122, 230, 160) else Color3.fromRGB(255, 120, 120)
		footprint = resolvedFootprint
	else
		if tileX == nil or tileY == nil then
			self:hide()
			return
		end

		local hoveredTileId = nextBuildServiceClient:getTileAt(tileX, tileY, false)
		if hoveredTileId == BuildServiceUtils.AIR_TILE_ID then
			self:hide()
			return
		end
	end

	local tileSize = if isFiniteNumber((state :: any).tileSize) then math.max(0.25, (state :: any).tileSize) else 2
	local worldOrigin = if typeof((state :: any).worldOrigin) == "Vector3"
		then (state :: any).worldOrigin
		else Vector3.zero
	local basePlaneX = if isFiniteNumber((state :: any).basePlaneX) then (state :: any).basePlaneX else 0
	local minTileX, maxTileX, minTileY, maxTileY = computeFootprintBounds(footprint, tileX, tileY)
	local width = maxTileX - minTileX + 1
	local height = maxTileY - minTileY + 1
	local thickness = math.max(0.12, tileSize * 0.12)
	local centerPosition = Vector3.new(
		basePlaneX + thickness * 0.5,
		worldOrigin.Y + (minTileY + height * 0.5) * tileSize,
		worldOrigin.Z + (minTileX + width * 0.5) * tileSize
	)

	self.part.Size =
		Vector3.new(thickness, math.max(0.1, height * tileSize * 0.92), math.max(0.1, width * tileSize * 0.92))
	self.part.CFrame = CFrame.new(centerPosition)
	self.part.Color = previewColor
	self.part.Transparency = 0.42
end

return PreviewBinder

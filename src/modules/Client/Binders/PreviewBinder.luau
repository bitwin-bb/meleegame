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

	local tileX = (nextBuildServiceClient :: any).cursorTileX
	local tileY = (nextBuildServiceClient :: any).cursorTileY
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

	local previewGeometry = nextBuildServiceClient:resolvePreviewGeometry(tileX, tileY, footprint)
	if previewGeometry == nil then
		self:hide()
		return
	end

	self.part.Size = previewGeometry.size
	self.part.CFrame = CFrame.new(previewGeometry.centerPosition)
	self.part.Color = previewColor
	self.part.Transparency = 0.42
end

return PreviewBinder

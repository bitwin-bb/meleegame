local require = require(script.Parent.loader).load(script)

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local BuildServiceUtils = require("BuildServiceUtils")
local ModelBinder = require("ModelBinder")
local String = require("String")

local PreviewBinder = {}
PreviewBinder.__index = PreviewBinder
setmetatable(PreviewBinder, ModelBinder)

local function createRuntimeInstanceName(): string
	local guid = String.removePostfix(String.removePrefix(HttpService:GenerateGUID(true), "{"), "}")
	return string.format("%03d", (tonumber(string.sub(guid, 1, 8), 16) or 0) % 1000)
end

function PreviewBinder.new(instance: Instance, context: ModelBinder.BinderContext)
	local self = ModelBinder.new(instance, context, PreviewBinder)
	self.buildServiceClient =
		assert(self:GetDependencies().BuildServiceClient, "BuildServiceClient dependency is unavailable")
	self.part = if instance:IsA("BasePart") then instance else nil
	if self.part ~= nil then
		self.part.Name = createRuntimeInstanceName()
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
		self:Step()
	end)
	return self
end

function PreviewBinder.Hide(self: any)
	if self.part ~= nil then
		self.part.Transparency = 1
	end
end

function PreviewBinder.Step(self: any)
	if self.part == nil then
		return
	end

	local buildServiceClient = self.buildServiceClient
	local state = (buildServiceClient :: any).state
	if typeof(state) ~= "table" then
		self:Hide()
		return
	end

	local tileX = (buildServiceClient :: any).cursorTileX
	local tileY = (buildServiceClient :: any).cursorTileY
	local previewColor = Color3.fromRGB(255, 209, 92)
	local footprint = {} :: { any }
	local activePlaceSource = buildServiceClient:GetActivePlaceSource()

	if activePlaceSource ~= nil then
		tileX, tileY = buildServiceClient:GetTerrainHoverTile(tileX, tileY)
		if tileX == nil or tileY == nil then
			self:Hide()
			return
		end

		local canPlace, _, gotFootprint = buildServiceClient:CanPlaceAt(tileX, tileY, activePlaceSource.config.tileId)
		previewColor = if canPlace then Color3.fromRGB(122, 230, 160) else Color3.fromRGB(255, 120, 120)
		footprint = gotFootprint
	else
		if tileX == nil or tileY == nil then
			self:Hide()
			return
		end

		local hoveredTileId = buildServiceClient:GetTileAt(tileX, tileY, false)
		if hoveredTileId == BuildServiceUtils.AIR_TILE_ID then
			self:Hide()
			return
		end
	end

	local previewGeometry = buildServiceClient:GetPreviewGeometry(tileX, tileY, footprint)
	if previewGeometry == nil then
		self:Hide()
		return
	end

	self.part.Size = previewGeometry.size
	self.part.CFrame = CFrame.new(previewGeometry.centerPosition)
	self.part.Color = previewColor
	self.part.Transparency = 0.42
end

return PreviewBinder

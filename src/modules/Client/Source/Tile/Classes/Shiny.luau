local require = require(script.Parent.loader).load(script)

local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local ContentProviderUtils = require("ContentProviderUtils")
local Maid = require("Maid")
local Rx: any = require("Rx")

local BuildServiceUtils = require("BuildServiceUtils")
local ShinySheet = require(script.Parent.Parent.Modules:WaitForChild("ShinySheet") :: any) :: any
local tileThunks = require("TileThunks")

type MaidClass = any

local Shiny = {}
Shiny.__index = Shiny

local SURFACE_PIXELS_PER_STUD = 32
local SPECK_ROLL_SECONDS = 0.45
local SPECK_ROLL_CHANCE = 0.28
local SPECK_MIN_SCALE = 0.16
local SPECK_MAX_SCALE = 0.34
local SPECK_EDGE_PADDING_SCALE = 0.08
local MAX_ACTIVE_SPECKS = 3
local DEFAULT_FRAME_RATE = 18

local TILE_ID = BuildServiceUtils.TILE_ID
local ORE_TILE_IDS = table.freeze({
	[TILE_ID.COPPER_ORE] = true,
	[TILE_ID.IRON_ORE] = true,
	[TILE_ID.SILVER_ORE] = true,
	[TILE_ID.GOLD_ORE] = true,
})

export type Shiny = typeof(setmetatable(
	{} :: {
		part: BasePart,
		maid: MaidClass,
		random: Random,
		activeSpecks: number,
		destroyed: boolean,
	},
	Shiny
))

local function createMaid(): MaidClass
	return Maid.new() :: MaidClass
end

local function CoercePositiveNumber(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return math.clamp(valueRaw, minimum, maximum)
end

local function GetTileId(instance: Instance): number?
	local tileId = instance:GetAttribute("TileId")
	if typeof(tileId) == "number" and tileId == tileId then
		return math.floor(tileId)
	end
	return nil
end

local function GetSurfaceFace(part: BasePart): Enum.NormalId
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return Enum.NormalId.Right
	end
	return if camera.CFrame.Position.X >= part.Position.X then Enum.NormalId.Right else Enum.NormalId.Left
end

local function GetTileSpan(instance: Instance, attributeName: string): number
	local value = instance:GetAttribute(attributeName)
	if typeof(value) ~= "number" or value ~= value then
		return 1
	end
	return math.max(1, math.floor(value))
end

local function GetTileFacePixels(part: BasePart): number
	local tileWidth = GetTileSpan(part, "TileWidth")
	local tileHeight = GetTileSpan(part, "TileHeight")
	local tileStudsY = part.Size.Y / tileHeight
	local tileStudsZ = part.Size.Z / tileWidth
	return math.max(tileStudsY, tileStudsZ, 0.01) * SURFACE_PIXELS_PER_STUD
end

local function isOreName(valueRaw: any): boolean
	if typeof(valueRaw) ~= "string" then
		return false
	end
	return string.find(string.lower(valueRaw), "ore", 1, true) ~= nil
end

local function GetColumns(): number
	local columns = math.max(1, math.floor(CoercePositiveNumber(ShinySheet.columns, 5, 1, 128)))
	return columns
end

local function GetOws(): number
	return math.max(1, math.floor(CoercePositiveNumber(ShinySheet.rows, 1, 1, 128)))
end

local function GetFrameRate(): number
	return CoercePositiveNumber(ShinySheet.frameRate, DEFAULT_FRAME_RATE, 1, 120)
end

local function GetFrameSize(): Vector2
	return if typeof(ShinySheet.frameSize) == "Vector2" then ShinySheet.frameSize else Vector2.new(32, 32)
end

local function GetPlayTimeSeconds(): number
	return (GetColumns() * GetOws()) / GetFrameRate()
end

function Shiny.IsOreTile(instanceRaw: any): boolean
	if typeof(instanceRaw) ~= "Instance" then
		return false
	end

	local instance = instanceRaw :: Instance
	if instance:GetAttribute("TileIsOre") == true then
		return true
	end

	local tileId = GetTileId(instance)
	if tileId ~= nil and ORE_TILE_IDS[tileId] == true then
		return true
	end

	return isOreName(instance:GetAttribute("TileName"))
end

function Shiny.new(partRaw: any, _contextRaw: any?): Shiny
	if typeof(partRaw) ~= "Instance" or not partRaw:IsA("BasePart") then
		error("Shiny.new expects a BasePart")
	end

	local self = setmetatable({
		part = partRaw :: BasePart,
		maid = createMaid(),
		random = Random.new(),
		activeSpecks = 0,
		destroyed = false,
	}, Shiny)

	self:Mount()
	return self
end

function Shiny.Mount(self: Shiny)
	if not Shiny.IsOreTile(self.part) then
		return
	end

	self:Preload()

	self.maid:GiveTask(Rx.interval(SPECK_ROLL_SECONDS):Subscribe(function()
		self:TrySpawnSpeck()
	end))
end

function Shiny.Preload(self: Shiny)
	if typeof(ShinySheet.image) ~= "string" or ShinySheet.image == "" then
		return
	end

	self.maid:GivePromise(ContentProviderUtils.promisePreload({ ShinySheet.image }):Catch(function()
		return false
	end))
end

function Shiny.TrySpawnSpeck(self: Shiny)
	if self.destroyed or self.part.Parent == nil then
		return
	end
	if self.activeSpecks >= MAX_ACTIVE_SPECKS then
		return
	end
	if self.random:NextNumber() > SPECK_ROLL_CHANCE then
		return
	end

	local facePixels = GetTileFacePixels(self.part)
	local sizePixels = math.floor(facePixels * self.random:NextNumber(SPECK_MIN_SCALE, SPECK_MAX_SCALE) + 0.5)
	local speckMaid = createMaid()
	local taskKey = {}
	self.maid[taskKey] = speckMaid
	local speckId = HttpService:GenerateGUID(false)

	self.activeSpecks += 1
	speckMaid:GiveTask(function()
		self.activeSpecks = math.max(0, self.activeSpecks - 1)
		tileThunks.RemoveShinySpeck(speckId)
	end)

	tileThunks.PublishShinySpeck({
		id = speckId,
		adornee = self.part,
		image = ShinySheet.image,
		columns = GetColumns(),
		rows = GetOws(),
		frameSize = GetFrameSize(),
		frameRate = GetFrameRate(),
		face = GetSurfaceFace(self.part),
		position = UDim2.fromScale(
			self.random:NextNumber(SPECK_EDGE_PADDING_SCALE, 1 - SPECK_EDGE_PADDING_SCALE),
			self.random:NextNumber(SPECK_EDGE_PADDING_SCALE, 1 - SPECK_EDGE_PADDING_SCALE)
		),
		size = UDim2.fromOffset(sizePixels, sizePixels),
	})

	speckMaid:GiveTask(Rx.delayed(GetPlayTimeSeconds()):Subscribe(function()
		if not self.destroyed then
			self.maid[taskKey] = nil
		end
	end))
end

function Shiny.Destroy(self: Shiny)
	if self.destroyed then
		return
	end

	self.destroyed = true
	tileThunks.ClearShinySpecksForAdornee(self.part)
	self.maid:Destroy()
end
return Shiny

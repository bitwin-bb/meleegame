--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local packageRoot = assert(gameRoot.Parent, "Missing AquariaBackup package root.")
local quentyPackages = assert(packageRoot.node_modules:FindFirstChild("@quenty"), "Missing @quenty packages.")

local Workspace = game:GetService("Workspace")

local ContentProviderUtils = require(quentyPackages.contentproviderutils.Client.ContentProviderUtils)
local Maid = require(quentyPackages.maid.Shared.Maid)
local Rx = require(quentyPackages.rx.Shared.Rx)

local BuildServiceClient = require(gameRoot.Shared.Features.world.BuildServiceClient)
local BuildServiceUtils = require(gameRoot.Shared.Features.world.BuildServiceUtils)
local Sheet = require(gameRoot.Client.Features.tile.modules.Sheet)
local WorldGenerationServiceClient = require(gameRoot.Shared.Features.worldGeneration.WorldGenerationServiceClient)
local tileThunks = require(gameRoot.Client.Features.tile.ui.state.tileThunks)

type MaidClass = {
	GiveTask: (self: MaidClass, task: any) -> any,
	GivePromise: (self: MaidClass, promise: any) -> any,
	DoCleaning: (self: MaidClass) -> (),
	Destroy: (self: MaidClass) -> (),
}

type BreakProgressPayload = {
	isActive: boolean,
	tileX: number,
	tileY: number,
	progress: number,
	progressUnits: number?,
	progressTotal: number?,
	targetKind: string?,
}

type TerrainBreakTarget = {
	part: BasePart,
	localTileX: number,
	localTileY: number,
	width: number,
	height: number,
}

local TileBreakServiceClient = {}
TileBreakServiceClient.ServiceName = "TileBreakServiceClient"

local maid: MaidClass? = nil
local initialized = false

local function hideBreak()
	tileThunks.clearBreak()
end

local function resolveProgress(payload: BreakProgressPayload): number
	if payload.progressTotal ~= nil and payload.progressTotal > 0 and payload.progressUnits ~= nil then
		return math.clamp(payload.progressUnits / payload.progressTotal, 0, 1)
	end
	return math.clamp(payload.progress, 0, 1)
end

local function resolveFrameIndex(progress: number): number
	local totalFrames = math.max(1, Sheet.columns * Sheet.rows)
	return math.clamp(math.ceil(math.clamp(progress, 0, 1) * totalFrames), 1, totalFrames)
end

local function resolveSurfaceFace(part: BasePart): Enum.NormalId
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return Enum.NormalId.Right
	end
	return if camera.CFrame.Position.X >= part.Position.X then Enum.NormalId.Right else Enum.NormalId.Left
end

local function resolveHoveredBreakTarget(tileX: number, tileY: number): TerrainBreakTarget?
	local runtime = (WorldGenerationServiceClient :: any).hoveredTerrainRuntime
	if typeof(runtime) ~= "table" then
		return nil
	end

	local runtimeAny = runtime :: { [string]: any }
	if runtimeAny.tileX ~= tileX or runtimeAny.tileY ~= tileY then
		return nil
	end

	local hoverPart = runtimeAny.hoverPart
	if typeof(hoverPart) ~= "Instance" or not hoverPart:IsA("BasePart") or hoverPart.Parent == nil then
		return nil
	end

	return {
		part = hoverPart,
		localTileX = 0,
		localTileY = 0,
		width = 1,
		height = 1,
	}
end

local function resolveTerrainBreakTarget(tileX: number, tileY: number): TerrainBreakTarget?
	local hoveredTarget = resolveHoveredBreakTarget(tileX, tileY)
	if hoveredTarget ~= nil then
		return hoveredTarget
	end

	local _, rectRuntime = (WorldGenerationServiceClient :: any):resolveTerrainRectRuntime(tileX, tileY)
	if typeof(rectRuntime) ~= "table" then
		return nil
	end

	local rectAny = rectRuntime :: { [string]: any }
	local part = rectAny.part
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or part.Parent == nil then
		return nil
	end
	if typeof(rectAny.tileMinX) ~= "number" or typeof(rectAny.tileMinY) ~= "number" then
		return nil
	end
	if typeof(rectAny.width) ~= "number" or typeof(rectAny.height) ~= "number" then
		return nil
	end

	local width = math.max(1, math.floor(rectAny.width))
	local height = math.max(1, math.floor(rectAny.height))
	local localTileX = tileX - math.floor(rectAny.tileMinX)
	local localTileY = tileY - math.floor(rectAny.tileMinY)
	if localTileX < 0 or localTileX >= width or localTileY < 0 or localTileY >= height then
		return nil
	end

	return {
		part = part,
		localTileX = localTileX,
		localTileY = localTileY,
		width = width,
		height = height,
	}
end

local function resolveImagePosition(target: TerrainBreakTarget, face: Enum.NormalId): UDim2
	local localTileX = if face == Enum.NormalId.Right then target.width - target.localTileX - 1 else target.localTileX
	return UDim2.fromOffset(
		(localTileX + 0.5) * Sheet.frameSize.X,
		(target.height - target.localTileY - 0.5) * Sheet.frameSize.Y
	)
end

local function applyBreakProgress(payloadRaw: any)
	if typeof(payloadRaw) ~= "table" then
		hideBreak()
		return
	end

	local payload = payloadRaw :: BreakProgressPayload
	if payload.isActive ~= true or payload.targetKind ~= "tile" then
		hideBreak()
		return
	end

	local tileX = BuildServiceUtils.sanitizeTileCoordinate(payload.tileX)
	local tileY = BuildServiceUtils.sanitizeTileCoordinate(payload.tileY)
	if tileX == nil or tileY == nil then
		hideBreak()
		return
	end

	local target = resolveTerrainBreakTarget(tileX, tileY)
	if target == nil then
		hideBreak()
		return
	end

	local progress = resolveProgress(payload)
	local face = resolveSurfaceFace(target.part)
	tileThunks.publishBreak({
		visible = progress > 0,
		adornee = target.part,
		image = Sheet.image,
		frameIndex = resolveFrameIndex(progress),
		columns = Sheet.columns,
		rows = Sheet.rows,
		frameSize = Sheet.frameSize,
		canvasSize = Vector2.new(target.width * Sheet.frameSize.X, target.height * Sheet.frameSize.Y),
		face = face,
		imagePosition = resolveImagePosition(target, face),
		imageSize = UDim2.fromOffset(Sheet.frameSize.X, Sheet.frameSize.Y),
		transparency = 0,
		tileX = tileX,
		tileY = tileY,
	})
end

local function preloadAssets()
	local activeMaid = maid
	if activeMaid == nil or Sheet.image == "" then
		return
	end
	activeMaid:GivePromise(ContentProviderUtils.promisePreload({ Sheet.image }):Catch(function()
		return false
	end))
end

local function bindBreakProgress()
	local activeMaid = maid
	if activeMaid == nil then
		return
	end

	activeMaid:GiveTask(Rx.fromSignal((BuildServiceClient :: any).breakProgressChanged)
		:Pipe({
			Rx.startWith({ (BuildServiceClient :: any).currentBreakProgress }),
		})
		:Subscribe(function(payload: any)
			applyBreakProgress(payload)
		end))
end

function TileBreakServiceClient.Init(_self: any)
	if maid == nil then
		local activeMaid = Maid.new()
		maid = activeMaid
		activeMaid:GiveTask(function()
			hideBreak()
			initialized = false
		end)
	end

	if initialized then
		return
	end

	preloadAssets()
	bindBreakProgress()
	initialized = true
end

function TileBreakServiceClient.Destroy(_self: any)
	if maid == nil then
		return
	end
	maid:DoCleaning()
	maid = nil
end

TileBreakServiceClient.init = TileBreakServiceClient.Init
TileBreakServiceClient.destroy = TileBreakServiceClient.Destroy

return TileBreakServiceClient

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ConnectionUtils = require(script:FindFirstAncestor("game").Client.UI.core.utils.ConnectionUtils)
local BuildServiceClient = require(script:FindFirstAncestor("game").Client.Services.BuildServiceClient)
local BuildServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BuildServiceUtils)
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Modules.Core.WorkspaceFolders)
local miningProgressSlice = require(script:FindFirstAncestor("game").Client.UI.features.mining.state.miningProgressSlice)

type BuildServiceState = BuildServiceUtils.BuildServiceState
type MiningProgressState = miningProgressSlice.MiningProgressState

type BuildProgressPayload = {
	isActive: boolean,
	tileX: number,
	tileY: number,
	progress: number,
	breakDuration: number,
	progressMode: string?,
	progressUnits: number?,
	progressTotal: number?,
	updatedAt: number,
}

local miningProgressThunks = {}

local ANCHOR_PART_NAME = "MiningProgressAnchor"

local runtime = {
	started = false,
	breakProgressConnection = nil :: RBXScriptConnection?,
	billboardGui = nil :: BillboardGui?,
	anchorPart = nil :: Part?,
}

local function sanitizeBuildState(stateRaw: any): BuildServiceState?
	if typeof(stateRaw) ~= "table" then
		return nil
	end
	local stateAny = stateRaw :: any
	if typeof(stateAny.worldOrigin) ~= "Vector3" then
		return nil
	end
	if typeof(stateAny.tileSize) ~= "number" or stateAny.tileSize <= 0 then
		return nil
	end
	if typeof(stateAny.basePlaneX) ~= "number" then
		return nil
	end
	return stateRaw :: BuildServiceState
end

local function ensureAnchorPart(): Part
	local current = runtime.anchorPart
	if current ~= nil and current.Parent ~= nil then
		return current
	end

	local gameFolder = WorkspaceFolders.getOrCreateGameFolder()
	local existing = gameFolder:FindFirstChild(ANCHOR_PART_NAME)
	if existing ~= nil then
		if existing:IsA("Part") then
			runtime.anchorPart = existing
			return existing
		end
		existing:Destroy()
	end

	local legacy = Workspace:FindFirstChild(ANCHOR_PART_NAME)
	if legacy ~= nil then
		if legacy:IsA("Part") then
			legacy.Parent = gameFolder
			runtime.anchorPart = legacy
			return legacy
		end
		legacy:Destroy()
	end

	local part = Instance.new("Part")
	part.Name = ANCHOR_PART_NAME
	part.Size = Vector3.new(0.05, 0.05, 0.05)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Locked = true
	part.CastShadow = false
	part.CFrame = CFrame.new(0, -10000, 0)
	part.Parent = gameFolder
	runtime.anchorPart = part
	return part
end

local function hideAnchorPart()
	local anchorPart = runtime.anchorPart
	if anchorPart == nil then
		return
	end
	anchorPart.CFrame = CFrame.new(0, -10000, 0)
end

local function applyToBillboard(state: MiningProgressState)
	local billboardGui = runtime.billboardGui
	if billboardGui == nil then
		return
	end

	if state.visible ~= true or state.worldPosition == nil then
		billboardGui.Enabled = false
		billboardGui.Adornee = nil
		hideAnchorPart()
		return
	end

	local anchorPart = ensureAnchorPart()
	anchorPart.CFrame = CFrame.new(state.worldPosition)
	billboardGui.Adornee = anchorPart
	billboardGui.Enabled = true
end

local function hideMiningProgressVisual()
	local nextState = miningProgressSlice.hideMiningProgress()
	applyToBillboard(nextState)
end

local function resolveBreakWorldPosition(tileX: number, tileY: number): Vector3?
	local state = sanitizeBuildState((BuildServiceClient :: any).state)
	if state == nil then
		return nil
	end
	local worldCenter = BuildServiceUtils.tileToWorldCenter(
		tileX,
		tileY,
		state.worldOrigin,
		state.tileSize,
		state.basePlaneX
	)
	return worldCenter + Vector3.new(0, state.tileSize * 0.92, 0)
end

local function applyBuildBreakProgress(payloadRaw: any): MiningProgressState
	if typeof(payloadRaw) ~= "table" then
		hideMiningProgressVisual()
		return miningProgressSlice.getMiningProgressState()
	end

	local payload = payloadRaw :: { [string]: any }
	if payload.isActive ~= true then
		hideMiningProgressVisual()
		return miningProgressSlice.getMiningProgressState()
	end

	local tileX = BuildServiceUtils.sanitizeTileCoordinate(payload.tileX)
	local tileY = BuildServiceUtils.sanitizeTileCoordinate(payload.tileY)
	if tileX == nil or tileY == nil then
		hideMiningProgressVisual()
		return miningProgressSlice.getMiningProgressState()
	end

	local worldPosition = resolveBreakWorldPosition(tileX, tileY)
	if worldPosition == nil then
		hideMiningProgressVisual()
		return miningProgressSlice.getMiningProgressState()
	end

	local progressRaw = payload.progress
	local progress = if typeof(progressRaw) == "number" and progressRaw == progressRaw then math.clamp(progressRaw, 0, 1) else 0
	local nextState = miningProgressSlice.showMiningProgress({
		progress = progress,
		tileX = tileX,
		tileY = tileY,
		worldPosition = worldPosition,
	})
	applyToBillboard(nextState)
	return nextState
end

function miningProgressThunks.Start(): () -> ()
	if runtime.started then
		return miningProgressThunks.Stop
	end

	runtime.started = true
	local breakProgressSignal = (BuildServiceClient :: any).breakProgressChanged
	if breakProgressSignal ~= nil then
		runtime.breakProgressConnection = breakProgressSignal:Connect(function(payload: BuildProgressPayload?)
			applyBuildBreakProgress(payload)
		end)
	end

	local currentProgress = (BuildServiceClient :: any).currentBreakProgress
	applyBuildBreakProgress(currentProgress)

	return miningProgressThunks.Stop
end

function miningProgressThunks.Stop()
	ConnectionUtils.disconnect(runtime.breakProgressConnection)
	runtime.breakProgressConnection = nil
	runtime.started = false
	hideMiningProgressVisual()
	if runtime.anchorPart ~= nil then
		runtime.anchorPart:Destroy()
		runtime.anchorPart = nil
	end
end

function miningProgressThunks.BindBillboardGui(guiRaw: any)
	local billboardGui = if typeof(guiRaw) == "Instance" and guiRaw:IsA("BillboardGui")
		then guiRaw
		else nil
	runtime.billboardGui = billboardGui
	if billboardGui == nil then
		return
	end
	applyToBillboard(miningProgressSlice.getMiningProgressState())
end

function miningProgressThunks.GetState(): MiningProgressState
	return miningProgressSlice.getMiningProgressState()
end

miningProgressThunks.start = miningProgressThunks.Start
miningProgressThunks.stop = miningProgressThunks.Stop
miningProgressThunks.bindBillboardGui = miningProgressThunks.BindBillboardGui
miningProgressThunks.getState = miningProgressThunks.GetState

return miningProgressThunks

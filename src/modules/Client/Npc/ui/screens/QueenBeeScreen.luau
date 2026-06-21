local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")


local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Maid = require("Maid")

local BossServiceUtils = require("BossServiceUtils")
local QueenBee = require("QueenBeeComponent")
local QueenBeeSpriteSheet = require("QueenBeeSpriteSheet")
local React = require(ReplicatedStorage.Packages.React)
local WorkspaceFolders = require("WorkspaceFolders")
local markerSlice = require("markerSlice")
local markerThunks = require("markerThunks")
local useStore = require("useCoreStore")

type BossServiceState = BossServiceUtils.BossServiceState
type BossSnapshot = BossServiceUtils.BossSnapshot

export type QueenBeeScreenProps = {
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement
local BOSS_RUNTIME_FOLDER_NAME = "BossRuntime"
local runtimeRootPartCache: { [string]: BasePart? } = {}

local function resolveRuntimeRootPart(runtimeId: string): BasePart?
	local cachedRootPart = runtimeRootPartCache[runtimeId]
	if cachedRootPart ~= nil and cachedRootPart:IsDescendantOf(Workspace) then
		return cachedRootPart
	end
	runtimeRootPartCache[runtimeId] = nil

	local runtimeFolder = WorkspaceFolders.findFolderInGameOrWorkspace(BOSS_RUNTIME_FOLDER_NAME)
	if runtimeFolder == nil then
		return nil
	end

	for _, child in runtimeFolder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		if child:GetAttribute(BossServiceUtils.RUNTIME_ID_ATTRIBUTE) ~= runtimeId then
			continue
		end

		local rootPart = BossServiceUtils.resolveRootPart(child)
		if rootPart ~= nil then
			runtimeRootPartCache[runtimeId] = rootPart
		end
		return rootPart
	end

	return nil
end

local function selectBossState(state: BossServiceState?): BossServiceState
	if state ~= nil then
		return state
	end
	return markerSlice.getMarkerState()
end

local function isQueenBeeSnapshot(snapshot: BossSnapshot?): boolean
	return snapshot ~= nil and snapshot.bossId == "QueenBee"
end

local function renderSurfaceBoss(snapshot: BossSnapshot, rootPart: BasePart, zIndex: number, renderClock: number)
	return e("SurfaceGui", {
		Adornee = rootPart,
		AlwaysOnTop = true,
		ClipsDescendants = true,
		Face = Enum.NormalId.Right,
		LightInfluence = 0,
		PixelsPerStud = QueenBeeSpriteSheet.pixelsPerStud,
		ResetOnSpawn = false,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		e(QueenBee, {
			snapshot = snapshot,
			renderClock = renderClock,
			surfaceGui = true,
			zIndex = zIndex,
		}),
	})
end

return function(props: QueenBeeScreenProps): React.ReactNode
	local zIndex = if typeof(props.zIndex) == "number" then props.zIndex else 169
	local renderClock, setRenderClock = React.useState(os.clock())
	local bossState = useStore(markerSlice.markerStateAtom, selectBossState) :: BossServiceState

	React.useEffect(function()
		local maid = Maid.new()
		local stop = markerThunks.start()
		maid:GiveTask(stop)
		maid:GiveTask(RunService.RenderStepped:Connect(function()
			setRenderClock(os.clock())
		end))

		return function()
			maid:DoCleaning()
		end
	end, {})

	local children: { [string]: React.ReactNode } = {}
	for index, runtimeId in bossState.orderedIds do
		local snapshot = bossState.byId[runtimeId]
		if not isQueenBeeSnapshot(snapshot) then
			continue
		end

		local displayOrder = zIndex + index
		local rootPart = resolveRuntimeRootPart(runtimeId)
		if rootPart == nil then
			continue
		end

		children[runtimeId] = renderSurfaceBoss(snapshot :: BossSnapshot, rootPart, displayOrder, renderClock)
	end

	return e(React.Fragment, nil, children)
end

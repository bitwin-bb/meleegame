local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")


local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Maid = require("Maid")

local BossServiceUtils = require("BossServiceUtils")
local EyeOfCthulhu = require("EyeOfCthulhuComponent")
local EyeOfCthulhuSpriteSheet = require("EyeOfCthulhuSpriteSheet")
local React = require(ReplicatedStorage.Packages.React)
local WorkspaceFolders = require("WorkspaceFolders")
local markerSlice = require("MarkerSlice")
local markerThunks = require("MarkerThunks")
local useStore = require("useCoreStore")

type BossServiceState = BossServiceUtils.BossServiceState
type BossSnapshot = BossServiceUtils.BossSnapshot

export type EyeOfCthulhuScreenProps = {
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement
local BOSS_RUNTIME_FOLDER_NAME = "BossRuntime"
local runtimeRootPartCache: { [string]: BasePart? } = {}

local function GetUntimeRootPart(runtimeId: string): BasePart?
	local cachedRootPart = runtimeRootPartCache[runtimeId]
	if cachedRootPart ~= nil and cachedRootPart:IsDescendantOf(Workspace) then
		return cachedRootPart
	end
	runtimeRootPartCache[runtimeId] = nil

	local runtimeFolder = WorkspaceFolders.FindFolderInGameOrWorkspace(BOSS_RUNTIME_FOLDER_NAME)
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

		local rootPart = BossServiceUtils.GetRootPart(child)
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

local function isEyeOfCthulhuSnapshot(snapshot: BossSnapshot?): boolean
	return snapshot ~= nil and snapshot.bossId == "EyeOfCthulhu"
end

local function renderSurfaceBoss(snapshot: BossSnapshot, rootPart: BasePart, zIndex: number, renderClock: number)
	return e("SurfaceGui", {
		Adornee = rootPart,
		AlwaysOnTop = true,
		ClipsDescendants = false,
		Face = Enum.NormalId.Right,
		LightInfluence = 0,
		PixelsPerStud = EyeOfCthulhuSpriteSheet.pixelsPerStud,
		ResetOnSpawn = false,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		e(EyeOfCthulhu, {
			snapshot = snapshot,
			renderClock = renderClock,
			surfaceGui = true,
			zIndex = zIndex,
		}),
	})
end

local function renderScreenBoss(snapshot: BossSnapshot, zIndex: number, renderClock: number)
	return e("ScreenGui", {
		DisplayOrder = zIndex,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.None,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		e(EyeOfCthulhu, {
			snapshot = snapshot,
			renderClock = renderClock,
			zIndex = zIndex,
		}),
	})
end

return function(props: EyeOfCthulhuScreenProps): React.ReactNode
	local zIndex = if typeof(props.zIndex) == "number" then props.zIndex else 166
	local renderClock, setRenderClock = React.useState(os.clock())
	local bossState = useStore(markerSlice.markerStateAtom, selectBossState) :: BossServiceState

	React.useEffect(function()
		local maid = Maid.new()
		local stop = markerThunks.Start()
		maid:GiveTask(stop)
		maid:GiveTask(RunService.RenderStepped:Connect(function()
			setRenderClock(os.clock())
		end))

		return function()
			maid:DoCleaning()
		end
	end, {})

	local children: { React.ReactNode } = {}
	for index, runtimeId in bossState.orderedIds do
		local snapshot = bossState.byId[runtimeId]
		if not isEyeOfCthulhuSnapshot(snapshot) then
			continue
		end

		local displayOrder = zIndex + index
		local rootPart = GetUntimeRootPart(runtimeId)
		children[#children + 1] = if rootPart ~= nil
			then renderSurfaceBoss(snapshot :: BossSnapshot, rootPart, displayOrder, renderClock)
			else renderScreenBoss(snapshot :: BossSnapshot, displayOrder, renderClock)
	end

	return e(React.Fragment, nil, children)
end

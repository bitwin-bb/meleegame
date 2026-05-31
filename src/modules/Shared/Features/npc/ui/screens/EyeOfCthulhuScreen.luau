--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = (require :: any)(loaderUtils.Parent).load(script)

local Maid = loader("Maid")

local BossServiceUtils = require(script:FindFirstAncestor("game").Shared.Features.npc.BossServiceUtils)
local EyeOfCthulhu = require(script:FindFirstAncestor("game").Shared.Features.npc.ui.components.EyeOfCthulhu)
local EyeOfCthulhuSpriteSheet =
	require(script:FindFirstAncestor("game").Shared.Features.npc.modules.EyeOfCthulhuSpriteSheet)
local React = require(ReplicatedStorage.Packages.React)
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Core.WorkspaceFolders)
local markerSlice = require(script:FindFirstAncestor("game").Shared.Features.npc.ui.boss.state.markerSlice)
local markerThunks = require(script:FindFirstAncestor("game").Shared.Features.npc.ui.boss.state.markerThunks)
local useStore = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useStore)

type BossServiceState = BossServiceUtils.BossServiceState
type BossSnapshot = BossServiceUtils.BossSnapshot

export type EyeOfCthulhuScreenProps = {
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
		local stop = markerThunks.start()
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
		local rootPart = resolveRuntimeRootPart(runtimeId)
		children[#children + 1] = if rootPart ~= nil
			then renderSurfaceBoss(snapshot :: BossSnapshot, rootPart, displayOrder, renderClock)
			else renderScreenBoss(snapshot :: BossSnapshot, displayOrder, renderClock)
	end

	return e(React.Fragment, nil, children)
end

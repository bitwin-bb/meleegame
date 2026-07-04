local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")


local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Maid = require("Maid")

local NpcServiceUtils = require("NpcServiceUtils")
local NpcSlice = require("NpcSlice")
local NpcThunks = require("NpcThunks")
local React: any = require(ReplicatedStorage.Packages.React)
local Slime = require("SlimeComponent")
local SlimeSpriteSheet = require("SlimeSpriteSheet")
local WorkspaceFolders = require("WorkspaceFolders")
local useDie = require("useDie")
local useStore = require("useCoreStore")

type NpcViewState = NpcSlice.NpcViewState
type SlimeGoreSprite = NpcSlice.SlimeGoreSprite

export type SlimeScreenProps = {
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement
local NPC_RUNTIME_FOLDER_NAME = "NpcRuntime"
local runtimeRootPartCache: { [string]: BasePart? } = {}

local function GetModelRootPart(model: Model): BasePart?
	local rootPart = model:FindFirstChild("RootPart")
	if rootPart ~= nil and rootPart:IsA("BasePart") then
		return rootPart
	end
	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function GetUntimeRootPart(runtimeId: string): BasePart?
	local cachedRootPart = runtimeRootPartCache[runtimeId]
	if cachedRootPart ~= nil and cachedRootPart:IsDescendantOf(Workspace) then
		return cachedRootPart
	end
	runtimeRootPartCache[runtimeId] = nil

	local runtimeFolder = WorkspaceFolders.FindFolderInGameOrWorkspace(NPC_RUNTIME_FOLDER_NAME)
	if runtimeFolder == nil then
		return nil
	end

	for _, child in runtimeFolder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		if child:GetAttribute(NpcServiceUtils.RUNTIME_ID_ATTRIBUTE) ~= runtimeId then
			continue
		end

		local rootPart = GetModelRootPart(child)
		if rootPart ~= nil then
			runtimeRootPartCache[runtimeId] = rootPart
		end
		return rootPart
	end

	return nil
end

local function selectViewState(state: NpcViewState?): NpcViewState
	if state ~= nil then
		return state
	end
	return NpcSlice.GetViewState()
end

local function selectGoreSprites(state: { [string]: SlimeGoreSprite }?): { [string]: SlimeGoreSprite }
	if state ~= nil then
		return state
	end
	return {}
end

return function(props: SlimeScreenProps)
	local zIndex = if typeof(props.zIndex) == "number" then props.zIndex else 120
	local renderClock, setRenderClock = React.useState(os.clock())
	local viewState = useStore(NpcSlice.npcViewStateAtom, selectViewState) :: NpcViewState
	local goreSprites = useStore(NpcSlice.slimeGoreSpritesAtom, selectGoreSprites) :: { [string]: SlimeGoreSprite }

	useDie(viewState.byId)

	React.useEffect(function()
		local maid = Maid.new()
		local stopClientSync = NpcThunks.StartClientSync()
		maid:GiveTask(stopClientSync)
		maid:GiveTask(RunService.RenderStepped:Connect(function()
			local now = os.clock()
			NpcThunks.PruneSlimeGore(now)
			setRenderClock(now)
		end))

		return function()
			maid:DoCleaning()
		end
	end, {})

	local children: { React.ReactNode } = {}
	for index, runtimeId in viewState.orderedIds do
		local snapshot = viewState.byId[runtimeId]
		if snapshot ~= nil then
			local displayOrder = zIndex + index
			children[#children + 1] = e("SurfaceGui", {
				Adornee = GetUntimeRootPart(runtimeId),
				AlwaysOnTop = true,
				ClipsDescendants = false,
				Face = Enum.NormalId.Right,
				LightInfluence = 0,
				PixelsPerStud = SlimeSpriteSheet.pixelsPerStud,
				ResetOnSpawn = false,
				SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			}, {
				e(Slime, {
					snapshot = snapshot,
					renderClock = renderClock,
					surfaceGui = true,
					zIndex = displayOrder,
				}),
			})
		end
	end

	for _, sprite in goreSprites do
		local displayOrder = zIndex + 80
		children[#children + 1] = e("ScreenGui", {
			DisplayOrder = displayOrder,
			IgnoreGuiInset = true,
			ResetOnSpawn = false,
			ScreenInsets = Enum.ScreenInsets.None,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		}, {
			e(Slime, {
				gore = sprite,
				renderClock = renderClock,
				zIndex = displayOrder,
			}),
		})
	end

	return e(React.Fragment, nil, children)
end

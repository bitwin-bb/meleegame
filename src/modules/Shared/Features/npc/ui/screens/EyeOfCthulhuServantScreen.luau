--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local packageRoot = assert(gameRoot.Parent, "Missing AquariaBackup package root.")
local quentyPackages = assert(packageRoot.node_modules:FindFirstChild("@quenty"), "Missing @quenty packages.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")

local Maid = require(quentyPackages.maid.Shared.Maid)

local EyeOfCthulhuServant = require(gameRoot.Shared.Features.npc.ui.components.EyeOfCthulhuServant)
local React = require(ReplicatedStorage.Packages.React)
local ServantSpriteSheet = require(gameRoot.Shared.Features.npc.modules.ServantSpriteSheet)
local WorkspaceFolders = require(gameRoot.Shared.Core.WorkspaceFolders)

export type EyeOfCthulhuServantScreenProps = {
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement
local SERVANT_FOLDER_NAME = "BossServants"

local function resolveModelRootPart(model: Model): BasePart?
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

return function(props: EyeOfCthulhuServantScreenProps): React.ReactNode
	local zIndex = if typeof(props.zIndex) == "number" then props.zIndex else 167
	local _, setRenderClock = React.useState(os.clock())

	React.useEffect(function()
		local maid = Maid.new()
		maid:GiveTask(RunService.RenderStepped:Connect(function()
			setRenderClock(os.clock())
		end))

		return function()
			maid:DoCleaning()
		end
	end, {})

	local children: { React.ReactNode } = {}
	local servantFolder = WorkspaceFolders.findFolderInGameOrWorkspace(SERVANT_FOLDER_NAME)
	if servantFolder ~= nil then
		for index, child in servantFolder:GetChildren() do
			if not child:IsA("Model") or child:GetAttribute("BossServantSpriteRoot") ~= true then
				continue
			end

			local rootPart = resolveModelRootPart(child)
			if rootPart == nil then
				continue
			end

			local displayOrder = zIndex + index
			children[#children + 1] = e("SurfaceGui", {
				Adornee = rootPart,
				AlwaysOnTop = true,
				ClipsDescendants = false,
				Face = Enum.NormalId.Right,
				LightInfluence = 0,
				PixelsPerStud = ServantSpriteSheet.pixelsPerStud,
				ResetOnSpawn = false,
				SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			}, {
				e(EyeOfCthulhuServant, {
					zIndex = displayOrder,
				}),
			})
		end
	end

	return e(React.Fragment, nil, children)
end

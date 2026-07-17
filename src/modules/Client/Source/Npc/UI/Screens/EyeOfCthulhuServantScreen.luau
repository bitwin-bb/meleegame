local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")

local Maid = require("Maid")

local EyeOfCthulhuServant = require("EyeOfCthulhuServant")
local React: any = require(ReplicatedStorage.Packages.React)
local ServantSpriteSheet = require("ServantSpriteSheet")
local WorkspaceFolders = require("WorkspaceFolders")

export type EyeOfCthulhuServantScreenProps = {
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement
local SERVANT_FOLDER_NAME = "BossServants"

local function getModelRootPart(model: Model): BasePart?
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
	local servantFolder = WorkspaceFolders.FindFolderInGameOrWorkspace(SERVANT_FOLDER_NAME)
	if servantFolder ~= nil then
		for index, child in servantFolder:GetChildren() do
			if not child:IsA("Model") or child:GetAttribute("BossServantSpriteRoot") ~= true then
				continue
			end

			local rootPart = getModelRootPart(child)
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

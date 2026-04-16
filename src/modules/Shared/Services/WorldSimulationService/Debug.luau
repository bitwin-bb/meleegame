--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Modules.Core.WorkspaceFolders)

local Debug = {}
Debug.__index = Debug

export type Debug = typeof(setmetatable({} :: any, Debug))

local DEFAULT_FOLDER_NAME = "WorldSimulationDebug"

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Debug.New(configRaw: any)
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local self = setmetatable({
		enabled = (config :: any).enabled == true,
		profilingEnabled = (config :: any).profilingEnabled == true,
		counters = {} :: { [string]: number },
		frameTimers = {} :: { [string]: number },
		visualFolder = nil :: Folder?,
		chunkVisuals = {} :: { [string]: BasePart },
	}, Debug)
	return self
end

function Debug:IsEnabled(): boolean
	return self.enabled
end

function Debug:BeginFrameScope(label: string): number?
	if not self.enabled or not self.profilingEnabled then
		return nil
	end
	self.frameTimers[label] = os.clock()
	return self.frameTimers[label]
end

function Debug:EndFrameScope(label: string, token: number?)
	if not self.enabled or not self.profilingEnabled then
		return
	end
	local startTime = if token ~= nil then token else self.frameTimers[label]
	if startTime == nil then
		return
	end
	local elapsed = math.max(0, os.clock() - startTime)
	self.counters[`time_{label}`] = (self.counters[`time_{label}`] or 0) + elapsed
	self.frameTimers[label] = nil
end

function Debug:IncrementCounter(name: string, amountRaw: any)
	if not self.enabled then
		return
	end
	local amount = if isFiniteNumber(amountRaw) then amountRaw else 1
	self.counters[name] = (self.counters[name] or 0) + amount
end

function Debug:SetCounter(name: string, valueRaw: any)
	if not self.enabled then
		return
	end
	local value = if isFiniteNumber(valueRaw) then valueRaw else 0
	self.counters[name] = value
end

function Debug:ResetFrameCounters()
	if not self.enabled then
		return
	end
	table.clear(self.counters)
	table.clear(self.frameTimers)
end

function Debug:GetCounters(): { [string]: number }
	if not self.enabled then
		return {}
	end
	local cloned = {}
	for name, value in self.counters do
		cloned[name] = value
	end
	return cloned
end

function Debug:ValidateChunkArrays(chunkRaw: any): boolean
	if not self.enabled then
		return true
	end
	if typeof(chunkRaw) ~= "table" then
		self:incrementCounter("chunk_validation_fail")
		return false
	end

	local chunk = chunkRaw :: { [string]: any }
	local clusterCountX = if isFiniteNumber(chunk.clusterCountX) then math.max(1, math.floor(chunk.clusterCountX)) else 1
	local clusterCountY = if isFiniteNumber(chunk.clusterCountY) then math.max(1, math.floor(chunk.clusterCountY)) else 1
	local clusterCountZ = if isFiniteNumber(chunk.clusterCountZ) then math.max(1, math.floor(chunk.clusterCountZ)) else 1
	local expectedClusters = clusterCountX * clusterCountY * clusterCountZ

	local valid = true
	if typeof(chunk.clusterChosenBiomeIds) ~= "table" or #chunk.clusterChosenBiomeIds ~= expectedClusters then
		valid = false
	end
	if typeof(chunk.clusterBlendWeights) ~= "table" or #chunk.clusterBlendWeights ~= expectedClusters then
		valid = false
	end
	if typeof(chunk.clusterSolidMask) ~= "table" or #chunk.clusterSolidMask ~= expectedClusters then
		valid = false
	end
	if typeof(chunk.clusterSurfaceY) ~= "table" or #chunk.clusterSurfaceY ~= expectedClusters then
		valid = false
	end

	if not valid then
		self:incrementCounter("chunk_validation_fail")
	else
		self:incrementCounter("chunk_validation_ok")
	end

	return valid
end

function Debug:EnsureVisualFolder(parentRaw: any): Folder?
	if not self.enabled then
		return nil
	end
	if self.visualFolder ~= nil and self.visualFolder.Parent ~= nil then
		return self.visualFolder
	end

	local parent = if typeof(parentRaw) == "Instance" then parentRaw else WorkspaceFolders.getOrCreateGameFolder()
	local existing = parent:FindFirstChild(DEFAULT_FOLDER_NAME)
	if existing ~= nil and existing:IsA("Folder") then
		self.visualFolder = existing
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = DEFAULT_FOLDER_NAME
	folder.Parent = parent
	self.visualFolder = folder
	return folder
end

function Debug:DrawChunkBox(chunkKey: string, center: Vector3, size: Vector3, color: Color3?)
	if not self.enabled then
		return
	end
	local folder = self:ensureVisualFolder(nil)
	if folder == nil then
		return
	end

	local part = self.chunkVisuals[chunkKey]
	if part == nil or part.Parent == nil then
		part = Instance.new("Part")
		part.Name = `Chunk_{chunkKey}`
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Material = Enum.Material.ForceField
		part.Transparency = 0.85
		part.Parent = folder
		self.chunkVisuals[chunkKey] = part
	end

	part.Size = size
	part.CFrame = CFrame.new(center)
	part.Color = color or Color3.fromRGB(75, 190, 255)
end

function Debug:ClearChunkBox(chunkKey: string)
	local part = self.chunkVisuals[chunkKey]
	if part ~= nil then
		self.chunkVisuals[chunkKey] = nil
		part:Destroy()
	end
end

function Debug:Destroy()
	for chunkKey, part in self.chunkVisuals do
		self.chunkVisuals[chunkKey] = nil
		part:Destroy()
	end
	if self.visualFolder ~= nil then
		self.visualFolder:Destroy()
		self.visualFolder = nil
	end
	table.clear(self.counters)
	table.clear(self.frameTimers)
end

Debug.new = Debug.New
Debug.isEnabled = Debug.IsEnabled
Debug.beginFrameScope = Debug.BeginFrameScope
Debug.endFrameScope = Debug.EndFrameScope
Debug.incrementCounter = Debug.IncrementCounter
Debug.setCounter = Debug.SetCounter
Debug.resetFrameCounters = Debug.ResetFrameCounters
Debug.getCounters = Debug.GetCounters
Debug.validateChunkArrays = Debug.ValidateChunkArrays
Debug.ensureVisualFolder = Debug.EnsureVisualFolder
Debug.drawChunkBox = Debug.DrawChunkBox
Debug.clearChunkBox = Debug.ClearChunkBox
Debug.destroy = Debug.Destroy

return Debug

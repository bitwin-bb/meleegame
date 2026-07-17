local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local CmdrUtils = require("CmdrUtils")
local Maid = require("Maid")
local MatterDebugMenuClient = require("MatterDebugMenuClient")

type MaidClass = any

local CmdrBootstrapClient = {}
CmdrBootstrapClient.ServiceName = "CmdrBootstrapClient"

local localPlayer = Players.LocalPlayer
local MATTER_DEBUGGER_REMOTE_NAME = "MatterDebuggerRemote"

local function findValidStarterGuiCmdr(): ScreenGui?
	local cmdrGui = CmdrUtils.KeepSingleValidCmdrGui(StarterGui)

	while cmdrGui ~= nil and not CmdrUtils.IsValidCmdrGui(cmdrGui) do
		task.wait()
		cmdrGui = CmdrUtils.KeepSingleValidCmdrGui(StarterGui)
	end

	return cmdrGui
end

local function preparePlayerGuiForCmdr(): ScreenGui?
	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	if playerGui == nil or not playerGui:IsA("PlayerGui") then
		return nil
	end

	return CmdrUtils.KeepSingleValidCmdrGui(playerGui)
end

local function findCmdrTypesFolder(): Folder?
	local gameRoot = script:FindFirstAncestor("game")
	local sharedRoot = if gameRoot ~= nil then gameRoot:FindFirstChild("Shared") else nil
	local sourceRoot = if sharedRoot ~= nil then sharedRoot:FindFirstChild("Source") else nil
	local commanderRoot = if sourceRoot ~= nil then sourceRoot:FindFirstChild("Commander") else nil
	local typesFolder = if commanderRoot ~= nil then commanderRoot:FindFirstChild("Types") else nil
	if typesFolder == nil or not typesFolder:IsA("Folder") then
		return nil
	end

	return typesFolder
end

local function registerCmdrTypes(self: any): boolean
	if self._cmdrTypesRegistered then
		return true
	end

	local typesFolder = findCmdrTypesFolder()
	if typesFolder == nil then
		return false
	end

	local registeredTypeCount = CmdrUtils.RegisterTypesIn(self._cmdrClient.Registry, typesFolder)
	assert(registeredTypeCount > 0, "[CmdrBootstrapClient] No valid Cmdr types were registered.")
	self._cmdrTypesRegistered = true
	return true
end

local function ensureCmdrClient(self: any): any
	if self._cmdrClient ~= nil then
		if not registerCmdrTypes(self) then
			return nil
		end
		self._cmdrClient:SetActivationUnlocksMouse(true)
		self._cmdrClient:SetActivationKeys({ Enum.KeyCode.F2 })
		self._cmdrClient:SetEnabled(false)
		return self._cmdrClient
	end

	local starterGuiCmdr = findValidStarterGuiCmdr()
	if starterGuiCmdr == nil then
		return nil
	end

	local existingGui = preparePlayerGuiForCmdr()
	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	if playerGui == nil or not playerGui:IsA("PlayerGui") then
		return nil
	end

	if existingGui == nil then
		starterGuiCmdr:Clone().Parent = playerGui
		existingGui = CmdrUtils.KeepSingleValidCmdrGui(playerGui)
	end

	if existingGui == nil then
		return nil
	end

	local cmdrClientModule = ReplicatedStorage:FindFirstChild("CmdrClient")
	if cmdrClientModule == nil or not cmdrClientModule:IsA("ModuleScript") then
		return nil
	end

	local ok, cmdrClient = pcall(require, cmdrClientModule :: any)
	assert(ok, `[CmdrBootstrapClient] Failed to require CmdrClient: {cmdrClient}`)
	self._cmdrClient = cmdrClient
	if not registerCmdrTypes(self) then
		return nil
	end
	self._cmdrClient:SetActivationUnlocksMouse(true)
	self._cmdrClient:SetActivationKeys({ Enum.KeyCode.F2 })
	self._cmdrClient:SetEnabled(false)
	return self._cmdrClient
end

local function scheduleCmdrRetry(self: any)
	if self._pendingCmdrRetry then
		return
	end

	self._pendingCmdrRetry = true
	local retryThread = task.delay(0.1, function()
		self._pendingCmdrRetry = false
		if self._maid == nil then
			return
		end

		self:ApplyCmdrAccess()
	end)
	self._maid:GiveTask(retryThread)
end

function CmdrBootstrapClient.ApplyCmdrAccess(self: any)
	local cmdrEnabled = localPlayer:GetAttribute(CmdrUtils.CMDR_ENABLED_ATTRIBUTE) == true or RunService:IsStudio()
	if not cmdrEnabled then
		if self._cmdrClient ~= nil then
			self._cmdrClient:SetEnabled(false)
			self._cmdrClient:Hide()
		end
		return
	end

	local ensuredClient = ensureCmdrClient(self)
	if ensuredClient ~= nil then
		ensuredClient:SetEnabled(true)
	else
		scheduleCmdrRetry(self)
	end
end

local function applyMatterDebugMenuAccess(self: any)
	local matterDebugEnabled = localPlayer:GetAttribute(CmdrUtils.MATTER_DEBUG_MENU_ENABLED_ATTRIBUTE) == true
	if not matterDebugEnabled then
		self._matterDebugInitScheduled = false
		MatterDebugMenuClient:Destroy()
		return
	end

	if ReplicatedStorage:FindFirstChild(MATTER_DEBUGGER_REMOTE_NAME) == nil then
		return
	end

	local matterDebugMenuClient = MatterDebugMenuClient :: any
	if matterDebugMenuClient.initialized == true or self._matterDebugInitScheduled == true then
		return
	end

	self._matterDebugInitScheduled = true
	task.defer(function()
		self._matterDebugInitScheduled = false
		if self._maid == nil then
			return
		end

		local ok, err = pcall(function()
			MatterDebugMenuClient:Init()
		end)
		if not ok then
			warn(`[CmdrBootstrapClient] Failed to initialize Matter debug menu: {err}`)
		end
	end)
end

function CmdrBootstrapClient.Init(self: any, serviceBag: any)
	assert(self._serviceBag == nil, "Already initialized")
	self._serviceBag = serviceBag
	self._maid = Maid.new() :: MaidClass
	self._started = false
	self._matterDebugInitScheduled = false
	self._cmdrClient = nil
	self._cmdrTypesRegistered = false
	self._pendingCmdrRetry = false
end

function CmdrBootstrapClient.Start(self: any)
	if self._started then
		return
	end
	self._started = true
	local runtimeMaid = assert(self._maid, "Not initialized")

	runtimeMaid:GiveTask(localPlayer:GetAttributeChangedSignal(CmdrUtils.CMDR_ENABLED_ATTRIBUTE):Connect(function()
		self:ApplyCmdrAccess()
	end))
	runtimeMaid:GiveTask(
		localPlayer:GetAttributeChangedSignal(CmdrUtils.MATTER_DEBUG_MENU_ENABLED_ATTRIBUTE):Connect(function()
			applyMatterDebugMenuAccess(self)
		end)
	)
	runtimeMaid:GiveTask(localPlayer.ChildAdded:Connect(function(child)
		if child:IsA("PlayerGui") then
			self:ApplyCmdrAccess()
		end
	end))
	runtimeMaid:GiveTask(ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == "CmdrClient" then
			self:ApplyCmdrAccess()
		elseif child.Name == MATTER_DEBUGGER_REMOTE_NAME then
			applyMatterDebugMenuAccess(self)
		end
	end))
	runtimeMaid:GiveTask(StarterGui.ChildAdded:Connect(function(child)
		if child.Name == "Cmdr" then
			self:ApplyCmdrAccess()
		end
	end))

	task.defer(function()
		if self._maid ~= runtimeMaid then
			return
		end
		self:ApplyCmdrAccess()
		applyMatterDebugMenuAccess(self)
	end)
end

function CmdrBootstrapClient.Destroy(self: any)
	if self._cmdrClient ~= nil then
		self._cmdrClient:SetEnabled(false)
		self._cmdrClient:Hide()
	end
	MatterDebugMenuClient:Destroy()
	if self._maid ~= nil then
		self._maid:DoCleaning()
	end
	self._maid = nil
	self._serviceBag = nil
	self._started = false
	self._matterDebugInitScheduled = false
	self._cmdrClient = nil
	self._cmdrTypesRegistered = false
	self._pendingCmdrRetry = false
end
return CmdrBootstrapClient

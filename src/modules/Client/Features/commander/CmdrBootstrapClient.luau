--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local packageRoot = assert(gameRoot.Parent, "Missing AquariaBackup package root.")
local quentyPackages = assert(packageRoot.node_modules:FindFirstChild("@quenty"), "Missing @quenty packages.")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local CmdrUtils = require(gameRoot.Shared.Features.commander.CmdrUtils)
local Maid = require(quentyPackages.maid.Shared.Maid)
local MatterDebugMenuClient = require(gameRoot.Client.Features.commander.MatterDebugMenuClient)

type MaidClass = {
	GiveTask: (self: MaidClass, task: any) -> any,
	DoCleaning: (self: MaidClass) -> (),
}

local CmdrBootstrapClient = {}

local localPlayer = Players.LocalPlayer
local MATTER_DEBUGGER_REMOTE_NAME = "MatterDebuggerRemote"

local started = false
local maid = nil :: MaidClass?
local matterDebugInitScheduled = false
local cmdrClient = nil :: any
local pendingCmdrRetry = false

local function findValidStarterGuiCmdr(): ScreenGui?
	local cmdrGui = CmdrUtils.keepSingleValidCmdrGui(StarterGui)

	while cmdrGui ~= nil and not CmdrUtils.isValidCmdrGui(cmdrGui) do
		task.wait()
		cmdrGui = CmdrUtils.keepSingleValidCmdrGui(StarterGui)
	end

	return cmdrGui
end

local function preparePlayerGuiForCmdr(): ScreenGui?
	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	if playerGui == nil or not playerGui:IsA("PlayerGui") then
		return nil
	end

	return CmdrUtils.keepSingleValidCmdrGui(playerGui)
end

local function ensureCmdrClient(): any
	if cmdrClient ~= nil then
		return cmdrClient
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
		existingGui = CmdrUtils.keepSingleValidCmdrGui(playerGui)
	end

	if existingGui == nil then
		return nil
	end

	local cmdrClientModule = ReplicatedStorage:FindFirstChild("CmdrClient")
	if cmdrClientModule == nil or not cmdrClientModule:IsA("ModuleScript") then
		return nil
	end

	cmdrClient = (require :: any)(cmdrClientModule)
	cmdrClient:SetActivationUnlocksMouse(true)
	cmdrClient:SetActivationKeys({ Enum.KeyCode.F2 })
	cmdrClient:SetEnabled(false)
	return cmdrClient
end

local function scheduleCmdrRetry()
	if pendingCmdrRetry then
		return
	end

	pendingCmdrRetry = true
	task.delay(0.1, function()
		pendingCmdrRetry = false
		if maid == nil then
			return
		end

		local applyCmdrAccess = CmdrBootstrapClient.applyCmdrAccess
		if applyCmdrAccess ~= nil then
			applyCmdrAccess()
		end
	end)
end

function CmdrBootstrapClient.ApplyCmdrAccess()
	local cmdrEnabled = localPlayer:GetAttribute(CmdrUtils.CMDR_ENABLED_ATTRIBUTE) == true or RunService:IsStudio()
	if not cmdrEnabled then
		if cmdrClient ~= nil then
			cmdrClient:SetEnabled(false)
			cmdrClient:Hide()
		end
		return
	end

	local ensuredClient = ensureCmdrClient()
	if ensuredClient ~= nil then
		ensuredClient:SetEnabled(true)
	else
		scheduleCmdrRetry()
	end
end

local function applyMatterDebugMenuAccess()
	local matterDebugEnabled = localPlayer:GetAttribute(CmdrUtils.MATTER_DEBUG_MENU_ENABLED_ATTRIBUTE) == true
	if not matterDebugEnabled then
		matterDebugInitScheduled = false
		MatterDebugMenuClient:destroy()
		return
	end

	if ReplicatedStorage:FindFirstChild(MATTER_DEBUGGER_REMOTE_NAME) == nil then
		return
	end

	local matterDebugMenuClient = MatterDebugMenuClient :: any
	if matterDebugMenuClient.initialized == true or matterDebugInitScheduled == true then
		return
	end

	matterDebugInitScheduled = true
	task.defer(function()
		matterDebugInitScheduled = false
		if maid == nil then
			return
		end

		local ok, err = pcall(function()
			MatterDebugMenuClient:init()
		end)
		if not ok then
			warn(`[CmdrBootstrapClient] Failed to initialize Matter debug menu: {err}`)
		end
	end)
end

function CmdrBootstrapClient.Start(_serviceBag: any)
	if started then
		return
	end
	started = true
	local runtimeMaid = Maid.new() :: MaidClass
	maid = runtimeMaid

	runtimeMaid:GiveTask(localPlayer:GetAttributeChangedSignal(CmdrUtils.CMDR_ENABLED_ATTRIBUTE):Connect(function()
		CmdrBootstrapClient.ApplyCmdrAccess()
	end))
	runtimeMaid:GiveTask(
		localPlayer:GetAttributeChangedSignal(CmdrUtils.MATTER_DEBUG_MENU_ENABLED_ATTRIBUTE):Connect(function()
			applyMatterDebugMenuAccess()
		end)
	)
	runtimeMaid:GiveTask(localPlayer.ChildAdded:Connect(function(child)
		if child:IsA("PlayerGui") then
			CmdrBootstrapClient.ApplyCmdrAccess()
		end
	end))
	runtimeMaid:GiveTask(ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == "CmdrClient" then
			CmdrBootstrapClient.ApplyCmdrAccess()
		elseif child.Name == MATTER_DEBUGGER_REMOTE_NAME then
			applyMatterDebugMenuAccess()
		end
	end))
	runtimeMaid:GiveTask(StarterGui.ChildAdded:Connect(function(child)
		if child.Name == "Cmdr" then
			CmdrBootstrapClient.ApplyCmdrAccess()
		end
	end))

	task.defer(function()
		CmdrBootstrapClient.ApplyCmdrAccess()
		applyMatterDebugMenuAccess()
	end)
end

CmdrBootstrapClient.applyCmdrAccess = CmdrBootstrapClient.ApplyCmdrAccess
CmdrBootstrapClient.start = CmdrBootstrapClient.Start

return CmdrBootstrapClient

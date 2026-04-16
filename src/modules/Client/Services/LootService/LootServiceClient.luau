--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local LootServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.LootService.LootServiceUtils)

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local LootServiceClient = {}

function LootServiceClient.ApplyState(self: LootServiceClient, _payloadRaw: any) end

function LootServiceClient.RequestSync(self: LootServiceClient)
	self.networker:fire(LootServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function LootServiceClient.RequestDropFromSlot(
	self: LootServiceClient,
	slotIndexRaw: any,
	amountRaw: any,
	throwDirectionRaw: any
)
	self.networker:fire(LootServiceUtils.NETWORK_METHOD_REQUEST_DROP_SLOT, slotIndexRaw, amountRaw, throwDirectionRaw)
end

function LootServiceClient.RequestDropSelectedSlot(self: LootServiceClient, amountRaw: any, throwDirectionRaw: any)
	self.networker:fire(LootServiceUtils.NETWORK_METHOD_REQUEST_DROP_SELECTED, amountRaw, throwDirectionRaw)
end

function LootServiceClient.ResolveDropAmount(self: LootServiceClient, amountRaw: any, fallbackAmountRaw: any?): number
	return LootServiceUtils.resolveDropAmount(amountRaw, fallbackAmountRaw)
end

function LootServiceClient.Init(self: LootServiceClient)
	self.networker = Networker.client.new("LootService", self)
	self.janitor = Janitor.new()
	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self:requestSync()
end

function LootServiceClient.Destroy(self: LootServiceClient)
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
end

LootServiceClient.applyState = LootServiceClient.ApplyState
LootServiceClient.requestSync = LootServiceClient.RequestSync
LootServiceClient.requestDropFromSlot = LootServiceClient.RequestDropFromSlot
LootServiceClient.requestDropSelectedSlot = LootServiceClient.RequestDropSelectedSlot
LootServiceClient.resolveDropAmount = LootServiceClient.ResolveDropAmount
LootServiceClient.init = LootServiceClient.Init
LootServiceClient.destroy = LootServiceClient.Destroy

type LootServiceClient = typeof(LootServiceClient) & {
	networker: Networker.Client,
	janitor: JanitorClass,
}

return LootServiceClient :: LootServiceClient

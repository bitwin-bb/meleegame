--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local LootServiceUtils = require(ReplicatedStorage.Shared.Services.LootService.LootServiceUtils)

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local LootServiceClient = {}

function LootServiceClient.applyState(self: LootServiceClient, _payloadRaw: any) end

function LootServiceClient.requestSync(self: LootServiceClient)
	self.networker:fire(LootServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function LootServiceClient.requestDropFromSlot(
	self: LootServiceClient,
	slotIndexRaw: any,
	amountRaw: any,
	throwDirectionRaw: any
)
	self.networker:fire(LootServiceUtils.NETWORK_METHOD_REQUEST_DROP_SLOT, slotIndexRaw, amountRaw, throwDirectionRaw)
end

function LootServiceClient.requestDropSelectedSlot(self: LootServiceClient, amountRaw: any, throwDirectionRaw: any)
	self.networker:fire(LootServiceUtils.NETWORK_METHOD_REQUEST_DROP_SELECTED, amountRaw, throwDirectionRaw)
end

function LootServiceClient.resolveDropAmount(self: LootServiceClient, amountRaw: any, fallbackAmountRaw: any?): number
	return LootServiceUtils.resolveDropAmount(amountRaw, fallbackAmountRaw)
end

function LootServiceClient.init(self: LootServiceClient)
	self.networker = Networker.client.new("LootService", self)
	self.janitor = Janitor.new()
	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self:requestSync()
end

function LootServiceClient.destroy(self: LootServiceClient)
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
end

type LootServiceClient = typeof(LootServiceClient) & {
	networker: Networker.Client,
	janitor: JanitorClass,
}

return LootServiceClient :: LootServiceClient

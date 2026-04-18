--!strict

local ModelBinder = require(script:FindFirstAncestor("game").Shared.Binders.ModelBinder)

local UseBinder = {}
UseBinder.__index = UseBinder
setmetatable(UseBinder, ModelBinder)

local inventoryServiceClient = nil

local function getInventoryServiceClient()
	if inventoryServiceClient == nil then
		inventoryServiceClient =
			require(script:FindFirstAncestor("game").Client.Services.InventoryService.InventoryServiceClient)
	end
	return inventoryServiceClient
end

local function resolveStringAttribute(instance: Instance, attributeName: string, fallback: string): string
	local value = instance:GetAttribute(attributeName)
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return fallback
end

local function resolveNumberAttribute(instance: Instance, attributeName: string, fallback: number): number
	local value = instance:GetAttribute(attributeName)
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end
	return value
end

function UseBinder.new(instance: Instance, context: any)
	local self = ModelBinder.new(instance, context, UseBinder)
	self.adornee = ModelBinder.resolveAdornee(instance)
	self.rootPart = ModelBinder.resolveRootPart(instance)
	self.highlight = self:createHighlight()
	self.prompt = self:createPrompt()

	self:refresh()
	if self.prompt ~= nil then
		self:Connect(self.prompt.PromptShown, function()
			self:setFocused(true)
		end)
		self:Connect(self.prompt.PromptHidden, function()
			self:setFocused(false)
		end)
		self:Connect(self.prompt.Triggered, function()
			self:onTriggered()
		end)
	end

	self:ObserveAttribute("UseActionText", function()
		self:refresh()
	end)
	self:ObserveAttribute("UseObjectText", function()
		self:refresh()
	end)
	self:ObserveAttribute("UseMaxDistance", function()
		self:refresh()
	end)
	self:ObserveAttribute("UseEnabled", function()
		self:refresh()
	end)

	return self
end

function UseBinder.createHighlight(self: any): Highlight?
	if self.adornee == nil then
		return nil
	end

	local existing = self.instance:FindFirstChild("UseHighlight")
	if existing ~= nil and existing:IsA("Highlight") then
		existing.Adornee = self.adornee
		return existing
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "UseHighlight"
	highlight.Adornee = self.adornee
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = Color3.fromRGB(255, 232, 176)
	highlight.FillTransparency = 0.82
	highlight.OutlineColor = Color3.fromRGB(255, 210, 98)
	highlight.OutlineTransparency = 0.15
	highlight.Enabled = false
	highlight.Parent = self.instance
	self:AddCleanup(function()
		if highlight.Parent ~= nil then
			highlight:Destroy()
		end
	end)
	return highlight
end

function UseBinder.createPrompt(self: any): ProximityPrompt?
	if self.rootPart == nil then
		return nil
	end

	local existing = self.rootPart:FindFirstChild("UsePrompt")
	if existing ~= nil and existing:IsA("ProximityPrompt") then
		return existing
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "UsePrompt"
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = self.rootPart
	self:AddCleanup(function()
		if prompt.Parent ~= nil then
			prompt:Destroy()
		end
	end)
	return prompt
end

function UseBinder.refresh(self: any)
	local enabled = self.instance:GetAttribute("UseEnabled") ~= false
	local actionText = resolveStringAttribute(self.instance, "UseActionText", "Use")
	local objectText = resolveStringAttribute(self.instance, "UseObjectText", self.instance.Name)
	local maxDistance = resolveNumberAttribute(self.instance, "UseMaxDistance", 12)

	self.instance:SetAttribute("UseTagged", true)
	self.instance:SetAttribute("UseFocused", false)

	if self.prompt ~= nil then
		self.prompt.Enabled = enabled
		self.prompt.ActionText = actionText
		self.prompt.ObjectText = objectText
		self.prompt.MaxActivationDistance = maxDistance
	end
	if self.highlight ~= nil then
		self.highlight.Enabled = false
	end
end

function UseBinder.setFocused(self: any, focused: boolean)
	if self.highlight ~= nil then
		self.highlight.Enabled = focused
	end
	self.instance:SetAttribute("UseFocused", focused)
end

function UseBinder.onTriggered(self: any)
	local remoteName = self.instance:GetAttribute("UseRemoteName")
	if typeof(remoteName) == "string" and remoteName ~= "" then
		local remote = self.instance:FindFirstChild(remoteName, true)
		if remote ~= nil and remote:IsA("RemoteEvent") then
			remote:FireServer(self.instance)
			return
		end
	end

	local defaultRemote = self.instance:FindFirstChild("UseRemoteEvent", true)
	if defaultRemote ~= nil and defaultRemote:IsA("RemoteEvent") then
		defaultRemote:FireServer(self.instance)
		return
	end

	local route = self.instance:GetAttribute("UseRoute")
	if route == "UseSelectedSlot" or route == "SelectedSlot" then
		getInventoryServiceClient():useSelectedSlot(1)
		return
	end
	if route == "PlaceSelectedDeployable" then
		getInventoryServiceClient():requestPlaceSelectedDeployable()
	end
end

function UseBinder.Cleanup(self: any)
	self:setFocused(false)
end

return UseBinder

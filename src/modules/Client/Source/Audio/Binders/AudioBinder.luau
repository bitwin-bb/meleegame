local require = require(script.Parent.loader).load(script)

local ModelBinder = require("ModelBinder")

local AudioBinder = {}
AudioBinder.__index = AudioBinder
setmetatable(AudioBinder, ModelBinder)

local function getStringAttribute(instance: Instance, attributeNames: { string }): string?
	for _, attributeName in attributeNames do
		local value = instance:GetAttribute(attributeName)
		if typeof(value) == "string" and value ~= "" then
			return value
		end
	end
	return nil
end

local function getNumberAttribute(instance: Instance, attributeName: string, fallback: number): number
	local value = instance:GetAttribute(attributeName)
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end
	return value
end

function AudioBinder.new(instance: Instance, context: ModelBinder.BinderContext)
	local self = ModelBinder.new(instance, context, AudioBinder)
	self.audioServiceClient =
		assert(self:GetDependencies().AudioServiceClient, "AudioServiceClient dependency is unavailable")
	self.rootPart = self:GetRootPart()
	self.playingSound = nil :: Sound?
	self.existingSound = instance:FindFirstChildWhichIsA("Sound", true)
	self.channel = `AudioBinder_{(instance :: any):GetDebugId(0)}`

	self:Refresh()
	self:ObserveAttribute("AudioEnabled", function()
		self:Refresh()
	end)
	self:ObserveAttribute("AudioSoundId", function()
		self:Refresh()
	end)
	self:ObserveAttribute("AmbientSoundId", function()
		self:Refresh()
	end)
	self:ObserveAttribute("AudioVolume", function()
		self:Refresh()
	end)

	return self
end

function AudioBinder.Refresh(self: any)
	local enabled = self.instance:GetAttribute("AudioEnabled") ~= false
	local soundId = getStringAttribute(self.instance, { "AudioSoundId", "AmbientSoundId", "SoundId" })
	local volume = getNumberAttribute(self.instance, "AudioVolume", 0.65)
	local maxDistance = getNumberAttribute(self.instance, "AudioMaxDistance", 55)
	local emitterSize = getNumberAttribute(self.instance, "AudioEmitterSize", 8)
	local looped = self.instance:GetAttribute("AudioLooped") ~= false

	self.instance:SetAttribute("AudioTagged", true)

	if self.existingSound ~= nil then
		self.existingSound.Volume = volume
		self.existingSound.RollOffMaxDistance = maxDistance
		self.existingSound.Looped = looped
		if enabled then
			if not self.existingSound.IsPlaying then
				self.existingSound:Play()
			end
		else
			self.existingSound:Stop()
		end
		return
	end

	if self.playingSound ~= nil then
		self.playingSound:Destroy()
		self.playingSound = nil
	end

	if not enabled or soundId == nil then
		return
	end

	local parent = if self.rootPart ~= nil
		then self.rootPart
		else if self.instance:IsA("BasePart") then self.instance else nil
	if parent == nil then
		return
	end

	self.playingSound = self.audioServiceClient:PlaySound(soundId, {
		parent = parent,
		channel = self.channel,
		looped = looped,
		autoDestroy = false,
		volume = volume,
		rollOffMaxDistance = maxDistance,
		emitterSize = emitterSize,
	})
end

function AudioBinder.Cleanup(self: any)
	if self.playingSound ~= nil then
		self.playingSound:Destroy()
		self.playingSound = nil
	end
	if self.existingSound ~= nil and self.instance:GetAttribute("AudioEnabled") == false then
		self.existingSound:Stop()
	end
end

return AudioBinder

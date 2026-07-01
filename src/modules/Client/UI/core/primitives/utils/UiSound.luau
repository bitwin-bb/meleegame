
local require = require(script.Parent.loader).load(script)

local AudioRegistry = require("Audio")
local AudioServiceUtils = require("AudioServiceUtils")

local UI_AUDIO = (AudioRegistry :: any).UI or ({} :: any)

local UiSound = {} :: any
local audioServiceClient = nil :: any?

local function getAudioServiceClient(): any
	if audioServiceClient == nil then
		audioServiceClient = require("AudioServiceClient")
	end
	return audioServiceClient
end

UiSound.hover = AudioServiceUtils.NormalizeSoundAssetId(UI_AUDIO.Hover)
UiSound.press = AudioServiceUtils.NormalizeSoundAssetId(UI_AUDIO.Press or UI_AUDIO.Click)
UiSound.click = AudioServiceUtils.NormalizeSoundAssetId(UI_AUDIO.Click or UI_AUDIO.Press)
UiSound.trash = AudioServiceUtils.NormalizeSoundAssetId(UI_AUDIO.Trash or UI_AUDIO.Drop)
UiSound.trashCanOpen = AudioServiceUtils.NormalizeSoundAssetId(UI_AUDIO.TrashCanOpen)
UiSound.trashCanClose = AudioServiceUtils.NormalizeSoundAssetId(UI_AUDIO.TrashCanClose)
UiSound.itemPutDown = AudioServiceUtils.NormalizeSoundAssetId(UI_AUDIO.ItemPutDown)
UiSound.craft = AudioServiceUtils.NormalizeSoundAssetId(UI_AUDIO.Craft)
UiSound.drag = AudioServiceUtils.NormalizeSoundAssetId(UI_AUDIO.Drag)

function UiSound.play(soundAssetId: string?)
	local AudioServiceClient = getAudioServiceClient()
	if AudioServiceClient.categoryGroups == nil then
		return
	end

	if soundAssetId == nil then
		return
	end

	AudioServiceClient:PlayUi(soundAssetId, {
		replaceChannel = false,
	})
end

function UiSound.playHover()
	UiSound.play(UiSound.hover)
end

function UiSound.playPress()
	UiSound.play(UiSound.press)
end

function UiSound.playTrash()
	UiSound.play(UiSound.trash)
end

function UiSound.playCraft()
	UiSound.play(UiSound.craft)
end

function UiSound.playDrag()
	UiSound.play(UiSound.drag)
end

return UiSound

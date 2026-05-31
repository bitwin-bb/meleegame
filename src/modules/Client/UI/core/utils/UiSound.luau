--!strict
local AudioRegistry = require(script:FindFirstAncestor("game").Shared.Features.item.modules.Audio)
local AudioServiceClient = require(script:FindFirstAncestor("game").Client.Features.audio.AudioServiceClient)
local AudioServiceUtils = require(script:FindFirstAncestor("game").Client.Features.audio.AudioServiceUtils)

local UI_AUDIO = (AudioRegistry :: any).UI or ({} :: any)

local UiSound = {} :: any

UiSound.hover = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.Hover)
UiSound.press = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.Press or UI_AUDIO.Click)
UiSound.click = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.Click or UI_AUDIO.Press)
UiSound.trash = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.Trash or UI_AUDIO.Drop)
UiSound.trashCanOpen = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.TrashCanOpen)
UiSound.trashCanClose = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.TrashCanClose)
UiSound.itemPutDown = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.ItemPutDown)
UiSound.craft = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.Craft)
UiSound.drag = AudioServiceUtils.normalizeSoundAssetId(UI_AUDIO.Drag)

function UiSound.play(soundAssetId: string?)
	if AudioServiceClient.categoryGroups == nil then
		return
	end

	if soundAssetId == nil then
		return
	end

	AudioServiceClient:playUi(soundAssetId, {
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

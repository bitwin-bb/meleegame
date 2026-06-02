--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local UiSound = require(gameRoot.Client.UI.core.utils.UiSound)
local useEvent = require(gameRoot.Client.UI.shared.useEvent)

export type UiSoundHook = {
	play: (soundAssetId: string?) -> (),
	playHover: () -> (),
	playPress: () -> (),
	playTrash: () -> (),
	playCraft: () -> (),
	playDrag: () -> (),
}

local function useUiSound(): UiSoundHook
	local play = useEvent(function(soundAssetId: string?)
		UiSound.play(soundAssetId)
	end) :: (string?) -> ()
	local playHover = useEvent(function()
		UiSound.playHover()
	end) :: () -> ()
	local playPress = useEvent(function()
		UiSound.playPress()
	end) :: () -> ()
	local playTrash = useEvent(function()
		UiSound.playTrash()
	end) :: () -> ()
	local playCraft = useEvent(function()
		UiSound.playCraft()
	end) :: () -> ()
	local playDrag = useEvent(function()
		UiSound.playDrag()
	end) :: () -> ()

	return {
		play = play,
		playHover = playHover,
		playPress = playPress,
		playTrash = playTrash,
		playCraft = playCraft,
		playDrag = playDrag,
	}
end

return useUiSound

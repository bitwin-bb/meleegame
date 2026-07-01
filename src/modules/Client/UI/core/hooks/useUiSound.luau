
local require = require(script.Parent.loader).load(script)

local UiSound = require("UiSound")
local useEvent = require("useEventShared")

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

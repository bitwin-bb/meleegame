local SideView = require(script.SideView)
local FirstPerson = require(script.FirstPerson)
local Isometric = require(script.Isometric)

local Camera = {}
Camera.__index = Camera

type cameraProps = {
    camera: Camera,
    moveVect: (Vector3) -> Vector3,
    rotateVect: (Vector3) -> Vector3,
    fieldView: number?,
}

export type Camera = typeof(setmetatable(
	{} :: {
        camera: cameraProps,
        sideView: SideView.SideView,
		firstPerson: FirstPerson.FirstPerson,
		isometric: Isometric.Isometric,
	},
	Camera
))

function Camera.new(self: Camera): ()
	return setmetatable({
		SideView = SideView.new(),
		FirstPerson = FirstPerson.new(),
		Isometric = Isometric.new(),
	}, Camera)
end

function Camera.init(self: Camera) end

--!strict

local Workspace = game:GetService("Workspace")

local Nevermore = require(script:FindFirstAncestor("game").Shared.StateMachine.Nevermore)
local Maid = Nevermore.Get("Maid")
local Signal = Nevermore.Get("Signal")

local CameraHandler = {}
CameraHandler.__index = CameraHandler

export type CameraHandler = typeof(setmetatable(
	{} :: {
		maid: any,
		Changed: any,
		camera: Camera?,
		target: Instance?,
	},
	CameraHandler
))

function CameraHandler.new(cameraRaw: any?): CameraHandler
	return setmetatable({
		maid = Maid.new(),
		Changed = Signal.new(),
		camera = if typeof(cameraRaw) == "Instance" and cameraRaw:IsA("Camera")
			then cameraRaw
			else Workspace.CurrentCamera,
		target = nil,
	}, CameraHandler)
end

function CameraHandler.SetTarget(self: CameraHandler, targetRaw: any?)
	self.target = if typeof(targetRaw) == "Instance" then targetRaw else nil
	self.Changed:Fire("Target", self.target)
end

function CameraHandler.GetCamera(self: CameraHandler): Camera?
	return self.camera
end

function CameraHandler.SetCameraType(self: CameraHandler, cameraType: Enum.CameraType)
	if self.camera ~= nil then
		self.camera.CameraType = cameraType
		self.Changed:Fire("CameraType", cameraType)
	end
end

function CameraHandler.Destroy(self: CameraHandler)
	self.maid:DoCleaning()
	self.Changed:Destroy()
	self.camera = nil
	self.target = nil
end

CameraHandler.setTarget = CameraHandler.SetTarget
CameraHandler.getCamera = CameraHandler.GetCamera
CameraHandler.setCameraType = CameraHandler.SetCameraType
CameraHandler.destroy = CameraHandler.Destroy

return CameraHandler

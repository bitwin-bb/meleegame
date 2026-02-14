local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ui = require(ReplicatedStorage.UI)
local SlimeServiceClient = require(ReplicatedStorage.Shared.Services.SlimeService.SlimeServiceClient)

SlimeServiceClient:init()

ui()

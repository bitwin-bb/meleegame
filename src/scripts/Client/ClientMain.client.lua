local ReplicatedStorage = game:GetService("ReplicatedStorage")

local loader = ReplicatedStorage:WaitForChild("AquariaBackup"):WaitForChild("loader")
local require = require(loader).bootstrapGame(loader.Parent)

local serviceBag = require("ServiceBag").new()

serviceBag:GetService(require("AquariaBackupServiceClient"))
serviceBag:Init()
serviceBag:Start()

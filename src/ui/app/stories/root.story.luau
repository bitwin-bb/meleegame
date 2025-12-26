return function(target) 
   local frame = Instance.new("Frame")

   frame.Size = UDim2.fromScale(0.1, 0.1)
   frame.Position = UDim2.fromScale(0.45, 0.45)
   frame.Parent = target

   return function()
      frame:Destroy()
   end
end
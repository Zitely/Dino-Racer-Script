local url = "https://raw.githubusercontent.com/Zitely/Dino-Racer-Script/main/RideADino.fixed.lua"
local ok, err = pcall(function()
    local source = game:HttpGet(url)
    local run, compileError = loadstring(source)
    if not run then error(compileError, 0) end
    run()
end)
if not ok then warn("Ride a Dino failed to load: " .. tostring(err)) end

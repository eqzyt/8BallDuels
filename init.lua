-- src/init.lua (ou atualize o seu init.lua no GitHub)
if _G.__CueBotKill then pcall(_G.__CueBotKill) end

local BASE_URL = "https://raw.githubusercontent.com/eqzyt/8BallDuels/bot-dsc/src/"

local function loadModule(name)
    local src = game:HttpGet(BASE_URL .. name .. ".lua")
    local fn, err = loadstring(src, name)
    assert(fn, "Erro ao carregar modulo " .. name .. ": " .. tostring(err))
    return fn()
end

local State      = loadModule("state")
local Match      = loadModule("match")(State)
local Planner    = loadModule("planner")(State, Match)
local Overlay    = loadModule("overlay")(State)
local BotActions = loadModule("bot")(State, Match, Overlay)
loadModule("ui")(State, Match)

local RunService          = State.RunService
local UserInputService    = State.UserInputService
local PoolInputController = State.PoolInputController
local Config              = State.Config
local Bot                 = State.Bot
local Connections         = State.Connections
local waitForReaction     = State.waitForReaction

local PoolRemotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("Pool")

task.spawn(function()
    while Bot.Alive do
        task.wait(1)
        pcall(function()
            if Config.Enabled then
                local mc = Match.findMC()
                if not mc then
                    firesignal(PoolRemotes.OnClientEvent, "Queued", "NineBall_Spain", 0, 550000, 206)
                    PoolRemotes:FireServer("LocalMatch", true)
                end
            end
        end)
    end
end)

Connections[#Connections + 1] = PoolRemotes.OnClientEvent:Connect(function(action, data)
    if action == "CardPicked" then
        pcall(function()
            firesignal(PoolRemotes.OnClientEvent, "CardPicked", {
                Others = {
                    { Coins = math.random(5000, 7000) },
                    { Coins = math.random(5000, 7000) }
                },
                Tier = "Wood",
                Id = tostring(math.random(100, 200)),
                First = false,
                Reward = { Coins = math.random(5000, 7000) }
            })
        end)
    end
end)

local function runPendingTask(callback)
    task.spawn(function()
        local ok, err = xpcall(callback, function(e)
            return tostring(e)
        end)
        Bot.Pending = false
        if not ok then
            Bot.Status = "Task error"
            warn("[CueBot] Auto Play task failed: " .. tostring(err))
        end
    end)
end

local nextMatchScan = 0
Connections[#Connections + 1] = RunService.Heartbeat:Connect(function(dt)
    if not Bot.Alive then return end
    if not Config.Enabled then
        Bot.Status = "Disabled"
        return
    end
    if Bot.Cooldown > 0 then
        Bot.Cooldown -= dt
        return
    end

    local md = Bot.MC and Match.matchData(Bot.MC)
    local oldInputState = Bot.MC and Bot.MC.Input and Bot.MC.Input.State
    if not md or not md.Active or md.Phase ~= "Playing" or oldInputState == "GameOver" then
        if os.clock() >= nextMatchScan then
            nextMatchScan = os.clock() + 0.5
            local freshMC = Match.findMC()
            Bot.MC = freshMC
            md = freshMC and Match.matchData(freshMC) or nil
        else
            Bot.MC = nil
            md = nil
        end
    end

    local mc = Bot.MC
    if not mc or not md or not md.Active or md.Phase ~= "Playing" then
        Bot.MC = nil
        Bot.Pending = false
        Bot.Status = "No Match"
        return
    end
    if not Match.myTurn(mc) then
        Bot.Status = "Opponent's Turn"; Bot.Pending = false; return
    end

    if Bot.Pending then return end
    local inputState = mc.Input and mc.Input.State or ""
    if inputState == "BallInHand" then
        Bot.Status = "Placing Ball..."
        Bot.Pending = true
        runPendingTask(function()
            task.wait(0.2)
            if not Bot.Alive or not Config.Enabled then Bot.Pending = false; return end
            local pos = Planner.planPlacement(mc)
            BotActions.placeBall(mc, pos)
            task.wait(0.2)
            if mc.Input and mc.Input.State == "BallInHand" then
                pcall(function() PoolInputController.SetState(mc.Input, "Aiming") end)
            end
            waitForReaction()
            if not Bot.Alive or not Config.Enabled or not Match.myTurn(mc) then
                Bot.Pending = false; return
            end
            Bot.Status = "Shooting"
            local shot = Planner.planShot(mc)
            if shot then
                BotActions.fireShot(mc, shot)
                Bot.Cooldown = 1.5
            end
            Bot.Pending = false
        end)
        return
    end
    if inputState == "Aiming" or inputState == "Charging" then
        Bot.Status = "Planning..."
        Bot.Pending = true
        runPendingTask(function()
            waitForReaction()
            if not Bot.Alive or not Config.Enabled or not Match.myTurn(mc) then
                Bot.Pending = false; return
            end
            Bot.Status = "Shooting"
            local shot = Planner.planShot(mc)
            if shot then
                BotActions.fireShot(mc, shot)
                Bot.Cooldown = 1.5
            else
                Bot.Status = "No shot found"
                Bot.Cooldown = 0.5
            end
            Bot.Pending = false
        end)
        return
    end
    if inputState == "Simulating" then
        Bot.Status = "Simulating..."
    elseif inputState == "GameOver" then
        Bot.Status = "Game Over"
    else
        Bot.Status = "Waiting (" .. inputState .. ")"
    end
end)

Connections[#Connections + 1] = UserInputService.InputBegan:Connect(function(inp, gpe)
    if gpe then return end
    if inp.KeyCode == Enum.KeyCode.F6 then
        Config.Enabled = not Config.Enabled
    end
end)

_G.__CueBotKill = function()
    Bot.Alive = false
    Config.Enabled = false
    Config.ActiveLines = false
    if _G.__CueBotSetActiveLines then
        _G.__CueBotSetActiveLines(false)
        _G.__CueBotSetActiveLines = nil
    end
    for _, conn in Connections do
        pcall(function() conn:Disconnect() end)
    end
end

pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "CueBot Pro",
        Text  = "Loaded successfully! Press F6 to toggle.",
        Duration = 4
    })
end)

-- src/ui.lua
return function(State, Match)
    local ReplicatedStorage = State.ReplicatedStorage
    local RunService        = State.RunService
    local Config            = State.Config
    local Bot               = State.Bot
    local Connections       = State.Connections

    local function loadImGuiPackage()
        local packages = ReplicatedStorage:FindFirstChild("Packages")
        local packageModule = packages and packages:FindFirstChild("ImGui")
            or ReplicatedStorage:FindFirstChild("ImGui")
        if packageModule and packageModule:IsA("ModuleScript") then
            return require(packageModule)
        end

        assert(type(loadstring) == "function", "Dear ImGui is missing; install 4dbug/imgui-luau or enable loadstring")
        local source = game:HttpGet("https://github.com/4DBug/imgui-luau/releases/latest/download/ImGui.luau")
        local chunk, compileError = loadstring(source, "DearImGui")
        assert(chunk, "Dear ImGui bundle failed to compile: " .. tostring(compileError))
        return chunk()
    end

    local ImGuiPackage = loadImGuiPackage()
    local ImGui = ImGuiPackage.ImGui
    local ImGui_ImplRoblox = ImGuiPackage.ImGui_ImplRoblox
    ImGui.CreateContext()
    ImGui_ImplRoblox.Init()

    local uiOpen = true
    local powerModes = {"Auto", "Soft", "Medium", "Hard"}
    local aimStyles  = {"Smooth", "Stepped", "Instant"}

    local function drawWindow()
        local isOpen, visible = ImGui.Begin("MENU DO BOMBOLEX EMPODERADO", uiOpen)
        uiOpen = isOpen
        if visible then
            ImGui.Text("MENU GULOSEX")
            ImGui.Separator()
            if ImGui.BeginTabBar("CueBotTabs") then
                if ImGui.BeginTabItem("Control") then
                    local _, enabled = ImGui.Checkbox("TACAR NUTELEX NELES", Config.Enabled)
                    Config.Enabled = enabled
                    local delay = ImGui.SliderFloat("Reaction delay", Config.ShotDelay, 0.3, 3.0, "%.1f s")
                    Config.ShotDelay = delay
                    local aimDur = ImGui.SliderFloat("Aim duration", Config.AimDuration, 0.2, 1.5, "%.2f s")
                    Config.AimDuration = aimDur
                    local styleIndex = (table.find(aimStyles, Config.AimStyle) or 1) - 1
                    local newStyle = ImGui.Combo("Aim style", styleIndex, aimStyles)
                    Config.AimStyle = aimStyles[newStyle + 1] or Config.AimStyle
                    local modeIndex = (table.find(powerModes, Config.PowerMode) or 1) - 1
                    local newMode = ImGui.Combo("Shot power", modeIndex, powerModes)
                    Config.PowerMode = powerModes[newMode + 1] or Config.PowerMode
                    local _, humanize = ImGui.Checkbox("Humanized cue movement", Config.Humanize)
                    Config.Humanize = humanize
                    local _, activeLines = ImGui.Checkbox("Active lines", Config.ActiveLines)
                    if activeLines ~= Config.ActiveLines then
                        Config.ActiveLines = activeLines
                        if _G.__CueBotSetActiveLines then
                            _G.__CueBotSetActiveLines(activeLines)
                        end
                    end
                    local _, bankFallback = ImGui.Checkbox("Bank-shot emergency fallback", Config.BankShotFallback)
                    Config.BankShotFallback = bankFallback
                    ImGui.Text("Direct pots evaluated first; one-rail banks as fallback.")
                    ImGui.EndTabItem()
                end
                if ImGui.BeginTabItem("Match") then
                    local mc = Bot.MC
                    local md = mc and Match.matchData(mc)
                    ImGui.Text("State: %s", Bot.Status)
                    ImGui.Text("Match: %s", md and (mc.GameType or "8-Ball") or "None")
                    ImGui.Text("Turn: %s", mc and Match.myTurn(mc) and "Your turn" or "Opponent / waiting")
                    local group = mc and Match.myGroup(mc)
                    ImGui.Text("Group: %s", group or "Open table")
                    ImGui.EndTabItem()
                end
                if ImGui.BeginTabItem("Stats") then
                    ImGui.Text("Shots: %d", Bot.Stats.Shots)
                    ImGui.Text("Pots: %d", Bot.Stats.Pots)
                    local shot = Bot.LastShot
                    if shot then
                        ImGui.Separator()
                        ImGui.Text("Last target: %s", tostring(shot.Target or "—"))
                        ImGui.Text("Pocket: %s", tostring(shot.PocketId or "—"))
                        ImGui.Text("Power: %.2f", shot.Power or 0)
                        ImGui.Text("Plan score: %.1f", shot.Score or 0)
                    end
                    ImGui.EndTabItem()
                end
                ImGui.EndTabBar()
            end
        end
        ImGui.End()
    end

    Connections[#Connections + 1] = RunService.PreSimulation:Connect(function()
        if not Bot.Alive then return end
        ImGui_ImplRoblox.NewFrame()
        ImGui.NewFrame()
        drawWindow()
        ImGui.Render()
        ImGui_ImplRoblox.RenderDrawData(ImGui.GetDrawData())
    end)
end
-- src/bot.lua
return function(State, Match, Overlay)
    local RunService     = State.RunService
    local PoolRules      = State.PoolRules
    local PoolAimOverlay = State.PoolAimOverlay
    local RemoteEnums    = State.RemoteEnums
    local RemoteSignals  = State.RemoteSignals
    local Config         = State.Config
    local Bot            = State.Bot
    local Live           = State.Live
    local Randomizer     = State.Randomizer
    local CUEBALL        = State.CUEBALL

    local BotActions = {}

    local function applyLocalAimVisuals(mc, cuePos, dir, pullFraction)
        local input = mc.Input
        if type(input) == "table" then
            for _, key in {"AimDirection", "Direction", "AimVector", "Aim", "LookDirection"} do
                if input[key] ~= nil then
                    input[key] = dir
                end
            end
            if pullFraction ~= nil then
                for _, key in {"PullFraction", "Power", "Charge", "Pull"} do
                    if type(input[key]) == "number" then
                        input[key] = pullFraction
                    end
                end
            end
        end

        if Live.lastOverlaySelf and mc.Simulation then
            pcall(function()
                local cast = Overlay.oldCastCueBall(mc.Simulation, dir)
                local firstHit = (cast and cast.Kind == "Ball") and cast.Other or nil
                local isLegal = firstHit ~= nil and PoolRules.IsLegalFirstContact(mc.Rules, mc.Simulation, firstHit)
                if Live.lastOverlaySelf.__CueBotSmoothAimDir then
                    Live.lastOverlaySelf.__CueBotSmoothAimDir = dir
                end
                PoolAimOverlay.Update(Live.lastOverlaySelf, cuePos, dir, cast, pullFraction or 0, 600, isLegal)
            end)
        end
    end

    local function readCurrentAim(mc, fallbackDir)
        local input = mc.Input
        if type(input) == "table" then
            for _, key in {"AimDirection", "Direction", "AimVector", "Aim", "LookDirection"} do
                local value = input[key]
                if typeof(value) == "Vector2" and value.Magnitude > 0.001 then
                    return value.Unit
                end
            end
        end
        if Live.lastAimDir and Live.lastAimDir.Magnitude > 0.001 then
            return Live.lastAimDir.Unit
        end
        return fallbackDir
    end

    local function easeOutCubic(t)
        return 1 - (1 - t) ^ 3
    end

    function BotActions.fireShot(mc, shot)
        if not shot then return false end
        local cb = mc.Simulation.Balls[CUEBALL]
        if not cb then return false end
        local cp   = cb.Position
        local call = nil
        if not shot.IsBreak and PoolRules.NeedsCall(mc.Rules, mc.Simulation) then
            call = shot.PocketId
        end

        local targetDirection = shot.Direction.Unit
        local spin = shot.Spin or Vector2.zero

        if Config.AimStyle == "Instant" or not Config.Humanize then
            applyLocalAimVisuals(mc, cp, targetDirection, shot.Power)
            pcall(function()
                RemoteSignals.FireServer(RemoteEnums.Pool, "Aim",
                    targetDirection.X, targetDirection.Y,
                    shot.Power,
                    spin.X, spin.Y,
                    cp.X, cp.Y,
                    false, true, call)
            end)
            task.wait(0.05)
        elseif Config.AimStyle == "Stepped" then
            local fromDirection = readCurrentAim(mc, targetDirection)
            local startAngle = math.atan2(fromDirection.Y, fromDirection.X)
            local targetAngle = math.atan2(targetDirection.Y, targetDirection.X)
            local angleDiff = (targetAngle - startAngle + math.pi) % (2 * math.pi) - math.pi
            local steps = math.clamp(math.floor(math.deg(math.abs(angleDiff)) / 15), 2, 6)

            for i = 1, steps do
                if not Bot.Alive or not Config.Enabled then return false end
                local alpha = i / steps
                local currentAngle = startAngle + angleDiff * alpha
                local dir = Vector2.new(math.cos(currentAngle), math.sin(currentAngle)).Unit

                applyLocalAimVisuals(mc, cp, dir, 0)
                pcall(function()
                    RemoteSignals.FireServer(RemoteEnums.Pool, "Aim",
                        dir.X, dir.Y,
                        shot.Power,
                        spin.X, spin.Y,
                        cp.X, cp.Y,
                        false, true, call)
                end)
                task.wait(0.04)
            end
        else
            local fromDirection = readCurrentAim(mc, targetDirection)
            local startAngle = math.atan2(fromDirection.Y, fromDirection.X)
            local targetAngle = math.atan2(targetDirection.Y, targetDirection.X)
            local angleDiff = (targetAngle - startAngle + math.pi) % (2 * math.pi) - math.pi

            if math.abs(angleDiff) < 0.05 then
                local offset = (Randomizer:NextNumber() > 0.5 and 1 or -1) * Randomizer:NextNumber(0.18, 0.35)
                startAngle = targetAngle - offset
                angleDiff = offset
            end

            local baseDuration = Config.AimDuration or 0.65
            local angleFactor = math.clamp(math.abs(angleDiff) / math.pi, 0.35, 1.25)
            local duration = math.clamp(baseDuration * angleFactor * Randomizer:NextNumber(0.9, 1.12), 0.28, 1.2)

            local startTime = os.clock()
            local lastNetworkSend = 0

            while true do
                if not Bot.Alive or not Config.Enabled or not Match.myTurn(mc) then return false end
                local now = os.clock()
                local t = math.clamp((now - startTime) / duration, 0, 1)
                local eased = easeOutCubic(t)

                local currentAngle = startAngle + angleDiff * eased
                local dir = Vector2.new(math.cos(currentAngle), math.sin(currentAngle)).Unit

                applyLocalAimVisuals(mc, cp, dir, 0)

                if now - lastNetworkSend >= 0.05 or t >= 1 then
                    lastNetworkSend = now
                    pcall(function()
                        RemoteSignals.FireServer(RemoteEnums.Pool, "Aim",
                            dir.X, dir.Y,
                            shot.Power,
                            spin.X, spin.Y,
                            cp.X, cp.Y,
                            false, true, call)
                    end)
                end

                if t >= 1 then break end
                RunService.Heartbeat:Wait()
            end

            local chargeDuration = math.clamp(0.18 + shot.Power * 0.22, 0.18, 0.42)
            local chargeStart = os.clock()
            while true do
                if not Bot.Alive or not Config.Enabled or not Match.myTurn(mc) then return false end
                local now = os.clock()
                local ct = math.clamp((now - chargeStart) / chargeDuration, 0, 1)
                local pull = shot.Power * easeOutCubic(ct)

                applyLocalAimVisuals(mc, cp, targetDirection, pull)

                if ct >= 1 then break end
                RunService.Heartbeat:Wait()
            end
        end

        task.wait(0.06)

        local ok = pcall(function()
            RemoteSignals.FireServer(RemoteEnums.Pool, "Shot",
                targetDirection.X, targetDirection.Y,
                shot.Power,
                spin.X, spin.Y,
                cp.X, cp.Y,
                call)
        end)

        if ok then
            Bot.Stats.Shots += 1
            if shot.OwnPots and shot.OwnPots > 0 then
                Bot.Stats.Pots += shot.OwnPots
            end
            Bot.LastShot = shot
        end
        return ok
    end

    function BotActions.placeBall(mc, pos)
        local cb = mc.Simulation.Balls[CUEBALL]
        if not cb then return end
        cb.Position = pos
        cb.Velocity = Vector2.zero
        cb.Pocketed = false
        cb.Sinking  = false
        pcall(function()
            RemoteSignals.FireServer(RemoteEnums.Pool, "Aim",
                0, 1, 0, 0, 0,
                pos.X, pos.Y,
                true, true, nil)
        end)
    end

    return BotActions
end
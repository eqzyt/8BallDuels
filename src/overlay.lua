-- src/overlay.lua
return function(State)
    local PoolConstants       = State.PoolConstants
    local PoolPhysics         = State.PoolPhysics
    local PoolStepper         = State.PoolStepper
    local PoolAI              = State.PoolAI
    local PoolAimOverlay      = State.PoolAimOverlay
    local PoolTableRenderer2D = State.PoolTableRenderer2D
    local Config              = State.Config
    local Live                = State.Live

    local Overlay = {}

    local oldCastCueBall = PoolPhysics.CastCueBall
    Overlay.oldCastCueBall = oldCastCueBall

    PoolPhysics.CastCueBall = function(sim, aimDir, ...)
        if Live.activeSim ~= sim then
            Live.activeSim = sim
            Live.forceResimulate = true
        end
        return oldCastCueBall(sim, aimDir, ...)
    end

    local oldPredictShot = PoolPhysics.PredictShot
    PoolPhysics.PredictShot = function(sim, aimDir, power, spin, ...)
        Live.activeSim = sim
        if typeof(power) == "number" and power > 0.01 then
            Live.currentPower = power
        end
        if typeof(spin) == "Vector2" then
            Live.currentSpin = spin
        end
        return oldPredictShot(sim, aimDir, power, spin, ...)
    end

    local oldShoot = PoolPhysics.Shoot
    local isSimulatingClone = false
    PoolPhysics.Shoot = function(sim, aimDir, power, spin, ...)
        local res = oldShoot(sim, aimDir, power, spin, ...)
        if not isSimulatingClone and sim == Live.activeSim then
            Live.forceResimulate = true
        end
        return res
    end

    local linePool = {}
    local markerPool = {}
    local activeRoot = nil
    local usedLines = 0
    local usedMarkers = 0

    local COLORS = {
        CuePre      = Color3.fromRGB(255, 255, 255),
        CuePost     = Color3.fromRGB(0, 230, 255),
        TargetRing  = Color3.fromRGB(255, 215, 0),
        PrimaryPath = Color3.fromRGB(255, 215, 0),
        ComboPath   = Color3.fromRGB(255, 125, 40),
        Pocketed    = Color3.fromRGB(60, 255, 110),
        Scratch     = Color3.fromRGB(255, 55, 55),
    }

    local function clearAllVisuals()
        for i = 1, usedLines do
            if linePool[i] then linePool[i].Visible = false end
        end
        for i = 1, usedMarkers do
            if markerPool[i] then markerPool[i].Visible = false end
        end
        usedLines = 0
        usedMarkers = 0
        Live.forceResimulate = true
    end

    _G.__CueBotSetActiveLines = function(enabled)
        Live.activeLinesEnabled = enabled == true
        Live.forceResimulate = true
        if not Live.activeLinesEnabled then
            clearAllVisuals()
        end
    end

    local function ensureRoot(root)
        if activeRoot ~= root then
            for _, line in linePool do line:Destroy() end
            for _, marker in markerPool do marker:Destroy() end
            table.clear(linePool)
            table.clear(markerPool)
            usedLines = 0
            usedMarkers = 0
            activeRoot = root
            Live.forceResimulate = true
        end
    end

    local function getLine(index, root)
        ensureRoot(root)
        local line = linePool[index]
        if not line then
            line = Instance.new("Frame")
            line.Name = "SimLine_" .. index
            line.AnchorPoint = Vector2.new(0.5, 0.5)
            line.BorderSizePixel = 0
            line.ZIndex = root.ZIndex + 30

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(1, 0)
            corner.Parent = line

            line.Parent = root
            linePool[index] = line
        end
        return line
    end

    local function getMarker(index, root, diameter, color, fillTrans, strokeThick, textLabel)
        ensureRoot(root)
        local marker = markerPool[index]
        if not marker then
            marker = Instance.new("Frame")
            marker.Name = "SimMarker_" .. index
            marker.AnchorPoint = Vector2.new(0.5, 0.5)
            marker.BorderSizePixel = 0
            marker.ZIndex = root.ZIndex + 34

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(1, 0)
            corner.Parent = marker

            local stroke = Instance.new("UIStroke")
            stroke.Name = "Stroke"
            stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            stroke.Parent = marker

            local label = Instance.new("TextLabel")
            label.Name = "Tag"
            label.Size = UDim2.fromScale(1, 1)
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.GothamBlack
            label.TextScaled = true
            label.ZIndex = marker.ZIndex + 1

            local labelStroke = Instance.new("UIStroke")
            labelStroke.Thickness = 1.2
            labelStroke.Color = Color3.fromRGB(15, 15, 15)
            labelStroke.Parent = label

            label.Parent = marker
            marker.Parent = root
            markerPool[index] = marker
        end

        local frameSize = PoolTableRenderer2D.GetFrameSize()
        marker.Size = UDim2.fromScale(diameter / frameSize.X, diameter / frameSize.Y)
        marker.BackgroundColor3 = color
        marker.BackgroundTransparency = fillTrans or 0.4

        local stroke = marker:FindFirstChild("Stroke")
        if stroke then
            stroke.Color = color
            stroke.Thickness = strokeThick or 2
            stroke.Transparency = 0.05
        end

        local label = marker:FindFirstChild("Tag")
        if label then
            label.Text = textLabel or ""
            label.TextColor3 = Color3.new(1, 1, 1)
            label.Visible = (textLabel ~= nil and textLabel ~= "")
        end

        return marker
    end

    local function drawLine(frame, p1, p2, thickness, color, transparency, zOffset, frameSize)
        local delta = p2 - p1
        local dist = delta.Magnitude
        if dist < 0.05 then
            frame.Visible = false
            return
        end

        local mid = (p1 + p2) * 0.5
        frame.Position = UDim2.fromScale(0.5 + mid.X / frameSize.X, 0.5 - mid.Y / frameSize.Y)
        frame.Size = UDim2.fromScale(dist / frameSize.X, thickness / frameSize.Y)
        frame.Rotation = math.deg(math.atan2(-delta.Y, delta.X))
        frame.BackgroundColor3 = color
        frame.BackgroundTransparency = transparency or 0.15
        if activeRoot and zOffset then
            frame.ZIndex = activeRoot.ZIndex + zOffset
        end
        frame.Visible = true
    end

    local function placeMarker(marker, pos, frameSize)
        marker.Position = UDim2.fromScale(0.5 + pos.X / frameSize.X, 0.5 - pos.Y / frameSize.Y)
        marker.Visible = true
    end

    local oldSetVisible = PoolAimOverlay.SetVisible
    PoolAimOverlay.SetVisible = function(self, visible, ...)
        if not visible then
            clearAllVisuals()
        else
            Live.forceResimulate = true
        end
        return oldSetVisible(self, visible, ...)
    end

    local oldShowHeldBall = PoolAimOverlay.ShowHeldBall
    PoolAimOverlay.ShowHeldBall = function(self, ...)
        clearAllVisuals()
        return oldShowHeldBall(self, ...)
    end

    local oldHideGuides = PoolAimOverlay.HideGuides
    PoolAimOverlay.HideGuides = function(self, ...)
        local res = oldHideGuides(self, ...)
        if not Live.activeLinesEnabled then
            clearAllVisuals()
            return res
        end

        local ballsMoving = Live.activeSim and not Live.activeSim.Settled
        local overlayHidden = not self.Root or not self.Root.Visible or (self.Halo and self.Halo.Visible)

        if ballsMoving or overlayHidden then
            clearAllVisuals()
        elseif Live.lastOverlaySelf == self and Live.lastAimDir.Magnitude > 0.0001 then
            Live.currentPower = 0.75
            Live.forceResimulate = true
            if self.AimLine then self.AimLine.Visible = true end
            if self.Ghost then self.Ghost.Visible = true end
            PoolAimOverlay.Update(self, Live.lastCuePos, Live.lastAimDir, oldCastCueBall(Live.activeSim, Live.lastAimDir), 0, 600, Live.lastLegal)
        end

        return res
    end

    local oldUpdate = PoolAimOverlay.Update
    local function smoothOverlayAim(self, aimDir)
        if not Config.Humanize or typeof(aimDir) ~= "Vector2" or aimDir.Magnitude < 0.0001 then
            self.__CueBotSmoothAimDir = nil
            self.__CueBotSmoothAimTime = os.clock()
            return aimDir
        end

        local target = aimDir.Unit
        local now = os.clock()
        local previous = self.__CueBotSmoothAimDir
        local previousTime = self.__CueBotSmoothAimTime or now
        local dt = math.clamp(now - previousTime, 0, 0.1)
        local smoothed = target

        if typeof(previous) == "Vector2" and previous.Magnitude > 0.0001 then
            local alpha = 1 - math.exp(-Config.AimVisualSpeed * dt)
            local ok, result = pcall(function()
                return PoolAI.SweepAim(previous.Unit, target, alpha)
            end)

            if ok and typeof(result) == "Vector2" and result.Magnitude > 0.0001 then
                smoothed = result.Unit
            else
                local blended = previous.Unit:Lerp(target, alpha)
                if blended.Magnitude > 0.0001 then
                    smoothed = blended.Unit
                end
            end
        end

        self.__CueBotSmoothAimDir = smoothed
        self.__CueBotSmoothAimTime = now
        return smoothed
    end

    PoolAimOverlay.Update = function(self, cuePos, aimDir, castResult, pullFraction, guideLength, isLegal)
        aimDir = smoothOverlayAim(self, aimDir)
        Live.lastOverlaySelf = self

        if not Live.activeLinesEnabled then
            clearAllVisuals()
            return oldUpdate(self, cuePos, aimDir, castResult, pullFraction, guideLength, isLegal)
        end

        self.GuidesEnabled = true
        oldUpdate(self, cuePos, aimDir, castResult, pullFraction, guideLength, isLegal)

        if self.ObjectLine then self.ObjectLine.Visible = false end
        if self.CueLine then self.CueLine.Visible = false end

        if not self.Root or not self.Root.Visible or aimDir.Magnitude < 0.0001 or not Live.activeSim then
            clearAllVisuals()
            return
        end

        local shotPower
        if pullFraction and pullFraction > 0.02 then
            shotPower = pullFraction
            Live.currentPower = pullFraction
        else
            shotPower = 0.75
        end

        local activeBallCount = 0
        for _, num in Live.activeSim.Order do
            local b = Live.activeSim.Balls[num]
            if b and not b.Pocketed then activeBallCount += 1 end
        end

        if not Live.forceResimulate
            and activeRoot == self.Root
            and activeBallCount == Live.lastBallCount
            and isLegal == Live.lastLegal
            and math.abs(shotPower - Live.lastPower) < 0.001
            and (cuePos - Live.lastCuePos).Magnitude < 0.001
            and (aimDir - Live.lastAimDir).Magnitude < 0.0002
            and (Live.currentSpin - Live.lastSpin).Magnitude < 0.001
        then
            return
        end

        Live.forceResimulate = false
        Live.lastCuePos = cuePos
        Live.lastAimDir = aimDir
        Live.lastPower = shotPower
        Live.lastSpin = Live.currentSpin
        Live.lastLegal = isLegal
        Live.lastBallCount = activeBallCount

        local lineIdx = 1
        local markerIdx = 1
        local ballDiam = PoolConstants.BallDiameter
        local frameSize = PoolTableRenderer2D.GetFrameSize()

        local simClone = PoolPhysics.Clone(Live.activeSim)
        local cueNum = PoolPhysics.CueNumber(simClone)
        local cueBall = simClone.Balls[cueNum]

        if not cueBall or cueBall.Pocketed then
            clearAllVisuals()
            return
        end

        cueBall.Position = cuePos

        local initialCast = oldCastCueBall(simClone, aimDir)
        local primaryTargetNum = (initialCast and initialCast.Kind == "Ball") and initialCast.Other or nil

        if primaryTargetNum and simClone.Balls[primaryTargetNum] then
            local targetPos = simClone.Balls[primaryTargetNum].Position
            local ringColor = (isLegal == false) and COLORS.Scratch or COLORS.TargetRing
            local targetRing = getMarker(markerIdx, self.Root, ballDiam * 1.38, ringColor, 0.85, 2.5, tostring(primaryTargetNum))
            markerIdx += 1
            placeMarker(targetRing, targetPos, frameSize)
        end

        isSimulatingClone = true
        PoolPhysics.Shoot(simClone, aimDir, shotPower, Live.currentSpin)
        isSimulatingClone = false

        local polylines = {}
        local movedBalls = {}

        for _, num in simClone.Order do
            local b = simClone.Balls[num]
            if b and not b.Pocketed then
                polylines[num] = { { Pos = b.Position, PostHit = false } }
            end
        end

        local fixedDelta = PoolStepper.FixedDelta or (1 / 120)
        local maxSteps = math.ceil((PoolStepper.MaxSettleSeconds or 6.5) / fixedDelta)
        local cueHasHit = false
        local eventCursor = 0

        for step = 1, maxSteps do
            if simClone.Settled then break end
            PoolPhysics.Step(simClone, fixedDelta)

            local newEventThisStep = false
            for eIdx = eventCursor + 1, #simClone.Events do
                local ev = simClone.Events[eIdx]
                newEventThisStep = true
                if ev.Kind == "BallHit" and (ev.Ball == cueNum or ev.Other == cueNum) then
                    cueHasHit = true
                end
            end
            eventCursor = #simClone.Events

            if newEventThisStep or (step % 3 == 0) or simClone.Settled then
                for _, num in simClone.Order do
                    local b = simClone.Balls[num]
                    local poly = polylines[num]
                    if b and poly then
                        local count = #poly
                        local lastPt = poly[count]
                        local curPos = b.Position
                        local delta = curPos - lastPt.Pos

                        if delta.Magnitude > 0.08 then
                            movedBalls[num] = true
                            local isPostHit = (num ~= cueNum) or cueHasHit

                            local merged = false
                            if not newEventThisStep and count >= 2 and lastPt.PostHit == isPostHit then
                                local prevPt = poly[count - 1]
                                local prevDir = (lastPt.Pos - prevPt.Pos).Unit
                                local curDir = delta.Unit
                                if prevDir:Dot(curDir) > 0.9992 then
                                    lastPt.Pos = curPos
                                    merged = true
                                end
                            end

                            if not merged then
                                table.insert(poly, {
                                    Pos = curPos,
                                    PostHit = isPostHit
                                })
                            end
                        end
                    end
                end
            end
        end

        for _, num in simClone.Order do
            if movedBalls[num] then
                local poly = polylines[num]
                local b = simClone.Balls[num]

                for i = 1, #poly - 1 do
                    local pt1 = poly[i]
                    local pt2 = poly[i + 1]

                    local color, thickness, trans, zOff
                    if num == cueNum then
                        if not pt2.PostHit then
                            color = (isLegal == false) and COLORS.Scratch or COLORS.CuePre
                            thickness = 0.45
                            trans = 0.25
                            zOff = 30
                        else
                            color = (b.Pocketed or b.Sinking) and COLORS.Scratch or COLORS.CuePost
                            thickness = 0.55
                            trans = 0.1
                            zOff = 32
                        end
                    elseif num == primaryTargetNum then
                        color = (b.Pocketed or b.Sinking) and COLORS.Pocketed or COLORS.PrimaryPath
                        thickness = 0.6
                        trans = 0.08
                        zOff = 33
                    else
                        color = (b.Pocketed or b.Sinking) and COLORS.Pocketed or COLORS.ComboPath
                        thickness = 0.5
                        trans = 0.15
                        zOff = 31
                    end

                    local line = getLine(lineIdx, self.Root)
                    lineIdx += 1
                    drawLine(line, pt1.Pos, pt2.Pos, thickness, color, trans, zOff, frameSize)
                end

                if b then
                    local finalPos = b.Position
                    if b.Pocketed or b.Sinking then
                        if num == cueNum then
                            local scratchMarker = getMarker(markerIdx, self.Root, ballDiam * 1.35, COLORS.Scratch, 0.2, 3, "X")
                            markerIdx += 1
                            placeMarker(scratchMarker, finalPos, frameSize)
                        else
                            local potMarker = getMarker(markerIdx, self.Root, ballDiam * 1.3, COLORS.Pocketed, 0.25, 3, tostring(num))
                            markerIdx += 1
                            placeMarker(potMarker, finalPos, frameSize)
                        end
                    else
                        local restColor = (num == cueNum) and COLORS.CuePost
                            or ((num == primaryTargetNum) and COLORS.PrimaryPath or COLORS.ComboPath)
                        local labelText = (num == cueNum) and "C" or tostring(num)

                        local restMarker = getMarker(markerIdx, self.Root, ballDiam * 0.95, restColor, 0.55, 2, labelText)
                        markerIdx += 1
                        placeMarker(restMarker, finalPos, frameSize)
                    end
                end
            end
        end

        for i = lineIdx, usedLines do
            if linePool[i] then linePool[i].Visible = false end
        end
        for i = markerIdx, usedMarkers do
            if markerPool[i] then markerPool[i].Visible = false end
        end

        usedLines = lineIdx - 1
        usedMarkers = markerIdx - 1
    end

    return Overlay
end
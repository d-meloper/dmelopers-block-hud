local M = {}

local function trim(value)
    local text = tostring(value or '')
    text = text:gsub('^%s+', '')
    text = text:gsub('%s+$', '')
    return text
end

local function numberValue(value, fallback)
    local number = tonumber(value)
    if number == nil then
        return fallback
    end
    return number
end

local function integerValue(value, fallback)
    local number = numberValue(value, fallback)
    if number == nil then
        return fallback
    end
    if number >= 0 then
        return math.floor(number)
    end
    return math.ceil(number)
end

local function boolValue(value, fallback)
    if value == nil then
        return fallback
    end
    if value == true or value == false then
        return value
    end
    local text = trim(value):lower()
    if text == '1' or text == 'true' or text == 'yes' or text == 'on' then
        return true
    end
    if text == '0' or text == 'false' or text == 'no' or text == 'off' then
        return false
    end
    return fallback
end

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function positiveModulo(value, modulus)
    if modulus <= 0 then
        return 0
    end
    local result = math.fmod(value, modulus)
    if result < 0 then
        result = result + modulus
    end
    return result
end

local Animator = {}
Animator.__index = Animator

local function normalizeProfile(profile)
    profile = profile or {}

    local frameCount = math.max(1, integerValue(profile.frameCount, 1))
    local frameWidth = math.max(1, integerValue(profile.frameWidth, 1))
    local frameHeight = math.max(1, integerValue(profile.frameHeight, 1))
    local columns = math.max(1, integerValue(profile.columns, frameCount))
    local startFrame = clamp(integerValue(profile.startFrame, 0), 0, frameCount - 1)
    local endFrame = clamp(integerValue(profile.endFrame, frameCount - 1), 0, frameCount - 1)

    if endFrame < startFrame then
        startFrame, endFrame = endFrame, startFrame
    end

    local frameStep = math.max(1, math.abs(integerValue(profile.frameStep, 1)))
    local frameMs = math.max(1, numberValue(profile.frameMs, 100))
    local tickMs = math.max(1, numberValue(profile.tickMs, numberValue(profile.updateMs, frameMs)))
    local mode = trim(profile.mode):lower()
    if mode == '' then
        if boolValue(profile.once, false) then
            mode = 'once'
        elseif boolValue(profile.pingpong, false) then
            mode = 'pingpong'
        else
            mode = 'loop'
        end
    end
    if mode ~= 'loop' and mode ~= 'once' and mode ~= 'pingpong' then
        mode = 'loop'
    end

    return {
        sheetPath = trim(profile.sheetPath),
        meterName = trim(profile.meterName),
        frameWidth = frameWidth,
        frameHeight = frameHeight,
        frameCount = frameCount,
        columns = columns,
        startFrame = startFrame,
        endFrame = endFrame,
        frameStep = frameStep,
        frameMs = frameMs,
        tickMs = tickMs,
        mode = mode,
        reverse = boolValue(profile.reverse, false),
        frozen = boolValue(profile.frozen, false),
        freezeFrame = clamp(integerValue(profile.freezeFrame, startFrame), 0, frameCount - 1),
        redrawOnFrameChangeOnly = boolValue(profile.redrawOnFrameChangeOnly, true),
        skipCatchUp = boolValue(profile.skipCatchUp, true),
        maxCatchUpFrames = math.max(1, integerValue(profile.maxCatchUpFrames, 4)),
    }
end

local function buildSequence(profile)
    local sequence = {}
    local frame = profile.startFrame
    while frame <= profile.endFrame do
        sequence[#sequence + 1] = frame
        frame = frame + profile.frameStep
    end

    if #sequence == 0 then
        sequence[1] = profile.startFrame
    end

    if profile.reverse then
        local reversed = {}
        for index = #sequence, 1, -1 do
            reversed[#reversed + 1] = sequence[index]
        end
        sequence = reversed
    end

    if profile.mode == 'pingpong' and #sequence > 1 then
        local pingpong = {}
        for index = 1, #sequence do
            pingpong[#pingpong + 1] = sequence[index]
        end
        for index = #sequence - 1, 2, -1 do
            pingpong[#pingpong + 1] = sequence[index]
        end
        sequence = pingpong
    end

    return sequence
end

local function frameCrop(profile, frameIndex)
    local column = positiveModulo(frameIndex, profile.columns)
    local row = math.floor(frameIndex / profile.columns)
    return column * profile.frameWidth, row * profile.frameHeight
end

function Animator:_setOption(option, value)
    self.skin:Bang('!SetOption', self.profile.meterName, option, tostring(value))
end

function Animator:_updateMeter()
    self.skin:Bang('!UpdateMeter', self.profile.meterName)
end

function Animator:_redraw()
    self.skin:Bang('!Redraw')
end

function Animator:_applyFrame(frameIndex, force)
    frameIndex = clamp(integerValue(frameIndex, self.profile.startFrame), 0, self.profile.frameCount - 1)
    if not force and self.currentFrame == frameIndex then
        return false
    end

    local cropX, cropY = frameCrop(self.profile, frameIndex)
    self.currentFrame = frameIndex
    self:_setOption('ImageCrop', string.format('%d,%d,%d,%d,1', cropX, cropY, self.profile.frameWidth, self.profile.frameHeight))
    self:_updateMeter()
    if force or not self.profile.redrawOnFrameChangeOnly or self.lastRenderedFrame ~= frameIndex then
        self:_redraw()
    end
    self.lastRenderedFrame = frameIndex
    return true
end

function Animator:_sequenceIndexForFrame(frameIndex)
    for index, value in ipairs(self.sequence) do
        if value == frameIndex then
            return index
        end
    end
    return 1
end

function Animator:_advanceOnce()
    if #self.sequence <= 1 then
        self.playing = self.profile.mode ~= 'once'
        return
    end

    local nextIndex = self.sequenceIndex + 1
    if nextIndex > #self.sequence then
        if self.profile.mode == 'once' then
            nextIndex = #self.sequence
            self.playing = false
        else
            nextIndex = 1
        end
    end
    self.sequenceIndex = nextIndex
end

function Animator:Initialize()
    self.profile = normalizeProfile(self.sourceProfile)
    self.sequence = buildSequence(self.profile)
    self.sequenceIndex = 1
    self.currentFrame = nil
    self.lastRenderedFrame = nil
    self.elapsedMs = 0
    self.playing = not self.profile.frozen
    self:_setOption('ImageName', self.profile.sheetPath)
    self:_applyFrame(self:CurrentFrame(), true)
    return 0
end

function Animator:CurrentFrame()
    if self.profile.frozen then
        return self.profile.freezeFrame
    end
    return self.sequence[self.sequenceIndex] or self.profile.startFrame
end

function Animator:Update()
    if self.profile.frozen or not self.playing then
        return 0
    end

    self.elapsedMs = (self.elapsedMs or 0) + self.profile.tickMs
    if self.elapsedMs < self.profile.frameMs then
        return 0
    end

    local steps = math.floor(self.elapsedMs / self.profile.frameMs)
    if self.profile.skipCatchUp then
        steps = 1
    else
        steps = clamp(steps, 1, self.profile.maxCatchUpFrames)
    end

    for _ = 1, steps do
        self:_advanceOnce()
    end

    if self.profile.skipCatchUp then
        self.elapsedMs = 0
    else
        self.elapsedMs = self.elapsedMs - (steps * self.profile.frameMs)
    end

    self:_applyFrame(self:CurrentFrame(), false)
    return 0
end

function Animator:Play()
    self.profile.frozen = false
    self.playing = true
    self.elapsedMs = 0
    self:_applyFrame(self:CurrentFrame(), true)
    return 0
end

function Animator:Pause()
    self.playing = false
    return 0
end

function Animator:Resume()
    if not self.profile.frozen then
        self.playing = true
        self.elapsedMs = 0
    end
    return 0
end

function Animator:Stop()
    self.playing = false
    self.sequenceIndex = 1
    self.elapsedMs = 0
    self:_applyFrame(self:CurrentFrame(), true)
    return 0
end

function Animator:Reset()
    self.sequenceIndex = 1
    self.elapsedMs = 0
    self:_applyFrame(self:CurrentFrame(), true)
    return 0
end

function Animator:SetFrozen(value)
    self.profile.frozen = boolValue(value, self.profile.frozen)
    if self.profile.frozen then
        self.playing = false
    else
        self.playing = true
        self.elapsedMs = 0
    end
    self:_applyFrame(self:CurrentFrame(), true)
    return 0
end

function Animator:SetFrameMs(value)
    self.profile.frameMs = math.max(1, numberValue(value, self.profile.frameMs))
    self.elapsedMs = 0
    return 0
end

function Animator:SetFrameRange(startFrame, endFrame)
    self.profile.startFrame = clamp(integerValue(startFrame, self.profile.startFrame), 0, self.profile.frameCount - 1)
    self.profile.endFrame = clamp(integerValue(endFrame, self.profile.endFrame), 0, self.profile.frameCount - 1)
    if self.profile.endFrame < self.profile.startFrame then
        self.profile.startFrame, self.profile.endFrame = self.profile.endFrame, self.profile.startFrame
    end
    self.sequence = buildSequence(self.profile)
    self.sequenceIndex = self:_sequenceIndexForFrame(self.currentFrame or self.profile.startFrame)
    self:_applyFrame(self:CurrentFrame(), true)
    return 0
end

function M.create(skin, profile)
    local animator = {
        skin = skin,
        sourceProfile = profile or {},
    }
    setmetatable(animator, Animator)
    return animator
end

return M

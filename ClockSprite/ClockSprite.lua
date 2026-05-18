local FRAME_COUNT = 64
local FRAME_WIDTH = 256
local FRAME_HEIGHT = 256
local FRAMES_PER_ROW = 5
local SECONDS_PER_DAY = 86400
local NOON_SECOND_OF_DAY = 43200
local function setVariable(name, value)
    SKIN:Bang('!SetVariable', name, tostring(value))
end
local function positiveModulo(value, modulus)
    local result = math.fmod(value, modulus)
    if result < 0 then
        result = result + modulus
    end
    return result
end
local function updateSpriteFrame()
    local hour = tonumber(os.date('%H')) or 0
    local minute = tonumber(os.date('%M')) or 0
    local second = tonumber(os.date('%S')) or 0
    local secondOfDay = (hour * 3600) + (minute * 60) + second
    local phaseSeconds = positiveModulo(secondOfDay - NOON_SECOND_OF_DAY, SECONDS_PER_DAY)
    local frameIndex = math.floor((phaseSeconds * FRAME_COUNT) / SECONDS_PER_DAY)
    if frameIndex < 0 then
        frameIndex = 0
    elseif frameIndex >= FRAME_COUNT then
        frameIndex = FRAME_COUNT - 1
    end
    local cropX = (frameIndex % FRAMES_PER_ROW) * FRAME_WIDTH
    local cropY = math.floor(frameIndex / FRAMES_PER_ROW) * FRAME_HEIGHT
    setVariable('ClockSpriteFrameIndex', frameIndex)
    setVariable('ClockSpriteCropX', cropX)
    setVariable('ClockSpriteCropY', cropY)
    SKIN:Bang('!UpdateMeter', 'MeterClockSprite')
    SKIN:Bang('!Redraw')
end
function Initialize()
    updateSpriteFrame()
end
function Update()
    updateSpriteFrame()
end
function RefreshSprite()
    updateSpriteFrame()
end
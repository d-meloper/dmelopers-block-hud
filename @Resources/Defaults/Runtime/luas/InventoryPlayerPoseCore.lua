local M = {}

local COLUMN_COUNT = 13
local ROW_COUNT = 9
local CENTER_COLUMN = 6
local CENTER_ROW = 4
local HALF_PI = math.pi / 2

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function round(value)
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

function M.CenterCell()
    return CENTER_COLUMN, CENTER_ROW
end

function M.CellKey(column, row)
    return tostring(tonumber(column) or CENTER_COLUMN) .. ':' .. tostring(tonumber(row) or CENTER_ROW)
end

function M.CellForPoint(mouseX, mouseY, bounds)
    bounds = bounds or {}
    local width = math.max(1, tonumber(bounds.width) or 1)
    local height = math.max(1, tonumber(bounds.height) or 1)
    local centerX = (tonumber(bounds.x) or 0) + (width / 2)
    local centerY = (tonumber(bounds.y) or 0) + (height / 2)
    local sensitivity = 40 * width / 49
    local horizontal = math.atan((centerX - (tonumber(mouseX) or centerX)) / sensitivity)
    local vertical = math.atan((centerY - (tonumber(mouseY) or centerY)) / sensitivity)
    local column = clamp(round(CENTER_COLUMN + ((horizontal / HALF_PI) * CENTER_COLUMN)), 0, COLUMN_COUNT - 1)
    local row = clamp(round(CENTER_ROW + ((vertical / HALF_PI) * CENTER_ROW)), 0, ROW_COUNT - 1)
    return column, row, horizontal, vertical
end

function M.CropForCell(column, row, frameWidth, frameHeight)
    local resolvedColumn = clamp(round(tonumber(column) or CENTER_COLUMN), 0, COLUMN_COUNT - 1)
    local resolvedRow = clamp(round(tonumber(row) or CENTER_ROW), 0, ROW_COUNT - 1)
    local width = math.max(1, round(tonumber(frameWidth) or 1))
    local height = math.max(1, round(tonumber(frameHeight) or 1))
    return resolvedColumn * width, resolvedRow * height, width, height
end

function M.PointInRect(x, y, rect)
    rect = rect or {}
    local left = tonumber(rect.x)
    local top = tonumber(rect.y)
    local width = tonumber(rect.width)
    local height = tonumber(rect.height)
    if not left or not top or not width or not height or width <= 0 or height <= 0 then
        return false
    end
    local pointX = tonumber(x)
    local pointY = tonumber(y)
    if not pointX or not pointY then
        return false
    end
    return pointX >= left and pointX < left + width and pointY >= top and pointY < top + height
end

M.COLUMN_COUNT = COLUMN_COUNT
M.ROW_COUNT = ROW_COUNT
M.CENTER_COLUMN = CENTER_COLUMN
M.CENTER_ROW = CENTER_ROW

return M

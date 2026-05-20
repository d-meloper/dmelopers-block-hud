_G.DMeloper                         = _G.DMeloper or {}
_G.DMeloper.OPEN_INVENTORY_KEY      = "_OPEN_INVENTORY_"

_G.DMeloper.BANG_REDRAW             = "!Redraw"
_G.DMeloper.BANG_SET_OPTION         = '!SetOption'
_G.DMeloper.BANG_SET_VARIABLE       = "!SetVariable"
_G.DMeloper.BANG_UPDATE_METER       = "!UpdateMeter"
_G.DMeloper.BANG_UPDATE_METER_GROUP = "!UpdateMeterGroup"
_G.DMeloper.BANG_HIDDEN             = "Hidden"
_G.DMeloper.BANG_IMAGE_NAME         = 'ImageName'
_G.DMeloper.BANG_TEXT               = "Text"
_G.DMeloper.BANG_FONT_SIZE          = "FontSize"
_G.DMeloper.BANG_X                  = "X"
_G.DMeloper.BANG_Y                  = "Y"
_G.DMeloper.BANG_W                  = "W"
_G.DMeloper.BANG_H                  = "H"

_G.DMeloper.EXTRA_INV_GAP           = 16



function _G.DMeloper.GetRowExtraOffset(idxY)
    if idxY >= 2 then
        local configuredGap = tonumber(SKIN:GetVariable('InventoryRowExtraGap', tostring(_G.DMeloper.EXTRA_INV_GAP)))
        return configuredGap or _G.DMeloper.EXTRA_INV_GAP
    end
    return 0
end

function _G.DMeloper.Clamp(x, min, max)
    if x < min then return min end
    if x > max then return max end
    return x
end

function _G.DMeloper.EvalNumber(expr)
    if type(expr) ~= "string" then
        return nil
    end

    expr = expr:gsub("%s+", "")
    if expr == "" then return nil end

    local prec = { ["+"] = 1, ["-"] = 1, ["*"] = 2, ["/"] = 2, ["u-"] = 3 }
    local rightAssoc = { ["u-"] = true }

    local function isOp(tok)
        return tok == "+" or tok == "-" or tok == "*" or tok == "/" or tok == "u-"
    end

    local tokens = {}
    local i, len = 1, #expr
    local prevType = "START"

    while i <= len do
        local c = expr:sub(i, i)

        if c:match("%d") or c == "." then
            local j = i
            local sawDot = false

            while j <= len do
                local ch = expr:sub(j, j)
                if ch:match("%d") then
                    j = j + 1
                elseif ch == "." and not sawDot then
                    sawDot = true
                    j = j + 1
                else
                    break
                end
            end

            local numStr = expr:sub(i, j - 1)
            local num = tonumber(numStr)
            if not num then return nil end

            table.insert(tokens, num)
            prevType = "NUM"
            i = j
        elseif c == "(" then
            table.insert(tokens, "(")
            prevType = "LPAREN"
            i = i + 1
        elseif c == ")" then
            table.insert(tokens, ")")
            prevType = "RPAREN"
            i = i + 1
        elseif c == "+" or c == "-" or c == "*" or c == "/" then
            if c == "-" and (prevType == "START" or prevType == "OP" or prevType == "LPAREN") then
                table.insert(tokens, "u-")
            else
                table.insert(tokens, c)
            end
            prevType = "OP"
            i = i + 1
        else
            return nil
        end
    end

    local output = {}
    local opstack = {}

    local function pushOp(op)
        while #opstack > 0 do
            local top = opstack[#opstack]
            if top == "(" then break end

            local pTop = prec[top]
            local pOp  = prec[op]
            if not pTop or not pOp then break end

            local shouldPop
            if rightAssoc[op] then
                shouldPop = (pTop > pOp)
            else
                shouldPop = (pTop >= pOp)
            end

            if shouldPop then
                table.insert(output, table.remove(opstack))
            else
                break
            end
        end
        table.insert(opstack, op)
    end

    for _, tok in ipairs(tokens) do
        if type(tok) == "number" then
            table.insert(output, tok)
        elseif tok == "(" then
            table.insert(opstack, tok)
        elseif tok == ")" then
            local found = false
            while #opstack > 0 do
                local top = table.remove(opstack)
                if top == "(" then
                    found = true
                    break
                end
                table.insert(output, top)
            end
            if not found then
                return nil
            end
        elseif isOp(tok) then
            pushOp(tok)
        else
            return nil
        end
    end

    while #opstack > 0 do
        local top = table.remove(opstack)
        if top == "(" or top == ")" then
            return nil
        end
        table.insert(output, top)
    end

    local stack = {}

    for _, tok in ipairs(output) do
        if type(tok) == "number" then
            table.insert(stack, tok)
        elseif tok == "u-" then
            local a = table.remove(stack)
            if a == nil then return nil end
            table.insert(stack, -a)
        else
            local b = table.remove(stack)
            local a = table.remove(stack)
            if a == nil or b == nil then return nil end

            if tok == "+" then
                table.insert(stack, a + b)
            elseif tok == "-" then
                table.insert(stack, a - b)
            elseif tok == "*" then
                table.insert(stack, a * b)
            elseif tok == "/" then
                if b == 0 then return nil end
                table.insert(stack, a / b)
            else
                return nil
            end
        end
    end

    if #stack ~= 1 then
        return nil
    end
    return stack[1]
end

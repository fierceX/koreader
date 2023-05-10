local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local http = require("socket.http")
local json = require("json")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local _ = require("gettext")

-- readwise exporter
local MemosExporter = require("base"):new {
    name = "memos",
    is_remote = true,
}

local function makeRequest(method, request_body, api)
    local sink = {}
    local request_body_json = json.encode(request_body)
    local source = ltn12.source.string(request_body_json)
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local request = {
        url     = api,
        method  = method,
        sink    = ltn12.sink.table(sink),
        source  = source,
        headers = {
            ["Content-Type"] = "application/json"
        },
    }
    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()

    if code ~= 200 then
        logger.warn("Memos: HTTP response code <> 200. Response status:", status or code or "network unreachable")
        logger.dbg("Response headers:", headers)
        return nil, status
    end

    local response = json.decode(sink[1])
    return response
end

function MemosExporter:isReadyToExport()
    if self.settings.api then return true end
    return false
end

function MemosExporter:getMenuTable()
    return {
        text = _("Memos"),
        checked_func = function() return self:isEnabled() end,
        sub_item_table = {
            {
                text = _("Set Memos API URL"),
                keep_menu_open = true,
                callback = function()
                    local auth_dialog
                    auth_dialog = InputDialog:new {
                        title = _("Set API URL for Memos"),
                        input = self.settings.api,
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    callback = function()
                                        UIManager:close(auth_dialog)
                                    end
                                },
                                {
                                    text = _("Set API URL"),
                                    callback = function()
                                        self.settings.api = auth_dialog:getInputText()
                                        self:saveSettings()
                                        UIManager:close(auth_dialog)
                                    end
                                }
                            }
                        }
                    }
                    UIManager:show(auth_dialog)
                    auth_dialog:onShowKeyboard()
                end
            },
            {
                text = _("Export to Memos"),
                checked_func = function() return self:isEnabled() end,
                callback = function() self:toggleEnabled() end,
            },

        }
    }
end

function MemosExporter:createHighlights(booknotes)
    for _, chapter in ipairs(booknotes) do
        for _, clipping in ipairs(chapter) do
            local highlight = clipping.text .. "\n\n"
            if clipping.note then
                highlight = highlight .. clipping.note .. "\n\n"
            end
            highlight =  highlight .. booknotes.title .. " (page: " .. clipping.page .. "）\n\n #" .. booknotes.title .. " #koreader"
            local result, err = makeRequest("POST", { content = highlight }, self.settings.api)
            if not result then
                logger.warn("error creating highlights", err)
                return false
            end
        end
    end

    logger.dbg("createHighlights success")
    return true
end

function MemosExporter:export(t)
    if not self:isReadyToExport() then return false end

    for _, booknotes in ipairs(t) do
        local ok = self:createHighlights(booknotes)
        if not ok then return false end
    end
    return true
end

return MemosExporter

-- Multi-chat support with sidebar
local send = gurt.select('#send')
local input = gurt.select('#input')
local chat = gurt.select('#chat')
local chatList = gurt.select('#chat-list')
local newChatBtn = gurt.select('#new-chat')
local inputFocused = false

-- In-memory render buffer for current chat
local allMessages = {}
chat.text = "Start chatting with Gronk"

-- Conversations schema persisted in crumbs
-- conversations: array of { id: string, title: string, history: [{role, content}] }
-- currentChatId: string
local function uuid()
    -- simple unique id using timestamp and random
    return tostring(Time.now()) .. "-" .. tostring(math.random(100000, 999999))
end

local function readConversations()
    local raw = gurt.crumbs.get("conversations")
    if raw ~= nil then
        local ok, parsed = pcall(JSON.parse, raw)
        if ok and parsed then return parsed end
    end
    return nil
end

local function writeConversations(conversations)
    gurt.crumbs.set({ name = "conversations", value = JSON.stringify(conversations) })
end

local function readCurrentChatId()
    return gurt.crumbs.get("currentChatId")
end

local function writeCurrentChatId(id)
    gurt.crumbs.set({ name = "currentChatId", value = id })
end

-- Migration from legacy single 'history' crumb
local function migrateIfNeeded()
    local convs = readConversations()
    if convs ~= nil then return convs end
    local legacy = gurt.crumbs.get("history")
    local conversations = {}
    if legacy ~= nil then
        local ok, hist = pcall(JSON.parse, legacy)
        if ok and hist then
            local id = uuid()
            local title = (#hist > 0 and hist[1].content) or "New Chat"
            conversations = { { id = id, title = title, history = hist } }
            writeCurrentChatId(id)
            -- remove legacy crumb
            gurt.crumbs.delete("history")
        end
    end
    if #conversations == 0 then
        local id = uuid()
        conversations = { { id = id, title = "New Chat", history = {} } }
        writeCurrentChatId(id)
    end
    writeConversations(conversations)
    return conversations
end

local conversations = migrateIfNeeded()
local currentChatId = readCurrentChatId() or (conversations[1] and conversations[1].id)
if currentChatId == nil then
    currentChatId = uuid()
    table.insert(conversations, { id = currentChatId, title = "New Chat", history = {} })
    writeConversations(conversations)
    writeCurrentChatId(currentChatId)
end

local function getCurrentChat()
    for _, c in ipairs(conversations) do
        if c.id == currentChatId then return c end
    end
    return nil
end

local function setCurrentChat(id)
    currentChatId = id
    writeCurrentChatId(id)
end

-- Rendering helpers
local function renderTranscript()
    allMessages = {}
    local c = getCurrentChat()
    if c == nil then chat.text = "Start chatting with Gronk" return end
    if #c.history == 0 then
        chat.text = "Start chatting with Gronk"
        return
    end
    for _, m in ipairs(c.history) do
        local roleText = string.replace(string.replace(m.role, "assistant", "Gronk"), "user", "You")
        table.insert(allMessages, { role = m.role, text = m.content })
    end
    local combined = {}
    for _, m in ipairs(allMessages) do
        table.insert(combined, string.replace(string.replace(m.role, "assistant", "Gronk"), "user", "You") .. ": " .. m.text)
    end
    chat.text = table.concat(combined, "\n\n")
end

local function clearChildren(el)
    local kids = el.children
    for i = #kids, 1, -1 do
        local child = kids[i]
        child:remove()
    end
end

local justDeletedAt = 0

local function renderChatList()
    clearChildren(chatList)
    for i, c in ipairs(conversations) do
        local title = c.title ~= nil and c.title or ((#c.history > 0 and c.history[1].content) or "New Chat")
        local rowStyle = "flex flex-row items-center gap-2 px-2 py-1 rounded"
        if c.id == currentChatId then
            rowStyle = rowStyle .. " bg-[#111827]"
        end
        local row = gurt.create('div', { style = rowStyle })
        local titleStyle = (c.id == currentChatId) and "font-bold" or ""
        local titleEl = gurt.create('span', { text = title, style = titleStyle })
        local del = gurt.create('button', { text = '✕', style = 'ml-auto text-[#9ca3af] px-2 hover:text-[#f87171]' })

        row:on('click', function()
            -- If we just clicked delete, ignore row click
            if (Time.now() - justDeletedAt) < 0.2 then return end
            selectChatByIndex(i)
        end)
        del:on('click', function()
            justDeletedAt = Time.now()
            deleteChatByIndex(i)
        end)

        row:append(titleEl)
        row:append(del)
        chatList:append(row)
    end
end

-- Streaming append for current render
local function appendMessage(role, text)
    local message = { role = role, text = text or "" }
    table.insert(allMessages, message)
    local combined = {}
    for _, m in ipairs(allMessages) do
        table.insert(combined, string.replace(string.replace(m.role, "assistant", "Gronk"), "user", "You") .. ": " .. m.text)
    end
    chat.text = table.concat(combined, "\n\n")
    return function(newText)
        message.text = newText
        local combined2 = {}
        for _, m in ipairs(allMessages) do
            table.insert(combined2, string.replace(string.replace(m.role, "assistant", "Gronk"), "user", "You") .. ": " .. m.text)
        end
        chat.text = table.concat(combined2, "\n\n")
    end
end

local function persist()
    writeConversations(conversations)
end

-- Create/select/delete chat actions
local function createNewChat()
    local id = uuid()
    local chatObj = { id = id, title = "New Chat", history = {} }
    table.insert(conversations, 1, chatObj)
    setCurrentChat(id)
    persist()
    renderChatList()
    renderTranscript()
end

local function deleteChatByIndex(idx)
    if idx < 1 or idx > #conversations then return end
    local removed = table.remove(conversations, idx)
    if removed and removed.id == currentChatId then
        local nextId = (conversations[1] and conversations[1].id) or nil
        if nextId == nil then
            nextId = uuid()
            table.insert(conversations, { id = nextId, title = "New Chat", history = {} })
        end
        setCurrentChat(nextId)
    end
    persist()
    renderChatList()
    renderTranscript()
end

local function selectChatByIndex(idx)
    if idx < 1 or idx > #conversations then return end
    local c = conversations[idx]
    setCurrentChat(c.id)
    renderChatList()
    renderTranscript()
end

-- Wire UI events
newChatBtn:on('click', function()
    createNewChat()
end)

-- Click handling within chat list area:
-- We don't have per-item elements here, so use simple heuristics:
chatList:on('click', function(event)
    -- Approximate which line was clicked by y-position and line height assumption (not perfect)
    local size = chatList.size
    local lineHeight = 20 -- heuristic
    local y = event.y or 0
    local idx = math.floor(y / lineHeight) + 1
    if idx < 1 then idx = 1 end
    if idx > #conversations then idx = #conversations end

    -- Determine if click was on the [x] delete area by x-position heuristic
    local x = event.x or 0
    if x > (size.width - 40) then
        deleteChatByIndex(idx)
    else
        selectChatByIndex(idx)
    end
end)

-- Messaging
local server = "https://s.73206141212.com:23100"

function sendMessage(prompt)
    local c = getCurrentChat()
    if c == nil then return end

    -- Update title if first message
    if #c.history == 0 then
        c.title = string.sub(prompt, 1, 50)
    end

    -- Update history
    table.insert(c.history, { role = "user", content = prompt })

    -- Render immediately
    local assistant = appendMessage("assistant", "thinking")

    -- Persist before network
    persist()

    local response = fetch(server .. "/submit", {
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        body = JSON.stringify({ prompt = prompt, history = c.history })
    })

    if not response:ok() then
        trace.log("Submit failed: " .. response.status)
        assistant("Unable to contact server " .. response.status)
        return
    end

    local data = response:json()
    local jobId = data.jobId

    local done = false
    intervalId = setInterval(function()
        local pollResp = fetch(server .. "/poll/" .. jobId)
        if pollResp:ok() then
            local pollData = pollResp:json()
            if pollData.tokens then
                assistant(pollData.tokens)
            end
            if pollData.done and not done then
                if (not done) then
                    table.insert(c.history, { role = "assistant", content = pollData.tokens })
                    clearInterval(intervalId)
                    trace.log("Finished " .. pollData.tokens)
                    assistant(pollData.tokens)
                    persist()
                end
                done = true
            end
        else
            trace.log("Poll failed: " .. pollResp.status)
            assistant("Unable to contact server")
        end
    end, 100)
end

send:on('click', function()
    local query = input.value
    if query ~= '' then
        -- Render user then send
        appendMessage("user", query)
        sendMessage(query)
        input.value = '' -- clear input
    end
end)

local keys = {}

gurt.body:on('keydown', function(event)
    if inputFocused then
        if event.key == "Enter" and not event.shift then
            local query = input.value
            if query ~= '' then
                appendMessage("user", query)
                sendMessage(query)
                input.value = ''
            end
        end
    end
end)

gurt.body:on('keyup', function(event)
    keys[event.key] = false
end)

input:on('focusin', function()
    inputFocused = true
end)

input:on('focusout', function()
    inputFocused = false
end)

-- Initial renders
renderChatList()
renderTranscript()

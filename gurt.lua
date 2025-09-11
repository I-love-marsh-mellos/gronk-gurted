-- keep chat history in memory
local send = gurt.select('#send')
local clearChat = gurt.select('#clear-chat')
local input = gurt.select('#input')
local history = {}
local inputBar = gurt.select("#input-bar");
chat = gurt.select('#chat')
local inputFocused = false;

-- all messages live in here
local allMessages = {}
chat.text = "Start chatting with Gronk"
function appendMessage(role, text, streaming)
    local message = { role = role, text = text or "" }
    table.insert(allMessages, message)

    -- force initial render
    local function render()
        local combined = {}
        for _, m in ipairs(allMessages) do
            table.insert(combined, string.replace(string.replace(m.role, "assistant", "Gronk"), "user", "You") .. ": " .. m.text)
        end
        local text = table.concat(combined, "\n\n") -- spacing
        chat.text = text
    end

    render()

    -- return updater function
    return function(newText)
        message.text = newText
        render()
    end
end

local h = gurt.crumbs.get("history")
if h ~= nil then
    history = JSON.parse(h)
    for _, m in ipairs(history) do
        appendMessage(m.role, m.content, false)
    end
end

function sendMessage(prompt)
    appendMessage("user", prompt, false)
    table.insert(history, { role = "user", content = prompt })

    local assistant = appendMessage("assistant", "", true)
    assistant("thinking")

    local server = "https://s.73206141212.com:23100"
    local response = fetch(server .. "/submit", {
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        body = JSON.stringify({ prompt = prompt, history = history })
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
                    table.insert(history, { role = "assistant", content = pollData.tokens })
                    clearInterval(intervalId)
                    trace.log("Finished " .. pollData.tokens)
                    assistant(pollData.tokens)
                    gurt.crumbs.set({
                        name = "history", 
                        value = JSON.stringify(history),
                    })
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

clearChat:on('click', function()
    if (clearChat.text == "Click againg to confirm") then
        gurt.crumbs.delete("history")
        gurt.location.reload();
    end
    clearChat.text = "Click againg to confirm"
end)
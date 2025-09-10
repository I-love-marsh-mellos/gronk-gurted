-- keep chat history in memory
local send = gurt.select('#send')
local input = gurt.select('#input')
local history = {}
local inputBar = gurt.select("#input-bar");
local busy = false;
local chat = gurt.select('#chat')

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

function countNewlines(str)
    local count = 0
    for _ in str:gmatch("\n") do
        count = count + 1
    end
    return count
end

function sendMessage(prompt)
    appendMessage("user", prompt, false)
    table.insert(history, { role = "user", content = prompt })

    local server = "https://s.73206141212.com:23100"
    local response = fetch(server .. "/submit", {
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        body = JSON.stringify({ prompt = prompt, history = history })
    })

    if not response:ok() then
        trace.log("Submit failed: " .. response.status)
        return
    end

    local data = response:json()
    local jobId = data.jobId

    local assistant = appendMessage("assistant", "", true)
    assistant("thinking")

    intervalId = setInterval(function()
        local pollResp = fetch(server .. "/poll/" .. jobId)
        if pollResp:ok() then
            local pollData = pollResp:json()
            if pollData.tokens then
                assistant(pollData.tokens)
            end
            if pollData.done then
                busy = false
                send.setAttribute("disabled", busy)
                table.insert(history, { role = "assistant", content = pollData.tokens })
                clearInterval(intervalId)
                trace.log("Finished " .. pollData.tokens)
                assistant(pollData.tokens)
            end
        else
            trace.log("Poll failed: " .. pollResp.status)
        end
    end, 200)
end


send:on('click', function()
    if (busy) return
    busy = true
    send.setAttribute("disabled", busy)
    local query = input.value
    if query ~= '' then
        sendMessage(query)
        input.value = '' -- clear input
    end
end)
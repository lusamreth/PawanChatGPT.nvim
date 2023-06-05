local job = require("plenary.job")
local Config = require("chatgpt.config")
local logger = require("chatgpt.common.logger")

local Api = {}

-- API URL
Api.COMPLETIONS_URL = "https://api.openai.com/v1/completions"
Api.CHAT_COMPLETIONS_URL = "https://api.openai.com/v1/chat/completions"
Api.EDITS_URL = "https://api.openai.com/v1/edits"

function Api.completions(custom_params, cb)
    local params = vim.tbl_extend("keep", custom_params, Config.options.openai_params)
    Api.make_call(Api.COMPLETIONS_URL, params, cb)
end

function Api.chat_completions(custom_params, cb)
    local params = vim.tbl_extend("keep", custom_params, Config.options.openai_params)
    Api.make_call(Api.CHAT_COMPLETIONS_URL, params, cb)
end

function Api.edits(custom_params, cb)
    local params = vim.tbl_extend("keep", custom_params, Config.options.openai_edit_params)
    Api.make_call(Api.EDITS_URL, params, cb)
end

local function curl_post(url, params)
    local gpt_payload = {
        model = "gpt-3.5-turbo",
        max_tokens = 3000,
        messages = {
            {
                role = "system",
                content = "a very helpful assistant",
            },
            {
                role = "user",
                content = "hello",
            },
        },
    }
    local jsonified = vim.fn.json_encode(gpt_payload)

    local res = curl.post(url, {
        body = jsonified,
        headers = {
            content_type = "application/json",
            authorization = "Bearer " .. Api.OPENAI_API_KEY,
        },
    })
    vim.pretty_print(res)
    return res.body
end

function Api.make_call(url, params, cb)
    TMP_MSG_FILENAME = os.tmpname()
    local f = io.open(TMP_MSG_FILENAME, "w+")
    if f == nil then
        vim.notify("Cannot open temporary message file: " .. TMP_MSG_FILENAME, vim.log.levels.ERROR)
        return
    end
    f:write(vim.fn.json_encode(params))
    f:close()

    local response = curl_post(url, params)
    print("response", response)
    Api.handle_response(response, 0, cb)
    -- Api.job = job:new({
    --     command = "curl",
    --     args = {
    --         url,
    --         "-H",
    --         "Content-Type: application/json",
    --         "-H",
    --         "Authorization: Bearer " .. Api.OPENAI_API_KEY,
    --         "-d",
    --         "@" .. TMP_MSG_FILENAME,
    --     },
    --     on_exit = vim.schedule_wrap(function(response, exit_code)
    --         Api.handle_response(response, exit_code, cb)
    --     end),
    -- }):start()
end

Api.handle_response = vim.schedule_wrap(function(response, exit_code, cb)
    os.remove(TMP_MSG_FILENAME)
    if exit_code ~= 0 then
        vim.notify("An Error Occurred ...", vim.log.levels.ERROR)
        cb("ERROR: API Error")
    end

    local result = table.concat(response:result(), "\n")
    local json = vim.fn.json_decode(result)
    if json == nil then
        cb("No Response.")
    elseif json.error then
        cb("// API ERROR: " .. json.error.message)
    else
        local message = json.choices[1].message
        if message ~= nil then
            local response_text = json.choices[1].message.content
            if type(response_text) == "string" and response_text ~= "" then
                cb(response_text, json.usage)
            else
                cb("...")
            end
        else
            local response_text = json.choices[1].text
            if type(response_text) == "string" and response_text ~= "" then
                cb(response_text, json.usage)
            else
                cb("...")
            end
        end
    end
end)

function Api.close()
    if Api.job then
        job:shutdown()
    end
end

function Api.setup()
    -- API KEY
    Api.OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
    if not Api.OPENAI_API_KEY then
        if Config.options.api_key_cmd ~= nil and Config.options.api_key_cmd ~= "" then
            Api.OPENAI_API_KEY = vim.fn.system(Config.options.api_key_cmd)
            if not Api.OPENAI_API_KEY then
                logger.warn("Config 'api_key_cmd' did not return a value when executed")
                return
            end
        else
            logger.warn("OPENAI_API_KEY environment variable not set")
            return
        end
    end
    Api.OPENAI_API_KEY = Api.OPENAI_API_KEY:gsub("%s+$", "")
end

return Api
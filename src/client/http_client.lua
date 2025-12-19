--[[
    HTTP Client Module

    Async HTTP client for fetching cat images and uploading archives.
    Uses Copas for non-blocking requests.

    Concurrency is controlled by the number of workers (num_workers),
    not by a semaphore - each worker makes one request at a time.

    Usage:
        local HttpClient = require("client.http_client")
        local client = HttpClient.new("http://algisothal.ru:8889")

        -- Inside a coroutine:
        local image_data, err = client:fetch_cat()
        if image_data then
            -- Process the image
        end
]]

local copas = require("copas")
local http = require("copas.http")
local ltn12 = require("ltn12")

local HttpClient = {}
HttpClient.__index = HttpClient

--- Create a new HTTP client
-- @param base_url string Base API URL
-- @param config table Additional settings (optional)
-- @return HttpClient
function HttpClient.new(base_url, config)
    config = config or {}

    return setmetatable({
        base_url = base_url,
        endpoint = config.endpoint or "/cat",
        timeout = config.timeout or 30,
        retry_count = config.retry_count or 3,
        retry_delay = config.retry_delay or 1,
        retry_multiplier = config.retry_multiplier or 2
    }, HttpClient)
end

--- Execute HTTP GET request with retry logic
-- @param url string URL to request
-- @return string|nil Response body or nil on error
-- @return string|nil Error message
local function http_get_with_retry(self, url)
    local last_error = nil
    local delay = self.retry_delay

    for attempt = 1, self.retry_count do
        local response_body = {}

        local result, status_code, headers, status_line = http.request{
            url = url,
            method = "GET",
            sink = ltn12.sink.table(response_body),
            redirect = true,
            timeout = self.timeout
        }

        if result and status_code == 200 then
            return table.concat(response_body), nil
        end

        if not result then
            last_error = "Connection error: " .. tostring(status_code)
        elseif status_code >= 500 then
            -- Server error - can retry
            last_error = "Server error: " .. tostring(status_code)
        elseif status_code >= 400 then
            -- Client error - no point in retrying
            return nil, "Client error: " .. tostring(status_code)
        else
            last_error = "Unexpected status: " .. tostring(status_code)
        end

        -- If there are more attempts - wait with exponential backoff
        if attempt < self.retry_count then
            copas.sleep(delay)
            delay = delay * self.retry_multiplier
        end
    end

    return nil, last_error .. " (after " .. self.retry_count .. " attempts)"
end

--- Create multipart/form-data body
-- @param filename string File name
-- @param data string Binary file data
-- @param field_name string Form field name (default "file")
-- @return string Multipart body
-- @return string Boundary for Content-Type
local function create_multipart_body(filename, data, field_name)
    field_name = field_name or "file"
    -- Generate unique boundary
    local boundary = "----LuaFormBoundary" .. os.time() .. math.random(1000, 9999)

    local body = table.concat({
        "--" .. boundary,
        string.format('Content-Disposition: form-data; name="%s"; filename="%s"', field_name, filename),
        "Content-Type: application/zip",
        "",
        data,
        "--" .. boundary .. "--",
        ""
    }, "\r\n")

    return body, boundary
end

--- Execute HTTP POST request
-- @param url string URL to request
-- @param data string Data to send
-- @param content_type string Content-Type header
-- @return boolean Operation success
-- @return string|nil Error message
local function http_post(self, url, data, content_type)
    local response_body = {}

    local result, status_code, headers, status_line = http.request{
        url = url,
        method = "POST",
        headers = {
            ["Content-Type"] = content_type,
            ["Content-Length"] = tostring(#data)
        },
        source = ltn12.source.string(data),
        sink = ltn12.sink.table(response_body),
    }

    if result and (status_code == 200 or status_code == 201) then
        return true, nil
    end

    if not result then
        return false, "Connection error: " .. tostring(status_code)
    end

    return false, "HTTP error: " .. tostring(status_code)
end

--- Fetch a cat image
-- Concurrency is controlled by the number of workers
-- @return string|nil Binary image data
-- @return string|nil Error message
function HttpClient:fetch_cat()
    local url = self.base_url .. self.endpoint
    local data, err = http_get_with_retry(self, url)
    return data, err
end

--- Upload archive to server (multipart/form-data)
-- @param data string Binary archive data
-- @param filename string File name (default "cats.zip")
-- @return boolean Operation success
-- @return string|nil Error message
function HttpClient:upload_archive(data, filename)
    filename = filename or "cats.zip"

    local url = self.base_url .. self.endpoint
    local body, boundary = create_multipart_body(filename, data, "file")
    local content_type = "multipart/form-data; boundary=" .. boundary
    local success, err = http_post(self, url, body, content_type)

    return success, err
end

return HttpClient

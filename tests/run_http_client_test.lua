#!/usr/bin/env lua
--[[
    Test script for HTTP Client module
    Run: lua tests/run_http_client_test.lua

    Tests against the real Cat API (debug endpoint for speed)
]]

package.path = package.path .. ";src/?.lua;src/?/init.lua"

local copas = require("copas")
local HttpClient = require("client.http_client")

-- Use debug API (no delay) for faster tests
local API_URL = os.getenv("CAT_API_URL") or "http://algisothal.ru:8890"

print("=== HTTP Client Test ===")
print("API URL: " .. API_URL)
print("")

local all_passed = true

-- Test 1: Create HTTP Client
print("[TEST 1] Creating HTTP Client")
local client = HttpClient.new(API_URL, {
    timeout = 30,
    retry_count = 3
})
print("  base_url: " .. client.base_url)
print("  endpoint: " .. client.endpoint)
print("  PASSED")
print("")

-- Test 2: Fetch single cat
print("[TEST 2] Fetching single cat image")
copas.addthread(function()
    local start_time = os.clock()
    local data, err = client:fetch_cat()
    local elapsed = os.clock() - start_time

    if data then
        print("  Received " .. #data .. " bytes")
        print("  Time: " .. string.format("%.2f", elapsed) .. "s")

        -- Check if it looks like a JPEG
        local header = string.sub(data, 1, 2)
        if header == "\xff\xd8" then
            print("  Format: JPEG (valid)")
        else
            print("  Format: Unknown (first bytes: " .. 
                  string.format("%02x %02x", string.byte(header, 1), string.byte(header, 2)) .. ")")
        end
        print("  PASSED")
    else
        print("  ERROR: " .. tostring(err))
        all_passed = false
    end
end)

copas.loop()
print("")

-- Test 3: Parallel fetching with multiple workers
print("[TEST 3] Parallel fetching (5 cats with copas workers)")
local client2 = HttpClient.new(API_URL)
local fetched_count = 0
local total_bytes = 0

copas.addthread(function()
    local start_time = os.clock()

    for i = 1, 5 do
        copas.addthread(function()
            local cat_id = i
            print("  Cat " .. cat_id .. " fetching...")

            local data, err = client2:fetch_cat()

            if data then
                fetched_count = fetched_count + 1
                total_bytes = total_bytes + #data
                print("  Cat " .. cat_id .. " received " .. #data .. " bytes")
            else
                print("  Cat " .. cat_id .. " ERROR: " .. tostring(err))
            end
        end)
    end
end)

copas.loop()

print("  Total fetched: " .. fetched_count .. "/5")
print("  Total bytes: " .. total_bytes)
if fetched_count == 5 then
    print("  PASSED")
else
    print("  FAILED")
    all_passed = false
end
print("")

-- Test 4: Error handling (bad URL)
print("[TEST 4] Error handling (bad URL)")
local bad_client = HttpClient.new("http://localhost:9999", {
    retry_count = 2,
    retry_delay = 0.1
})

copas.addthread(function()
    local start_time = os.clock()
    local data, err = bad_client:fetch_cat()
    local elapsed = os.clock() - start_time

    if data then
        print("  Unexpected success")
        all_passed = false
    else
        print("  Expected error: " .. tostring(err))
        print("  Time for retries: " .. string.format("%.2f", elapsed) .. "s")
        print("  PASSED (error handled gracefully)")
    end
end)

copas.loop()
print("")

-- Summary
print("=== Test Summary ===")
if all_passed then
    print("All HTTP Client Tests PASSED")
else
    print("Some tests FAILED")
    os.exit(1)
end

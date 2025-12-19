#!/usr/bin/env lua
--[[
    Test script for Fetcher module
    Run: lua tests/run_fetcher_test.lua

    Tests parallel fetching with real Cat API
]]

package.path = package.path .. ";src/?.lua;src/?/init.lua"

local copas = require("copas")
local HttpClient = require("client.http_client")
local Deduplicator = require("services.deduplicator")
local Fetcher = require("services.fetcher")

-- Use debug API (no delay) for faster tests
local API_URL = os.getenv("CAT_API_URL") or "http://algisothal.ru:8890"

print("=== Fetcher Test ===")
print("API URL: " .. API_URL)
print("")

local all_passed = true

-- Test 1: Create Fetcher
print("[TEST 1] Creating Fetcher")
local client = HttpClient.new(API_URL)
local dedup = Deduplicator.new()
local fetcher = Fetcher.new({
    http_client = client,
    deduplicator = dedup
})

print("  Fetcher created")
print("  PASSED")
print("")

-- Test 2: Fetch 5 unique cats with 3 workers
print("[TEST 2] Fetching 5 unique cats with 3 workers")

copas.addthread(function()
    local start_time = os.clock()

    local images = fetcher:fetch_unique(5, 3)

    local elapsed = os.clock() - start_time

    print("")
    print("  Results:")
    print("    Unique cats: " .. #images)
    print("    Time: " .. string.format("%.2f", elapsed) .. "s")

    -- Check all images are valid JPEGs
    local valid_count = 0
    for i, img in ipairs(images) do
        local header = string.sub(img, 1, 2)
        if header == "\xff\xd8" then
            valid_count = valid_count + 1
        end
    end
    print("    Valid JPEGs: " .. valid_count .. "/" .. #images)

    if #images == 5 and valid_count == 5 then
        print("  PASSED")
    else
        print("  FAILED")
        all_passed = false
    end
end)

copas.loop()
print("")

-- Test 3: Fetch 12 unique cats (full batch) with 10 workers
print("[TEST 3] Fetching 12 unique cats with 10 workers")

-- Reset deduplicator for new batch
dedup:reset()

copas.addthread(function()
    local start_time = os.clock()

    local images = fetcher:fetch_unique(12, 10)

    local elapsed = os.clock() - start_time

    print("")
    print("  Results:")
    print("    Unique cats: " .. #images)
    print("    Time: " .. string.format("%.2f", elapsed) .. "s")
    print("    Deduplicator count: " .. dedup:get_count())

    -- Verify all images are unique (no duplicates in results)
    local hash_check = {}
    local hash = require("utils.hash")
    local duplicates_found = 0

    for i, img in ipairs(images) do
        local h = hash.md5(img)
        if hash_check[h] then
            duplicates_found = duplicates_found + 1
        else
            hash_check[h] = true
        end
    end

    print("    Duplicates in results: " .. duplicates_found)

    if #images == 12 and duplicates_found == 0 then
        print("  PASSED")
    else
        print("  FAILED")
        all_passed = false
    end
end)

copas.loop()
print("")

-- Test 4: Stop functionality
print("[TEST 4] Stop functionality")

dedup:reset()
local fetcher2 = Fetcher.new({
    http_client = client,
    deduplicator = dedup
})

copas.addthread(function()
    -- Start fetching in background
    copas.addthread(function()
        fetcher2:fetch_unique(100, 5)  -- Try to fetch 100 (will be stopped)
    end)

    -- Wait a bit then stop
    copas.sleep(0.5)
    fetcher2:stop()
    copas.sleep(0.3)

    local count = fetcher2:get_count()
    print("  Fetched before stop: " .. count)
    print("  is_running: " .. tostring(fetcher2:is_running()))

    if count < 100 and not fetcher2:is_running() then
        print("  PASSED (stopped before completing)")
    else
        print("  FAILED")
        all_passed = false
    end
end)

copas.loop()
print("")

-- Summary
print("=== Test Summary ===")
if all_passed then
    print("All Fetcher Tests PASSED")
else
    print("Some tests FAILED")
    os.exit(1)
end

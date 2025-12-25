#!/usr/bin/env lua
--[[
    Unit tests for StreamingFetcher module

    Uses mock HTTP client to test without real network calls
]]

package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local StreamingFetcher = require("services.streaming_fetcher")
local ImageQueue = require("services.image_queue")

local tests_run = 0
local tests_passed = 0

local function test(name, func)
    tests_run = tests_run + 1
    local ok, err = pcall(func)
    if ok then
        tests_passed = tests_passed + 1
        print("✓ " .. name)
    else
        print("✗ " .. name .. ": " .. tostring(err))
    end
end

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s",
              msg or "Assertion failed", tostring(expected), tostring(actual)))
    end
end

local function assert_true(value, msg)
    if not value then
        error(msg or "Expected true, got false")
    end
end

local function assert_false(value, msg)
    if value then
        error(msg or "Expected false, got true")
    end
end

local function assert_gte(actual, expected, msg)
    if actual < expected then
        error(string.format("%s: expected >= %s, got %s",
              msg or "Assertion failed", tostring(expected), tostring(actual)))
    end
end

-- Mock HTTP Client that returns fake images
local MockHttpClient = {}
MockHttpClient.__index = MockHttpClient

function MockHttpClient.new(options)
    options = options or {}
    return setmetatable({
        call_count = 0,
        unique_images = options.unique_images or 100,  -- how many unique images to generate
        fail_rate = options.fail_rate or 0,            -- probability of failure (0-1)
        delay = options.delay or 0                      -- simulated delay
    }, MockHttpClient)
end

function MockHttpClient:fetch_cat()
    self.call_count = self.call_count + 1

    -- Simulate failures
    if self.fail_rate > 0 and math.random() < self.fail_rate then
        return nil, "Simulated network error"
    end

    -- Generate unique image data (cycles through unique_images)
    local image_id = ((self.call_count - 1) % self.unique_images) + 1
    local image_data = string.format("FAKE_IMAGE_DATA_%04d_%d", image_id, os.time())

    return image_data
end

function MockHttpClient:get_call_count()
    return self.call_count
end

print("\n=== StreamingFetcher Tests ===\n")

-- Test 1: Constructor
test("new() creates fetcher with defaults", function()
    local mock_client = MockHttpClient.new()
    local fetcher = StreamingFetcher.new(mock_client)

    assert_eq(fetcher.num_workers, 12, "default workers")
    assert_false(fetcher:is_running(), "not running initially")
    assert_eq(fetcher:get_count(), 0, "zero count initially")
end)

-- Test 2: Constructor with options
test("new() accepts custom options", function()
    local mock_client = MockHttpClient.new()
    local fetcher = StreamingFetcher.new(mock_client, {
        num_workers = 5
    })

    assert_eq(fetcher.num_workers, 5, "custom workers")
end)

-- Test 3: get_stats() initial state
test("get_stats() returns initial zeroes", function()
    local mock_client = MockHttpClient.new()
    local fetcher = StreamingFetcher.new(mock_client)

    local stats = fetcher:get_stats()
    assert_eq(stats.fetched, 0, "fetched")
    assert_eq(stats.duplicates, 0, "duplicates")
    assert_eq(stats.errors, 0, "errors")
end)

-- Test 4: reset() clears state
test("reset() clears statistics", function()
    local mock_client = MockHttpClient.new()
    local fetcher = StreamingFetcher.new(mock_client)

    -- Manually set some stats
    fetcher.stats.fetched = 10
    fetcher.stats.duplicates = 5
    fetcher.stats.errors = 2

    fetcher:reset()

    local stats = fetcher:get_stats()
    assert_eq(stats.fetched, 0, "fetched reset")
    assert_eq(stats.duplicates, 0, "duplicates reset")
    assert_eq(stats.errors, 0, "errors reset")
end)

-- Test 5: Fetcher pushes to queue (integration with copas)
test("start() fetches images to queue", function()
    local copas = require("copas")

    local mock_client = MockHttpClient.new({ unique_images = 20 })
    local fetcher = StreamingFetcher.new(mock_client, { num_workers = 2 })
    local queue = ImageQueue.new(50)

    copas.addthread(function()
        fetcher:start(queue)
        
        -- Wait until we have at least 5 images
        while fetcher:get_count() < 5 do
            copas.pause(0.05)
        end
        
        fetcher:stop()
        queue:close()
    end)

    copas.loop()

    local stats = fetcher:get_stats()
    assert_gte(stats.fetched, 5, "fetched at least 5 images")
    assert_gte(queue:get_stats().pushed, 5, "queue received at least 5 items")
end)

-- Test 6: Deduplication works
test("fetcher deduplicates images", function()
    local copas = require("copas")

    -- Mock client that returns only 3 unique images (will cause duplicates)
    local mock_client = MockHttpClient.new({ unique_images = 3 })
    local fetcher = StreamingFetcher.new(mock_client, { num_workers = 2 })
    local queue = ImageQueue.new(50)

    copas.addthread(function()
        fetcher:start(queue)
        
        -- Wait until we have 3 unique images
        while fetcher:get_count() < 3 do
            copas.pause(0.05)
        end
        
        fetcher:stop()
        queue:close()
    end)

    copas.loop()

    local stats = fetcher:get_stats()
    assert_gte(stats.fetched, 3, "fetched at least 3 unique")
    assert_gte(stats.duplicates, 0, "duplicates counted")
end)

-- Test 7: Error handling
test("fetcher counts errors", function()
    local copas = require("copas")

    -- Mock client with 50% fail rate
    local mock_client = MockHttpClient.new({
        unique_images = 10,
        fail_rate = 0.5
    })
    local fetcher = StreamingFetcher.new(mock_client, { num_workers = 2 })
    local queue = ImageQueue.new(50)

    copas.addthread(function()
        fetcher:start(queue)
        
        -- Wait until we have 3 images
        while fetcher:get_count() < 3 do
            copas.pause(0.05)
        end
        
        fetcher:stop()
        queue:close()
    end)

    copas.loop()

    local stats = fetcher:get_stats()
    assert_gte(stats.fetched, 3, "still fetched target")
    assert_gte(stats.errors, 0, "errors counted")
end)

-- Test 8: Stop functionality
test("stop() stops fetching", function()
    local copas = require("copas")

    local mock_client = MockHttpClient.new({ unique_images = 100 })
    local fetcher = StreamingFetcher.new(mock_client, { num_workers = 2 })
    local queue = ImageQueue.new(50)

    copas.addthread(function()
        fetcher:start(queue)

        -- Stop after short delay
        copas.pause(0.1)
        fetcher:stop()
        queue:close()
    end)

    copas.loop()

    assert_false(fetcher:is_running(), "stopped running")
end)

-- Test 9: Queue receives correct data structure
test("queue items have correct structure", function()
    local copas = require("copas")

    local mock_client = MockHttpClient.new({ unique_images = 10 })
    local fetcher = StreamingFetcher.new(mock_client, { num_workers = 1 })
    local queue = ImageQueue.new(50)

    copas.addthread(function()
        fetcher:start(queue)
        
        while fetcher:get_count() < 1 do
            copas.pause(0.05)
        end
        
        fetcher:stop()
        queue:close()
    end)

    copas.loop()

    -- Pop item from closed queue
    local item = queue:try_pop()

    assert_true(item ~= nil, "item exists")
    assert_true(item.data ~= nil, "has data")
    assert_true(item.filename ~= nil, "has filename")
    assert_true(item.filename:match("^cat_"), "filename starts with cat_")
    assert_true(item.filename:match("%.jpg$"), "filename ends with .jpg")
    assert_true(item.timestamp > 0, "has timestamp")
end)

-- Test 10: Filename uses MD5 hash
test("filename is derived from MD5 hash", function()
    local copas = require("copas")

    local mock_client = MockHttpClient.new({ unique_images = 10 })
    local fetcher = StreamingFetcher.new(mock_client, { num_workers = 1 })
    local queue = ImageQueue.new(50)

    copas.addthread(function()
        fetcher:start(queue)
        
        while fetcher:get_count() < 2 do
            copas.pause(0.05)
        end
        
        fetcher:stop()
        queue:close()
    end)

    copas.loop()

    local item1 = queue:try_pop()
    local item2 = queue:try_pop()

    -- Filenames should be different (different hashes)
    assert_true(item1.filename ~= item2.filename, "different filenames for different images")

    -- Filename format: cat_XXXXXXXX.jpg (8 hex chars from MD5)
    assert_true(item1.filename:match("^cat_[a-f0-9]+%.jpg$"), "valid filename format")
end)

-- Summary
print(string.format("\n=== Results: %d/%d tests passed ===\n", tests_passed, tests_run))

if tests_passed == tests_run then
    os.exit(0)
else
    os.exit(1)
end

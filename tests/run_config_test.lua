#!/usr/bin/env lua
--[[
    Configuration Test Suite
]]

package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

local config = require("config")

local GREEN = "\27[32m"
local RED = "\27[31m"
local YELLOW = "\27[33m"
local RESET = "\27[0m"

local function log(color, ...)
    io.write(color)
    print(...)
    io.write(RESET)
    io.flush()
end

local tests_passed = 0
local tests_failed = 0

-- ============== TEST 1: Loading config ==============
do
    print("\n" .. YELLOW .. "[TEST 1] Loading config..." .. RESET)

    assert(config ~= nil, "Config should load")
    assert(type(config) == "table", "Config should be a table")

    log(GREEN, "[TEST 1] Loading config - PASSED")
    tests_passed = tests_passed + 1
end

-- ============== TEST 2: Config structure ==============
do
    print("\n" .. YELLOW .. "[TEST 2] Config structure..." .. RESET)

    -- Cat API
    assert(config.cat_api, "cat_api section should exist")
    assert(config.cat_api.base_url, "base_url should exist")
    assert(config.cat_api.debug_url, "debug_url should exist")
    assert(config.cat_api.endpoint, "endpoint should exist")

    -- Upload
    assert(config.upload, "upload section should exist")
    assert(type(config.upload.enabled) == "boolean", "upload.enabled should exist")

    -- Async
    assert(config.async, "async section should exist")
    assert(config.async.num_workers, "num_workers should exist")
    assert(config.async.timeout, "timeout should exist")
    assert(config.async.retry_count, "retry_count should exist")

    -- Archive
    assert(config.archive, "archive section should exist")
    assert(config.archive.target_count, "target_count should exist")
    assert(config.archive.filename_pattern, "filename_pattern should exist")

    -- Logging
    assert(config.logging, "logging section should exist")
    assert(config.logging.level, "log level should exist")

    -- Service
    assert(config.service, "service section should exist")
    assert(config.service.cycle_delay ~= nil, "cycle_delay should exist")

    log(GREEN, "[TEST 2] Config structure - PASSED")
    tests_passed = tests_passed + 1
end

-- ============== TEST 3: Default values ==============
do
    print("\n" .. YELLOW .. "[TEST 3] Default values..." .. RESET)

    assert(config.cat_api.base_url:find("algisothal"), "Default base_url should be algisothal")
    assert(config.cat_api.endpoint == "/cat", "Default endpoint should be /cat")
    assert(config.async.num_workers == 12, "Default num_workers should be 12")
    assert(config.archive.target_count == 12, "Default target_count should be 12")
    assert(config.archive.filename_pattern == "cat_%02d.jpg", "Default pattern should be cat_%02d.jpg")

    log(GREEN, "[TEST 3] Default values - PASSED")
    tests_passed = tests_passed + 1
end

-- ============== TEST 4: Helper methods ==============
do
    print("\n" .. YELLOW .. "[TEST 4] Helper methods..." .. RESET)

    -- get_base_url
    assert(type(config.get_base_url) == "function", "get_base_url should be a function")
    local base_url = config:get_base_url()
    assert(type(base_url) == "string", "get_base_url should return string")
    assert(#base_url > 0, "base_url should not be empty")

    -- get_api_url
    assert(type(config.get_api_url) == "function", "get_api_url should be a function")
    local api_url = config:get_api_url()
    assert(api_url:find("/cat"), "api_url should contain /cat")

    -- dump
    assert(type(config.dump) == "function", "dump should be a function")

    log(GREEN, "[TEST 4] Helper methods - PASSED")
    tests_passed = tests_passed + 1
end

-- ============== TEST 5: Value types ==============
do
    print("\n" .. YELLOW .. "[TEST 5] Value types..." .. RESET)

    assert(type(config.async.num_workers) == "number", "num_workers should be number")
    assert(type(config.async.timeout) == "number", "timeout should be number")
    assert(type(config.async.retry_count) == "number", "retry_count should be number")
    assert(type(config.archive.target_count) == "number", "target_count should be number")
    assert(type(config.cat_api.use_debug) == "boolean", "use_debug should be boolean")
    assert(type(config.upload.enabled) == "boolean", "upload.enabled should be boolean")

    log(GREEN, "[TEST 5] Value types - PASSED")
    tests_passed = tests_passed + 1
end

-- ============== TEST 6: Debug/Production toggle ==============
do
    print("\n" .. YELLOW .. "[TEST 6] Debug/Production toggle..." .. RESET)

    local base = config:get_base_url()

    if config.cat_api.use_debug then
        assert(base == config.cat_api.debug_url, "Should return debug URL when use_debug=true")
    else
        assert(base == config.cat_api.base_url, "Should return production URL when use_debug=false")
    end

    log(GREEN, "[TEST 6] Debug/Production toggle - PASSED")
    tests_passed = tests_passed + 1
end

-- ============== TEST 7: Config dump ==============
do
    print("\n" .. YELLOW .. "[TEST 7] Config dump (visual check)..." .. RESET)

    config:dump()

    log(GREEN, "[TEST 7] Config dump - PASSED")
    tests_passed = tests_passed + 1
end

-- ============== SUMMARY ==============
print("\n" .. string.rep("=", 50))
if tests_failed == 0 then
    log(GREEN, string.format("All Config Tests PASSED (%d/%d)", 
        tests_passed, tests_passed + tests_failed))
else
    log(RED, string.format("Config Tests: %d PASSED, %d FAILED", 
        tests_passed, tests_failed))
    os.exit(1)
end

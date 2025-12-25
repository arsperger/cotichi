#!/usr/bin/env lua
--[[
    Unit tests for ImageQueue module
]]

package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

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

local function assert_nil(value, msg)
    if value ~= nil then
        error(msg or "Expected nil, got " .. tostring(value))
    end
end

print("\n=== ImageQueue Tests ===\n")

-- Test 1: Constructor
test("new() creates empty queue", function()
    local queue = ImageQueue.new()
    assert_eq(queue:size(), 0, "size")
    assert_true(queue:is_empty(), "is_empty")
    assert_false(queue:is_closed(), "is_closed")
    assert_eq(queue.max_size, 50, "default max_size")
end)

-- Test 2: Constructor with max_size
test("new(max_size) sets custom limit", function()
    local queue = ImageQueue.new(10)
    assert_eq(queue.max_size, 10, "custom max_size")
end)

-- Test 3: Push single item
test("push() adds item to queue", function()
    local queue = ImageQueue.new()
    local ok, err = queue:push("image_data_1", "cat_01.jpg")
    assert_true(ok, "push should succeed")
    assert_nil(err, "no error")
    assert_eq(queue:size(), 1, "size after push")
end)

-- Test 4: Push multiple items
test("push() adds multiple items", function()
    local queue = ImageQueue.new()
    queue:push("data1", "file1.jpg")
    queue:push("data2", "file2.jpg")
    queue:push("data3", "file3.jpg")
    assert_eq(queue:size(), 3, "size after 3 pushes")
end)

-- Test 5: try_pop from non-empty queue
test("try_pop() returns item from queue", function()
    local queue = ImageQueue.new()
    queue:push("test_data", "test.jpg")

    local item = queue:try_pop()
    assert_true(item ~= nil, "item should exist")
    assert_eq(item.data, "test_data", "data")
    assert_eq(item.filename, "test.jpg", "filename")
    assert_true(item.timestamp > 0, "timestamp")
    assert_eq(queue:size(), 0, "size after pop")
end)

-- Test 6: try_pop from empty queue
test("try_pop() returns nil for empty queue", function()
    local queue = ImageQueue.new()
    local item = queue:try_pop()
    assert_nil(item, "should return nil")
end)

-- Test 7: FIFO order
test("queue maintains FIFO order", function()
    local queue = ImageQueue.new()
    queue:push("first", "1.jpg")
    queue:push("second", "2.jpg")
    queue:push("third", "3.jpg")

    assert_eq(queue:try_pop().data, "first", "first item")
    assert_eq(queue:try_pop().data, "second", "second item")
    assert_eq(queue:try_pop().data, "third", "third item")
end)

-- Test 8: Close queue
test("close() sets closed flag", function()
    local queue = ImageQueue.new()
    assert_false(queue:is_closed(), "not closed initially")
    queue:close()
    assert_true(queue:is_closed(), "closed after close()")
end)

-- Test 9: Push to closed queue fails
test("push() to closed queue fails", function()
    local queue = ImageQueue.new()
    queue:close()
    local ok, err = queue:push("data", "file.jpg")
    assert_false(ok, "push should fail")
    assert_eq(err, "queue closed", "error message")
end)

-- Test 10: is_done()
test("is_done() returns true only when closed AND empty", function()
    local queue = ImageQueue.new()

    -- Not closed, empty
    assert_false(queue:is_done(), "not done when open and empty")

    -- Not closed, has items
    queue:push("data", "file.jpg")
    assert_false(queue:is_done(), "not done when has items")

    -- Closed, has items
    queue:close()
    assert_false(queue:is_done(), "not done when closed but has items")

    -- Closed, empty
    queue:try_pop()
    assert_true(queue:is_done(), "done when closed and empty")
end)

-- Test 11: is_full()
test("is_full() returns true when at max_size", function()
    local queue = ImageQueue.new(3)
    assert_false(queue:is_full(), "not full initially")

    queue:push("1", "1.jpg")
    queue:push("2", "2.jpg")
    assert_false(queue:is_full(), "not full at 2/3")

    queue:push("3", "3.jpg")
    assert_true(queue:is_full(), "full at 3/3")
end)

-- Test 12: get_stats()
test("get_stats() returns correct statistics", function()
    local queue = ImageQueue.new(10)
    queue:push("a", "a.jpg")
    queue:push("b", "b.jpg")
    queue:try_pop()

    local stats = queue:get_stats()
    assert_eq(stats.size, 1, "current size")
    assert_eq(stats.max_size, 10, "max size")
    assert_eq(stats.pushed, 2, "total pushed")
    assert_eq(stats.popped, 1, "total popped")
    assert_false(stats.closed, "not closed")
end)

-- Test 13: reset()
test("reset() clears queue state", function()
    local queue = ImageQueue.new()
    queue:push("data", "file.jpg")
    queue:close()

    queue:reset()

    assert_eq(queue:size(), 0, "size after reset")
    assert_false(queue:is_closed(), "not closed after reset")
    assert_eq(queue:get_stats().pushed, 0, "pushed counter reset")
end)

-- Summary
print(string.format("\n=== Results: %d/%d tests passed ===\n", tests_passed, tests_run))

if tests_passed == tests_run then
    os.exit(0)
else
    os.exit(1)
end

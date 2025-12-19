#!/usr/bin/env lua
--[[
    Test script for Deduplicator module
    Run: lua tests/run_deduplicator_test.lua
]]

package.path = package.path .. ";src/?.lua;src/?/init.lua"

local Deduplicator = require("services.deduplicator")
local hash = require("utils.hash")

print("=== Deduplicator Test ===")
print("")

local all_passed = true

-- Test 1: Hash module
print("[TEST 1] Hash module")
local test_data = "Hello, World!"
local h = hash.md5(test_data)
print("  Input: " .. test_data)
print("  MD5: " .. h)
-- Known MD5 for "Hello, World!" is 65a8e27d8879283831b664bd8b7f0ad4
if h == "65a8e27d8879283831b664bd8b7f0ad4" then
    print("  PASSED")
else
    print("  FAILED (expected 65a8e27d8879283831b664bd8b7f0ad4)")
    all_passed = false
end
print("")

-- Test 2: Create Deduplicator
print("[TEST 2] Creating Deduplicator")
local dedup = Deduplicator.new()
print("  count: " .. dedup:get_count())
if dedup:get_count() == 0 then
    print("  PASSED")
else
    print("  FAILED")
    all_passed = false
end
print("")

-- Test 3: Add unique images
print("[TEST 3] Adding unique images")
local img1 = "image data 1"
local img2 = "image data 2"
local img3 = "image data 3"

dedup:add_image(img1)
dedup:add_image(img2)
dedup:add_image(img3)

print("  Added 3 images")
print("  count: " .. dedup:get_count())
if dedup:get_count() == 3 then
    print("  PASSED")
else
    print("  FAILED (expected 3)")
    all_passed = false
end
print("")

-- Test 4: Detect duplicates
print("[TEST 4] Detecting duplicates")
local is_dup1 = dedup:is_duplicate(img1)
local is_dup_new = dedup:is_duplicate("new image data")

print("  is_duplicate(img1): " .. tostring(is_dup1))
print("  is_duplicate(new): " .. tostring(is_dup_new))

if is_dup1 == true and is_dup_new == false then
    print("  PASSED")
else
    print("  FAILED")
    all_passed = false
end
print("")

-- Test 5: Atomic try_add
print("[TEST 5] Atomic try_add")
local dedup2 = Deduplicator.new()
local added1 = dedup2:try_add("unique 1")
local added2 = dedup2:try_add("unique 2")
local added_dup = dedup2:try_add("unique 1")  -- duplicate

print("  try_add(unique 1): " .. tostring(added1))
print("  try_add(unique 2): " .. tostring(added2))
print("  try_add(unique 1 again): " .. tostring(added_dup))
print("  count: " .. dedup2:get_count())

if added1 == true and added2 == true and added_dup == false and dedup2:get_count() == 2 then
    print("  PASSED")
else
    print("  FAILED")
    all_passed = false
end
print("")

-- Test 6: Reset
print("[TEST 6] Reset")
dedup:reset()
print("  After reset, count: " .. dedup:get_count())
local is_dup_after_reset = dedup:is_duplicate(img1)
print("  is_duplicate(img1) after reset: " .. tostring(is_dup_after_reset))

if dedup:get_count() == 0 and is_dup_after_reset == false then
    print("  PASSED")
else
    print("  FAILED")
    all_passed = false
end
print("")

-- Test 7: Performance (1000 checks)
print("[TEST 7] Performance (1000 checks)")
local dedup3 = Deduplicator.new()
local start_time = os.clock()

for i = 1, 1000 do
    local fake_image = "fake image data " .. i
    dedup3:try_add(fake_image)
end

local elapsed = (os.clock() - start_time) * 1000  -- ms
local per_check = elapsed / 1000

print("  Total time: " .. string.format("%.2f", elapsed) .. " ms")
print("  Per check: " .. string.format("%.4f", per_check) .. " ms")

if per_check < 1 then
    print("  PASSED (< 1ms per check)")
else
    print("  FAILED (too slow)")
    all_passed = false
end
print("")

-- Test 8: Handle nil/empty data
print("[TEST 8] Handle nil/empty data")
local dedup4 = Deduplicator.new()
local hash_nil = dedup4:compute_hash(nil)
local hash_empty = dedup4:compute_hash("")
local is_dup_nil = dedup4:is_duplicate(nil)
local added_nil = dedup4:try_add(nil)

print("  compute_hash(nil): " .. tostring(hash_nil))
print("  compute_hash(''): " .. tostring(hash_empty))
print("  is_duplicate(nil): " .. tostring(is_dup_nil))
print("  try_add(nil): " .. tostring(added_nil))

if hash_nil == nil and is_dup_nil == false and added_nil == false then
    print("  PASSED")
else
    print("  FAILED")
    all_passed = false
end
print("")

-- Summary
print("=== Test Summary ===")
if all_passed then
    print("All Deduplicator Tests PASSED")
else
    print("Some tests FAILED")
    os.exit(1)
end

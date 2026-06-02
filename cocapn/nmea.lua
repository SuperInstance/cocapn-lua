--- CoCapn NMEA sentence parser.
-- Lightweight parser for NMEA 0183 talker sentences ($--...,*cs).
-- Handles checksum validation and field splitting.
-- No GPS/GNSS dependency — pure string processing.

local M = {}

--- Parse an NMEA 0183 sentence.
-- @param raw  The raw NMEA string (with or without trailing \\r\\n)
-- @return     Table {talker, sentence, fields, checksum_valid, raw}
--             or nil on malformed input (no $, no *)
function M.parse(raw)
  if type(raw) ~= "string" then return nil, "input must be string" end

  -- Strip whitespace
  raw = raw:match("^%s*(.-)%s*$") or raw

  -- Must start with $
  if raw:sub(1, 1) ~= "$" then return nil, "missing $" end

  -- Must have an asterisk for the checksum
  local star = raw:find("*", 2, true)
  if not star then return nil, "missing checksum delimiter *" end

  -- Extract body and checksum
  local body = raw:sub(2, star - 1)
  local chk_str = raw:sub(star + 1):gsub("%s", "")
  local expected_chk = tonumber(chk_str, 16)
  if not expected_chk then return nil, "invalid checksum hex" end

  -- Compute checksum over body (bitwise XOR, ~ is XOR in Lua 5.3+)
  local computed = 0
  for i = 1, #body do
    computed = computed ~ body:byte(i)
  end

  -- Talker ID (first 2 chars)
  local talker = body:sub(1, 2)
  -- Sentence type (2 chars normally after talker)
  local sentence = body:sub(3, 5):gsub(",.*", "")

  -- Split fields
  local fields = {}
  for field in body:gmatch("([^,]*)") do
    fields[#fields + 1] = field
  end

  return {
    talker         = talker,
    sentence       = sentence,
    fields         = fields,
    checksum       = expected_chk,
    checksum_valid = computed == expected_chk,
    raw            = raw,
  }
end

--- Build a simple NMEA sentence from components.
-- @param talker   2-char talker ID (e.g., "GP", "II", "AI")
-- @param sentence Sentence type (e.g., "RMC", "HDG", "MWV")
-- @param fields   Array of field values (strings or numbers)
-- @return         Formatted NMEA sentence string
function M.build(talker, sentence, fields)
  local body = talker .. sentence
  for _, v in ipairs(fields) do
    body = body .. "," .. tostring(v)
  end

  local chk = 0
  for i = 1, #body do
    chk = chk ~ body:byte(i)
  end

  return "$" .. body .. "*" .. string.upper(string.format("%02X", chk))
end

--- Parse latitude/longitude from NMEA format (DDDMM.MMMM -> degrees).
-- @param nmea_val  The raw NMEA coordinate string
-- @param hemi      Hemisphere character ('N','S','E','W')
-- @return          Decimal degrees, or nil on failure
function M.parse_coord(nmea_val, hemi)
  if not nmea_val or nmea_val == "" then return nil end

  local val = tonumber(nmea_val)
  if not val then return nil end

  -- Determine degrees part: for lat it's 2 digits, for lon it's 3
  local deg_len
  if hemi == "N" or hemi == "S" then
    deg_len = 2
  else
    deg_len = 3
  end

  -- Determine degrees from the original string
  -- Find the first non-digit
  local deg_str = nmea_val:sub(1, deg_len)
  local rest = nmea_val:sub(deg_len + 1)
  if rest == "" then rest = "0" end
  local deg = tonumber(deg_str)
  local minutes = tonumber(rest)

  local decimal = deg + (minutes / 60.0)

  if hemi == "S" or hemi == "W" then
    decimal = -decimal
  end

  return decimal
end

return M

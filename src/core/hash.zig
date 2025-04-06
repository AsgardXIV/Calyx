const std = @import("std");

/// A simple CRC32 checksum function using the JamCRC algorithm.
/// This is the correct implementation of the CRC32 checksum for XIV.
pub inline fn crc32(data: []const u8) u32 {
    return std.hash.crc.Crc32Jamcrc.hash(data);
}

test "crc32" {
    {
        const expected = 0xa2850653;
        const result = crc32("chara/equipment/e0633/material/v0010/mt_c0101e0633_met_a.mtrl");
        try std.testing.expectEqual(expected, result);
    }
}

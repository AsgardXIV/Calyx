const std = @import("std");

/// This is the correct implementation of the CRC32 checksum for XIV.
pub const Crc32 = std.hash.crc.Crc32Jamcrc;

/// A simple XIV compatible CRC32 checksum function
pub inline fn crc32(data: []const u8) u32 {
    return Crc32.hash(data);
}

test "crc32" {
    {
        const expected = 0xa2850653;
        const result = crc32("chara/equipment/e0633/material/v0010/mt_c0101e0633_met_a.mtrl");
        try std.testing.expectEqual(expected, result);
    }
}

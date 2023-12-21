const std = @import("std");

const Self = @This();

allocator: std.mem.Allocator,
target: []const u8,
method: std.http.Method,
body: []const u8,
post_parameters: std.StringHashMap([]const u8),
get_parameters: std.StringHashMap([]const u8),

pub fn init(server_response: *std.http.Server.Response, allocator: std.mem.Allocator) !Self {
    const body_escaped = try server_response.reader().readAllAlloc(allocator, 1 << 32);
    defer allocator.free(body_escaped);

    var result = Self{
        .allocator = allocator,
        .target = server_response.request.target,
        .method = server_response.request.method,
        .body = try std.Uri.unescapeString(allocator, body_escaped),
        .post_parameters = std.StringHashMap([]const u8).init(allocator),
        .get_parameters = std.StringHashMap([]const u8).init(allocator),
    };

    try result.parse_post_parameters();

    return result;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.body);
    self.post_parameters.deinit();
    self.get_parameters.deinit();
}

fn parse_post_parameters(self: *Self) !void {
    var parameters = std.mem.splitSequence(u8, self.body, "\r\n");

    while (parameters.next()) |parameter| {
        if (std.mem.indexOf(u8, parameter, "=")) |equal_pos| {
            const key = parameter[0..equal_pos];
            const value = parameter[(equal_pos + 1)..];
            try self.post_parameters.put(key, value);
        } else {
            try self.post_parameters.put(parameter, "");
        }
    }
}

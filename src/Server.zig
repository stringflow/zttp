const std = @import("std");
const Request = @import("Request.zig");
const Router = @import("Router.zig");
const View = @import("View.zig");

const Self = @This();

const max_header_size = 8192;

allocator: std.mem.Allocator,
http_server: std.http.Server,
router: Router,
view: View,

pub fn init(router: Router, allocator: std.mem.Allocator) !Self {
    return Self{
        .allocator = allocator,
        .http_server = std.http.Server.init(allocator, .{ .reuse_address = true }),
        .router = router,
        .view = try View.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.http_server.deinit();
    self.view.deinit();
}

pub fn listenBlocking(self: *Self, ip_address: []const u8, port: u16) !void {
    const address = try std.net.Address.parseIp(ip_address, port);
    try self.http_server.listen(address);

    std.debug.print("Start listening on {s}:{d}...\n", .{ ip_address, port });

    while (true) {
        var response = try self.http_server.accept(.{
            .allocator = self.allocator,
            .header_strategy = .{ .dynamic = max_header_size },
        });
        defer response.deinit();

        while (response.reset() != .closing) {
            response.wait() catch |err| switch (err) {
                error.HttpHeadersInvalid => break,
                error.EndOfStream => continue,
                else => return err,
            };

            std.debug.print("{s} \"{s}\": ", .{ @tagName(response.request.method), response.request.target });

            self.view.target = &response;

            var request = try Request.init(&response, self.allocator);
            defer request.deinit();

            var request_status = std.http.Status.internal_server_error;
            var request_error: ?anyerror = null;
            if (self.router.dispatch(&self.view, request)) |status| {
                request_status = status;
            } else |err| {
                request_error = err;
            }

            const output_size = try self.view.flush(request_status);

            std.debug.print("{d}, {d} bytes", .{ @intFromEnum(response.status), output_size });

            if (request_error) |err| {
                std.debug.print(" ({})", .{err});
            }

            std.debug.print("\n", .{});
        }
    }
}

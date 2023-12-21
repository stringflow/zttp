const std = @import("std");
const Server = @import("Server.zig");
const Request = @import("Request.zig");
const View = @import("View.zig");

const Self = @This();

const RouteFn = *const fn (*View, Request) anyerror!std.http.Status;

routes: std.AutoHashMap(std.http.Method, std.StringHashMap(RouteFn)),
file_servers: std.StringHashMap([]const u8),

pub fn init(allocator: std.mem.Allocator) !Self {
    var routes = std.AutoHashMap(std.http.Method, std.StringHashMap(RouteFn)).init(allocator);

    inline for (std.meta.fields(std.http.Method)) |method| {
        try routes.put(@enumFromInt(method.value), std.StringHashMap(RouteFn).init(allocator));
    }

    return Self{
        .routes = routes,
        .file_servers = std.StringHashMap([]const u8).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var it = self.routes.valueIterator();
    while (it.next()) |hash_map| {
        hash_map.deinit();
    }

    self.routes.deinit();
    self.file_servers.deinit();
}

pub fn addRoute(self: *Self, method: std.http.Method, url: []const u8, callback: RouteFn) !void {
    if (self.routes.getEntry(method)) |routes_for_method| {
        try routes_for_method.value_ptr.*.put(url, callback);
    } else {
        unreachable;
    }
}

pub fn addFileServer(self: *Self, prefix: []const u8, directory: []const u8) !void {
    try self.file_servers.put(prefix, directory);
}

pub fn dispatch(self: Self, view: *View, request: Request) !std.http.Status {
    const serve_status = try self.handleServe(view, request);
    if (serve_status != std.http.Status.not_found) {
        return serve_status;
    }

    const route_status = try self.handleRoute(view, request);
    if (route_status != std.http.Status.not_found) {
        return route_status;
    }

    try view.respondHtmlSlice("<html><body>404</body></html>");
    return std.http.Status.not_found;
}

fn handleServe(self: Self, view: *View, request: Request) !std.http.Status {
    var cwd = std.fs.cwd();

    var it = self.file_servers.iterator();
    while (it.next()) |file_server| {
        const prefix = file_server.key_ptr.*;
        const directory_path = file_server.value_ptr.*;

        if (std.mem.startsWith(u8, request.target, prefix)) {
            var directory = cwd.openDir(directory_path, .{}) catch return std.http.Status.not_found;
            defer directory.close();

            const sub_path = request.target[(prefix.len)..];

            var file = directory.openFile(sub_path, .{}) catch return std.http.Status.not_found;
            defer file.close();

            try view.respondFileContents(file, "text/plain");
            return std.http.Status.ok;
        }
    }

    return std.http.Status.not_found;
}

fn handleRoute(self: Self, view: *View, request: Request) !std.http.Status {
    if (self.routes.get(request.method)) |routes_for_method| {
        if (routes_for_method.get(request.target)) |route| {
            return try route(view, request);
        }
    }

    return std.http.Status.not_found;
}

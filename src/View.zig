const std = @import("std");
const mustache = @import("mustache");

const Self = @This();

const output_buffer_capacity = 16 * 1024 * 1024;

allocator: std.mem.Allocator,
target: *std.http.Server.Response,
output_buffer: std.io.FixedBufferStream([]u8),
content_type: []const u8,

pub fn init(allocator: std.mem.Allocator) !Self {
    return Self{
        .allocator = allocator,
        .target = undefined,
        .output_buffer = std.io.fixedBufferStream(try allocator.alloc(u8, output_buffer_capacity)),
        .content_type = "",
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.output_buffer.buffer);
}

pub fn respondHtml(self: *Self, path: []const u8) !void {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    try self.respondFileContents(file, "text/html");
}

pub fn respondHtmlSlice(self: *Self, html: []const u8) !void {
    try self.output_buffer.writer().writeAll(html);
    self.content_type = "text/html";
}

pub fn respondJson(self: *Self, value: anytype) !void {
    const json = try std.json.stringifyAlloc(self.allocator, value);
    defer self.allocator.free(json);

    try self.output_buffer.writer().writeAll(json);
    self.content_type = "application/json";
}

pub fn respondFileContents(self: *Self, file: std.fs.File, content_type: []const u8) !void {
    const contents = try file.readToEndAlloc(self.allocator, output_buffer_capacity);
    defer self.allocator.free(contents);

    try self.output_buffer.writer().writeAll(contents);
    self.content_type = content_type;
}

pub fn respondTemplate(self: *Self, path: []const u8, data: anytype) !void {
    const absolute_path = try std.fs.cwd().realpathAlloc(self.allocator, path);
    defer self.allocator.free(absolute_path);

    const json_text = try std.json.stringifyAlloc(self.allocator, data, .{});
    defer self.allocator.free(json_text);

    var json = try std.json.parseFromSlice(std.json.Value, self.allocator, json_text, .{});
    defer json.deinit();

    try mustache.renderFile(self.allocator, absolute_path, json.value, self.output_buffer.writer());
    self.content_type = "text/html";
}

pub fn flush(self: *Self, status: std.http.Status) !usize {
    const output = self.output_buffer.getWritten();
    defer self.output_buffer.reset();

    self.target.status = status;
    self.target.transfer_encoding = .{ .content_length = output.len };
    try self.target.headers.append("content-type", self.content_type);
    try self.target.do();
    try self.target.writeAll(output);
    try self.target.finish();

    return output.len;
}

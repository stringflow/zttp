const std = @import("std");
const zttp = @import("zttp");

const TodoList = struct {
    allocator: std.mem.Allocator,
    backing_list: std.ArrayList([]const u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .backing_list = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.backing_list.items) |text| {
            self.allocator.free(text);
        }

        self.backing_list.deinit();
    }

    pub fn append(self: *Self, text: []const u8) !void {
        const copy = try self.allocator.alloc(u8, text.len);
        @memcpy(copy, text);

        try self.backing_list.append(copy);
    }

    pub fn remove(self: *Self, index: usize) void {
        if (index > self.backing_list.items.len) {
            return;
        }

        const string = self.backing_list.orderedRemove(index);
        self.allocator.free(string);
    }
};

var todos: TodoList = undefined;

fn indexAction(view: *zttp.View, request: zttp.Request) !std.http.Status {
    _ = request;

    try view.respondHtml("examples/todo-app/templates/index.html");
    return std.http.Status.ok;
}

fn todosAction(view: *zttp.View, request: zttp.Request) !std.http.Status {
    _ = request;

    for (todos.backing_list.items, 0..) |text, index| {
        try view.respondTemplate("examples/todo-app/templates/fragments/todo.html", .{ .text = text, .index = index });
    }

    return std.http.Status.ok;
}

fn addTodoAction(view: *zttp.View, request: zttp.Request) !std.http.Status {
    if (request.post_parameters.get("todoText")) |todo| {
        try todos.append(todo);
    }

    return todosAction(view, request);
}

fn removeTodoAction(view: *zttp.View, request: zttp.Request) !std.http.Status {
    if (request.post_parameters.get("id")) |id_string| {
        const id = try std.fmt.parseInt(usize, id_string, 10);
        todos.remove(id);
    }

    return todosAction(view, request);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    todos = TodoList.init(allocator);
    defer todos.deinit();

    var router = try zttp.Router.init(allocator);
    defer router.deinit();

    try router.addRoute(std.http.Method.GET, "/", indexAction);
    try router.addRoute(std.http.Method.GET, "/index", indexAction);
    try router.addRoute(std.http.Method.GET, "/todos", todosAction);
    try router.addRoute(std.http.Method.POST, "/addTodo", addTodoAction);
    try router.addRoute(std.http.Method.POST, "/removeTodo", removeTodoAction);

    var server = try zttp.Server.init(router, allocator);
    defer server.deinit();

    try server.listenBlocking("127.0.0.1", 3000);
}

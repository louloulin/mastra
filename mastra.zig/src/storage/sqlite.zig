//! SQLite 数据库集成
//!
//! 提供：
//! - 数据库连接管理
//! - SQL 查询执行
//! - 事务支持
//! - 连接池
//! - 迁移支持

const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

/// SQLite 错误类型
pub const SQLiteError = error{
    DatabaseError,
    ConnectionFailed,
    QueryFailed,
    PrepareStatementFailed,
    BindParameterFailed,
    ExecutionFailed,
    NoMoreRows,
    InvalidColumnIndex,
    InvalidColumnType,
    TransactionFailed,
    MigrationFailed,
};

/// SQLite 数据类型
pub const SQLiteValue = union(enum) {
    null_value,
    integer: i64,
    real: f64,
    text: []const u8,
    blob: []const u8,

    pub fn fromSQLite(stmt: *c.sqlite3_stmt, column: c_int) SQLiteValue {
        const column_type = c.sqlite3_column_type(stmt, column);
        return switch (column_type) {
            c.SQLITE_NULL => .null_value,
            c.SQLITE_INTEGER => .{ .integer = c.sqlite3_column_int64(stmt, column) },
            c.SQLITE_FLOAT => .{ .real = c.sqlite3_column_double(stmt, column) },
            c.SQLITE_TEXT => .{ .text = std.mem.span(c.sqlite3_column_text(stmt, column)) },
            c.SQLITE_BLOB => blk: {
                const blob_ptr = c.sqlite3_column_blob(stmt, column);
                const blob_size = c.sqlite3_column_bytes(stmt, column);
                const blob_data = @as([*]const u8, @ptrCast(blob_ptr))[0..@intCast(blob_size)];
                break :blk .{ .blob = blob_data };
            },
            else => .null_value,
        };
    }
};

/// SQLite 查询结果行
pub const SQLiteRow = struct {
    values: []SQLiteValue,
    column_names: [][]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *SQLiteRow) void {
        for (self.values) |value| {
            switch (value) {
                .text => |text| self.allocator.free(text),
                .blob => |blob| self.allocator.free(blob),
                else => {},
            }
        }
        self.allocator.free(self.values);
        
        for (self.column_names) |name| {
            self.allocator.free(name);
        }
        self.allocator.free(self.column_names);
    }

    pub fn getValue(self: *const SQLiteRow, column_name: []const u8) ?SQLiteValue {
        for (self.column_names, 0..) |name, i| {
            if (std.mem.eql(u8, name, column_name)) {
                return self.values[i];
            }
        }
        return null;
    }

    pub fn getValueByIndex(self: *const SQLiteRow, index: usize) ?SQLiteValue {
        if (index >= self.values.len) return null;
        return self.values[index];
    }
};

/// SQLite 查询结果
pub const SQLiteResult = struct {
    rows: []SQLiteRow,
    affected_rows: i64,
    last_insert_id: i64,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *SQLiteResult) void {
        for (self.rows) |*row| {
            row.deinit();
        }
        self.allocator.free(self.rows);
    }
};

/// SQLite 连接
pub const SQLiteConnection = struct {
    db: *c.sqlite3,
    allocator: std.mem.Allocator,
    in_transaction: bool,

    const Self = @This();

    /// 打开数据库连接
    pub fn open(allocator: std.mem.Allocator, path: []const u8) SQLiteError!Self {
        var db: ?*c.sqlite3 = null;
        const path_cstr = try allocator.dupeZ(u8, path);
        defer allocator.free(path_cstr);

        const result = c.sqlite3_open(path_cstr.ptr, &db);
        if (result != c.SQLITE_OK) {
            if (db) |d| {
                _ = c.sqlite3_close(d);
            }
            return SQLiteError.ConnectionFailed;
        }

        return Self{
            .db = db.?,
            .allocator = allocator,
            .in_transaction = false,
        };
    }

    /// 关闭数据库连接
    pub fn close(self: *Self) void {
        _ = c.sqlite3_close(self.db);
    }

    /// 执行 SQL 查询
    pub fn execute(self: *Self, sql: []const u8, params: ?[]const SQLiteValue) SQLiteError!SQLiteResult {
        const sql_cstr = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_cstr);

        var stmt: ?*c.sqlite3_stmt = null;
        var result = c.sqlite3_prepare_v2(self.db, sql_cstr.ptr, -1, &stmt, null);
        if (result != c.SQLITE_OK) {
            return SQLiteError.PrepareStatementFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);

        // 绑定参数
        if (params) |param_values| {
            for (param_values, 0..) |param, i| {
                const param_index: c_int = @intCast(i + 1);
                result = switch (param) {
                    .null_value => c.sqlite3_bind_null(stmt, param_index),
                    .integer => |val| c.sqlite3_bind_int64(stmt, param_index, val),
                    .real => |val| c.sqlite3_bind_double(stmt, param_index, val),
                    .text => |val| blk: {
                        const text_cstr = try self.allocator.dupeZ(u8, val);
                        defer self.allocator.free(text_cstr);
                        break :blk c.sqlite3_bind_text(stmt, param_index, text_cstr.ptr, -1, c.SQLITE_TRANSIENT);
                    },
                    .blob => |val| c.sqlite3_bind_blob(stmt, param_index, val.ptr, @intCast(val.len), c.SQLITE_TRANSIENT),
                };

                if (result != c.SQLITE_OK) {
                    return SQLiteError.BindParameterFailed;
                }
            }
        }

        // 执行查询并收集结果
        var rows = std.ArrayList(SQLiteRow).init(self.allocator);
        defer rows.deinit();

        const column_count = c.sqlite3_column_count(stmt);
        var column_names = try self.allocator.alloc([]const u8, @intCast(column_count));
        
        // 获取列名
        for (0..@intCast(column_count)) |i| {
            const name_ptr = c.sqlite3_column_name(stmt, @intCast(i));
            column_names[i] = try self.allocator.dupe(u8, std.mem.span(name_ptr));
        }

        while (true) {
            result = c.sqlite3_step(stmt);
            if (result == c.SQLITE_DONE) break;
            if (result != c.SQLITE_ROW) {
                // 清理列名
                for (column_names) |name| {
                    self.allocator.free(name);
                }
                self.allocator.free(column_names);
                return SQLiteError.ExecutionFailed;
            }

            // 读取行数据
            var row_values = try self.allocator.alloc(SQLiteValue, @intCast(column_count));
            for (0..@intCast(column_count)) |i| {
                row_values[i] = SQLiteValue.fromSQLite(stmt, @intCast(i));
                
                // 复制字符串和 blob 数据
                switch (row_values[i]) {
                    .text => |text| {
                        row_values[i] = .{ .text = try self.allocator.dupe(u8, text) };
                    },
                    .blob => |blob| {
                        row_values[i] = .{ .blob = try self.allocator.dupe(u8, blob) };
                    },
                    else => {},
                }
            }

            // 复制列名
            var row_column_names = try self.allocator.alloc([]const u8, column_names.len);
            for (column_names, 0..) |name, i| {
                row_column_names[i] = try self.allocator.dupe(u8, name);
            }

            try rows.append(SQLiteRow{
                .values = row_values,
                .column_names = row_column_names,
                .allocator = self.allocator,
            });
        }

        // 清理列名
        for (column_names) |name| {
            self.allocator.free(name);
        }
        self.allocator.free(column_names);

        return SQLiteResult{
            .rows = try rows.toOwnedSlice(),
            .affected_rows = c.sqlite3_changes(self.db),
            .last_insert_id = c.sqlite3_last_insert_rowid(self.db),
            .allocator = self.allocator,
        };
    }

    /// 开始事务
    pub fn beginTransaction(self: *Self) SQLiteError!void {
        if (self.in_transaction) return;
        
        var result = self.execute("BEGIN TRANSACTION", null) catch return SQLiteError.TransactionFailed;
        result.deinit();
        self.in_transaction = true;
    }

    /// 提交事务
    pub fn commitTransaction(self: *Self) SQLiteError!void {
        if (!self.in_transaction) return;
        
        var result = self.execute("COMMIT", null) catch return SQLiteError.TransactionFailed;
        result.deinit();
        self.in_transaction = false;
    }

    /// 回滚事务
    pub fn rollbackTransaction(self: *Self) SQLiteError!void {
        if (!self.in_transaction) return;
        
        var result = self.execute("ROLLBACK", null) catch return SQLiteError.TransactionFailed;
        result.deinit();
        self.in_transaction = false;
    }

    /// 获取最后的错误消息
    pub fn getLastError(self: *const Self) []const u8 {
        return std.mem.span(c.sqlite3_errmsg(self.db));
    }
};

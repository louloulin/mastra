const std = @import("std");

/// Document types supported by RAG system
pub const DocumentType = enum {
    text,
    markdown,
    pdf,
    html,
    json,
    csv,

    pub fn fromExtension(extension: []const u8) DocumentType {
        if (std.mem.eql(u8, extension, ".txt")) return .text;
        if (std.mem.eql(u8, extension, ".md")) return .markdown;
        if (std.mem.eql(u8, extension, ".pdf")) return .pdf;
        if (std.mem.eql(u8, extension, ".html") or std.mem.eql(u8, extension, ".htm")) return .html;
        if (std.mem.eql(u8, extension, ".json")) return .json;
        if (std.mem.eql(u8, extension, ".csv")) return .csv;
        return .text; // default
    }
};

/// Document metadata
pub const DocumentMetadata = struct {
    id: []const u8,
    title: ?[]const u8 = null,
    author: ?[]const u8 = null,
    created_at: i64,
    updated_at: i64,
    source: ?[]const u8 = null,
    tags: [][]const u8 = &[_][]const u8{},
    language: []const u8 = "en",
    size: usize = 0,
    checksum: ?[]const u8 = null,
};

/// Document chunk for vector storage
pub const DocumentChunk = struct {
    id: []const u8,
    document_id: []const u8,
    content: []const u8,
    start_offset: usize,
    end_offset: usize,
    chunk_index: usize,
    metadata: std.json.Value,
    embedding: ?[]f32 = null,

    pub fn deinit(self: *DocumentChunk, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.document_id);
        allocator.free(self.content);
        if (self.embedding) |embedding| {
            allocator.free(embedding);
        }
        // 释放 JSON 对象
        if (self.metadata == .object) {
            self.metadata.object.deinit();
        }
    }
};

/// Document processing configuration
pub const DocumentConfig = struct {
    chunk_size: usize = 1000,
    chunk_overlap: usize = 200,
    min_chunk_size: usize = 100,
    max_chunk_size: usize = 2000,
    preserve_structure: bool = true,
    extract_metadata: bool = true,
    language_detection: bool = true,
};

/// Document processor
pub const DocumentProcessor = struct {
    allocator: std.mem.Allocator,
    config: DocumentConfig,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: DocumentConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn processDocument(self: *Self, content: []const u8, doc_type: DocumentType, metadata: DocumentMetadata) ![]DocumentChunk {
        // Extract text content based on document type
        const text_content = try self.extractText(content, doc_type);
        defer self.allocator.free(text_content);

        // Split into chunks
        const chunks = try self.chunkText(text_content, metadata);

        return chunks;
    }

    fn extractText(self: *Self, content: []const u8, doc_type: DocumentType) ![]const u8 {
        switch (doc_type) {
            .text => return try self.allocator.dupe(u8, content),
            .markdown => return try self.extractMarkdownText(content),
            .html => return try self.extractHtmlText(content),
            .json => return try self.extractJsonText(content),
            .csv => return try self.extractCsvText(content),
            .pdf => return try self.extractPdfText(content),
        }
    }

    fn extractMarkdownText(self: *Self, content: []const u8) ![]const u8 {
        // Simple markdown text extraction - remove headers, links, etc.
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");

            // Skip empty lines and headers
            if (trimmed.len == 0 or trimmed[0] == '#') {
                continue;
            }

            // Remove markdown formatting
            const clean_line = try self.cleanMarkdownLine(trimmed);
            defer self.allocator.free(clean_line);

            try result.appendSlice(clean_line);
            try result.append('\n');
        }

        return try result.toOwnedSlice();
    }

    fn cleanMarkdownLine(self: *Self, line: []const u8) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var i: usize = 0;
        while (i < line.len) {
            const char = line[i];

            // Remove markdown formatting
            if (char == '*' or char == '_' or char == '`') {
                // Skip formatting characters
                i += 1;
                continue;
            }

            // Handle links [text](url)
            if (char == '[') {
                const close_bracket = std.mem.indexOfScalarPos(u8, line, i, ']');
                if (close_bracket) |end| {
                    // Extract link text
                    const link_text = line[i + 1 .. end];
                    try result.appendSlice(link_text);

                    // Skip the URL part
                    if (end + 1 < line.len and line[end + 1] == '(') {
                        const close_paren = std.mem.indexOfScalarPos(u8, line, end + 1, ')');
                        if (close_paren) |url_end| {
                            i = url_end + 1;
                            continue;
                        }
                    }
                    i = end + 1;
                    continue;
                }
            }

            try result.append(char);
            i += 1;
        }

        return try result.toOwnedSlice();
    }

    fn extractHtmlText(self: *Self, content: []const u8) ![]const u8 {
        // Simple HTML text extraction - remove tags
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var in_tag = false;
        var in_script = false;
        var in_style = false;

        var i: usize = 0;
        while (i < content.len) {
            const char = content[i];

            if (char == '<') {
                in_tag = true;

                // Check for script/style tags
                if (i + 7 < content.len and std.mem.eql(u8, content[i .. i + 7], "<script")) {
                    in_script = true;
                }
                if (i + 6 < content.len and std.mem.eql(u8, content[i .. i + 6], "<style")) {
                    in_style = true;
                }
            } else if (char == '>') {
                in_tag = false;

                // Check for closing script/style tags
                if (in_script and i >= 8 and std.mem.eql(u8, content[i - 8 .. i], "/script")) {
                    in_script = false;
                }
                if (in_style and i >= 7 and std.mem.eql(u8, content[i - 7 .. i], "/style")) {
                    in_style = false;
                }
            } else if (!in_tag and !in_script and !in_style) {
                try result.append(char);
            }

            i += 1;
        }

        return try result.toOwnedSlice();
    }

    fn extractJsonText(self: *Self, content: []const u8) ![]const u8 {
        // Extract text values from JSON
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, content, .{}) catch {
            // If JSON parsing fails, return content as-is
            return try self.allocator.dupe(u8, content);
        };
        defer parsed.deinit();

        try self.extractJsonValues(parsed.value, &result);

        return try result.toOwnedSlice();
    }

    fn extractJsonValues(self: *Self, value: std.json.Value, result: *std.ArrayList(u8)) !void {
        switch (value) {
            .string => |s| {
                try result.appendSlice(s);
                try result.append(' ');
            },
            .object => |obj| {
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    try self.extractJsonValues(entry.value_ptr.*, result);
                }
            },
            .array => |arr| {
                for (arr.items) |item| {
                    try self.extractJsonValues(item, result);
                }
            },
            else => {},
        }
    }

    fn extractCsvText(self: *Self, content: []const u8) ![]const u8 {
        // Extract text from CSV, joining cells with spaces
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            var cells = std.mem.splitScalar(u8, line, ',');
            while (cells.next()) |cell| {
                const trimmed = std.mem.trim(u8, cell, " \t\r\"");
                if (trimmed.len > 0) {
                    try result.appendSlice(trimmed);
                    try result.append(' ');
                }
            }
            try result.append('\n');
        }

        return try result.toOwnedSlice();
    }

    fn extractPdfText(self: *Self, content: []const u8) ![]const u8 {
        // Placeholder for PDF text extraction
        // In a real implementation, you would use a PDF library
        _ = content;
        const placeholder = "PDF text extraction not implemented";
        return try self.allocator.dupe(u8, placeholder);
    }

    fn chunkText(self: *Self, text: []const u8, metadata: DocumentMetadata) ![]DocumentChunk {
        var chunks = std.ArrayList(DocumentChunk).init(self.allocator);
        defer chunks.deinit();

        var start: usize = 0;
        var chunk_index: usize = 0;

        while (start < text.len) {
            const end = @min(start + self.config.chunk_size, text.len);

            // Try to break at word boundary
            var actual_end = end;
            if (end < text.len) {
                // Look for space or newline within overlap distance
                var i = end;
                const min_boundary = if (start + self.config.chunk_size > self.config.chunk_overlap)
                    start + self.config.chunk_size - self.config.chunk_overlap
                else
                    start;
                while (i > min_boundary and i > start) {
                    if (text[i] == ' ' or text[i] == '\n' or text[i] == '\t') {
                        actual_end = i;
                        break;
                    }
                    i -= 1;
                }
            }

            const chunk_content = text[start..actual_end];

            // Skip chunks that are too small
            if (chunk_content.len < self.config.min_chunk_size and actual_end < text.len) {
                start = actual_end;
                continue;
            }

            const chunk_id = try std.fmt.allocPrint(self.allocator, "{s}_chunk_{d}", .{ metadata.id, chunk_index });
            const doc_id = try self.allocator.dupe(u8, metadata.id);
            const content_copy = try self.allocator.dupe(u8, chunk_content);

            var chunk_metadata = std.json.ObjectMap.init(self.allocator);
            try chunk_metadata.put("chunk_index", std.json.Value{ .integer = @intCast(chunk_index) });
            try chunk_metadata.put("start_offset", std.json.Value{ .integer = @intCast(start) });
            try chunk_metadata.put("end_offset", std.json.Value{ .integer = @intCast(actual_end) });

            const chunk = DocumentChunk{
                .id = chunk_id,
                .document_id = doc_id,
                .content = content_copy,
                .start_offset = start,
                .end_offset = actual_end,
                .chunk_index = chunk_index,
                .metadata = std.json.Value{ .object = chunk_metadata },
                .embedding = null,
            };

            try chunks.append(chunk);

            // Move to next chunk with overlap
            if (actual_end >= text.len) break;

            const next_start = if (actual_end > self.config.chunk_overlap)
                actual_end - self.config.chunk_overlap
            else
                actual_end;

            // Ensure we make progress to avoid infinite loop
            if (next_start <= start) {
                start = start + 1;
            } else {
                start = next_start;
            }

            chunk_index += 1;

            // Safety check to prevent infinite loops
            if (chunk_index > 1000) {
                std.log.warn("Too many chunks generated, stopping at {d}", .{chunk_index});
                break;
            }
        }

        return try chunks.toOwnedSlice();
    }
};

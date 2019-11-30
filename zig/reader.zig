const std = @import("std");
const Allocator = std.mem.Allocator;

const types = @import("types.zig");
const MalType = types.MalType;
const SequenceType = types.SequenceType;

pub const Token = []const u8;

pub const Reader = struct {
    tokens: []Token,
    position: usize,

    const Self = @This();

    pub fn next(self: *Self) ?Token {
        if (self.tokens.len < 1) return null;
        if (self.position >= self.tokens.len) return null;
        self.position += 1;
        return self.tokens[self.position - 1];
    }

    pub fn peek(self: *Self) ?Token {
        if (self.tokens.len < 1) return null;
        if (self.position >= self.tokens.len) return null;
        return self.tokens[self.position];
    }
};

/// Reads a string into internal mal representation
pub fn read_str(s: []const u8, alloc: *Allocator) !MalType {
    const tokens = try tokenize(s, alloc);
    defer alloc.free(tokens);

    const reader = &Reader{
        .tokens = tokens,
        .position = 0,
    };

    return try read_form(reader, alloc);
}

pub const TokenizeError = error{ UnfinishedQuote };

/// Tokenizes a raw byte slice
pub fn tokenize(s: []const u8, alloc: *Allocator) ![]Token {
    var result = std.ArrayList(Token).init(alloc);

    const State = enum {
        TopLevel,
        SeenTilde,
        DoubleQuotedString,
        DoubleQuotedStringEscaped,
        NonSpecialSequence,
    };
    var state = State.TopLevel;
    var begin_string: usize = 0;
    var begin_nonspecial: usize = 0;

    for (s) |c, i| {
        switch (state) {
            .TopLevel => switch (c) {
                // Whitespace and commas
                ',', 0x09, 0x0A, 0x0D, 0x20, => continue,

                // Begin of ~@ (maybe)
                '~' => state = State.SeenTilde,

                // Special characters
                '[', ']', '{', '}', '(', ')', '\'', '`', '^', '@' => 
                    try result.append(s[i..i+1]),

                // Double-quoted string
                '"' => {
                    begin_string = i;
                    state = State.DoubleQuotedString;
                },

                // Comment
                ';' => break,

                // All other characters
                else => {
                    begin_nonspecial = i;
                    state = State.NonSpecialSequence;
                },
            },
            .SeenTilde => switch (c) {
                // Special two-character sequence encountered
                '@' => {
                    try result.append("~@");
                    state = State.TopLevel;
                },

                // Maybe a two-character sequence now?
                '~' => try result.append("~"),

                // Whitespace and commas
                ',', 0x09, 0x0A, 0x0D, 0x20, => {
                    try result.append("~");
                    state = State.TopLevel;
                },

                // Special characters
                '[', ']', '{', '}', '(', ')', '\'', '`', '^', => {
                    try result.append("~");
                    try result.append(s[i..i+1]);
                    state = State.TopLevel;
                },

                // Double-quoted string
                '"' => {
                    try result.append("~");
                    begin_string = i;
                    state = State.DoubleQuotedString;
                },

                // Comment
                ';' => {
                    try result.append("~");
                    break;
                },

                // All other characters
                else => {
                    try result.append("~");
                    begin_nonspecial = i;
                    state = State.NonSpecialSequence;
                },
            },
            .DoubleQuotedString => switch (c) {
                // End of string
                '"' => {
                    try result.append(s[begin_string..i+1]);
                    state = State.TopLevel;
                },

                // Escape
                '\\' => state = State.DoubleQuotedStringEscaped,

                // Any other character
                else => continue,
            },
            .DoubleQuotedStringEscaped => state = State.DoubleQuotedString,
            .NonSpecialSequence => switch (c) {
                // Whitespace and commas
                ',', 0x09, 0x0A, 0x0D, 0x20 => {
                    try result.append(s[begin_nonspecial..i]);
                    state = State.TopLevel;
                },

                // Special characters
                '[', ']', '{', '}', '(', ')', '\'', '`', '^', '@' => {
                    try result.append(s[begin_nonspecial..i]);
                    try result.append(s[i..i+1]);
                    state = State.TopLevel;
                },

                // Begin of ~@ (maybe)
                '~' => {
                    try result.append(s[begin_nonspecial..i]);
                    state = State.SeenTilde;
                },

                // Double-quoted string
                '"' => {
                    try result.append(s[begin_nonspecial..i]);
                    begin_string = i;
                    state = State.DoubleQuotedString;
                },

                // Comment
                ';' => {
                    try result.append(s[begin_nonspecial..i]);
                    break;
                },

                // Any other character
                else => continue,
            }
        }
    }

    // Check end state
    switch (state) {
        .DoubleQuotedString, .DoubleQuotedStringEscaped => return error.UnfinishedQuote,
        .SeenTilde => try result.append("~"),
        .NonSpecialSequence => try result.append(s[begin_nonspecial..]),
        else => {},
    }

    return result.toOwnedSlice();
}

pub const ReadError = std.mem.Allocator.Error || error{
    UnbalancedParenthesis,
    Underflow,
    KeyIsNotString,
    UnevenHashMap,
};

fn specialList(r: *Reader, alloc: *Allocator, name: []const u8) ReadError!MalType {
    var result = std.ArrayList(MalType).init(alloc);

    // If there is nothing left to read, return error
    if (r.peek()) |_| {} else return error.Underflow;
    const itm = try read_form(r, alloc);

    try result.append(MalType{ .MalSymbol = name });
    try result.append(itm);

    return MalType{ .MalList = result };
}

fn specialListTwo(r: *Reader, alloc: *Allocator, name: []const u8) ReadError!MalType {
    var result = std.ArrayList(MalType).init(alloc);

    // If there is nothing left to read, return error
    if (r.peek()) |_| {} else return error.Underflow;
    const meta = try read_form(r, alloc);

    // Same here
    if (r.peek()) |_| {} else return error.Underflow;
    const itm = try read_form(r, alloc);

    try result.append(MalType{ .MalSymbol = name });
    try result.append(itm);
    try result.append(meta);

    return MalType{ .MalList = result };
}

/// Reads the next full piece
pub fn read_form(r: *Reader, alloc: *Allocator) ReadError!MalType {
    if (r.peek()) |tok| {
        if (std.mem.eql(u8, tok, "(")) {
            _ = r.next();
            return try read_list(r, alloc, SequenceType.List);
        } else if (std.mem.eql(u8, tok, "[")) {
            _ = r.next();
            return try read_list(r, alloc, SequenceType.Vector);
        } else if (std.mem.eql(u8, tok, "{")) {
            _ = r.next();
            return try read_map(r, alloc);
        } else if (std.mem.eql(u8, tok, ")")) {
            return error.UnbalancedParenthesis;
        } else if (std.mem.eql(u8, tok, "]")) {
            return error.UnbalancedParenthesis;
        } else if (std.mem.eql(u8, tok, "}")) {
            return error.UnbalancedParenthesis;
        } else if (std.mem.eql(u8, tok, "'")) {
            _ = r.next();
            return try specialList(r, alloc, "quote");
        } else if (std.mem.eql(u8, tok, "`")) {
            _ = r.next();
            return try specialList(r, alloc, "quasiquote");
        } else if (std.mem.eql(u8, tok, "~")) {
            _ = r.next();
            return try specialList(r, alloc, "unquote");
        } else if (std.mem.eql(u8, tok, "~@")) {
            _ = r.next();
            return try specialList(r, alloc, "splice-unquote");
        } else if (std.mem.eql(u8, tok, "@")) {
            _ = r.next();
            return try specialList(r, alloc, "deref");
        } else if (std.mem.eql(u8, tok, "^")) {
            _ = r.next();
            return try specialListTwo(r, alloc, "with-meta");
        } else {
            return read_atom(r, alloc);
        }
    } else {
        return MalType{ .MalNil = {} };
    }
}

/// Reads a hash map starting with the first key
fn read_map(r: *Reader, alloc: *Allocator) ReadError!MalType {
    var result = std.StringHashMap(MalType).init(alloc);

    // Reading in two stages: First read key, then read value
    var key: ?[]const u8 = null;

    while (true) {
        if (r.peek()) |tok| {
            if (std.mem.eql(u8, "}", tok)) {
                _ = r.next();
                break;
            } else {
                if (key) |ky| {
                    // Key was already read
                    const value = try read_form(r, alloc);

                    _ = try result.put(ky, value);
                    key = null;
                } else {
                    switch (try read_form(r, alloc)) {
                        .MalString => |s| key = s,
                        else => return error.KeyIsNotString,
                    }
                }
            }
        } else {
            return error.UnbalancedParenthesis;
        }
    }

    // If a key is left over at the end, there were an odd
    // number of elements here
    if (key) |_| return error.UnevenHashMap;

    return MalType{ .MalHashMap = result };
}

/// Reads a list or a vector starting with the first element
fn read_list(r: *Reader, alloc: *Allocator, seq_type: SequenceType) ReadError!MalType {
    var result = std.ArrayList(MalType).init(alloc);

    while (true) {
        if (r.peek()) |tok| {
            if (std.mem.eql(u8, seq_type.endToken(), tok)) {
                _ = r.next();
                break;
            } else {
                try result.append(try read_form(r, alloc));
            }
        } else {
            return error.UnbalancedParenthesis;
        }
    }

    return switch(seq_type) {
       .List => MalType{ .MalList = result },
       .Vector => MalType{ .MalVector = result },
    };
}

/// Unescapes a string
pub fn unescape(s: []const u8, alloc: *Allocator) ![]const u8 {
    var result = std.ArrayList(u8).init(alloc);
    
    // Remove the double quotes
    // That means we can safely assume that len >= 2
    try result.appendSlice(s[1..s.len-1]); 

    if (result.count() < 1)
        return result.toSliceConst();

    // Assumes len >= 1
    var i: usize = 0;
    while (i < result.count() - 1) : (i += 1) {
        if (result.at(i) == '\\') {
            switch (result.at(i + 1)) {
                'n' => {
                    result.set(i, '\n');
                    _ = result.orderedRemove(i + 1);
                },
                '"' => {
                    result.set(i, '"');
                    _ = result.orderedRemove(i + 1);
                },
                '\\' => {
                    _ = result.orderedRemove(i + 1);
                },
                else => continue,
            }
        }
    }

    return result.toSliceConst();
}

/// Reads a mal atom
fn read_atom(r: *Reader, alloc: *Allocator) !MalType {
    if (r.next()) |tok| {
        if (std.mem.eql(u8, tok, "nil"))
            return MalType{ .MalNil = {} };
        if (std.mem.eql(u8, tok, "true"))
            return MalType{ .MalBoolean = true };
        if (std.mem.eql(u8, tok, "false"))
            return MalType{ .MalBoolean = false };

        // A not-cool hack to prevent "+" and "-"
        // from being parsed as integers
        if (std.mem.eql(u8, tok, "+"))
            return MalType{ .MalSymbol = tok };
        if (std.mem.eql(u8, tok, "-"))
            return MalType{ .MalSymbol = tok };

        if (std.fmt.parseInt(i64, tok, 10)) |x| {
            return MalType{ .MalInteger = x };
        } else |err| {
            if (std.mem.startsWith(u8, tok, "\"")) {
                // Strings
                return MalType{ .MalString = try unescape(tok, alloc) };
            } else if (std.mem.startsWith(u8, tok, ":")) {
                // Keywords
                return MalType{
                    .MalString = try std.fmt.allocPrint(alloc, "\u{29e}{}", tok[1..])
                };
            } else {
                // Symbols
                return MalType{ .MalSymbol = tok };
            }
        }
    } else {
        return MalType{ .MalNil = {} };
    }
}

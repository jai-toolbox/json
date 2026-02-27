#scope_module

Parser_State :: struct {
    data          : string;
    offset        : int;
    line          : int;
    column        : int;
    has_error     : bool;
    error_message : string;
}

#scope_module

// we use #scope_module so parse.jai can call these,
// but they're not visible to code that imports the module.

make_parser :: (input: string) -> Parser_State {
    ps: Parser_State;
    ps.data = input;
    ps.line = 1;
    ps.column = 1;
    return ps;
}

parser_remaining :: inline (ps: *Parser_State) -> int {
    return ps.data.count - ps.offset;
}

parser_peek :: inline (ps: *Parser_State) -> u8 {
    if ps.offset >= ps.data.count return 0;
    return ps.data[ps.offset];
}

parser_peek_at :: inline (ps: *Parser_State, ahead: int) -> u8 {
    idx := ps.offset + ahead;
    if idx >= ps.data.count return 0;
    return ps.data[idx];
}

parser_advance :: inline (ps: *Parser_State) -> u8 {
    if ps.offset >= ps.data.count return 0;
    c := ps.data[ps.offset];
    ps.offset += 1;
    if c == #char "\n" { ps.line += 1; ps.column = 1; }
    else               { ps.column += 1; }
    return c;
}

parser_advance_n :: (ps: *Parser_State, n: int) {
    for 0..n-1 parser_advance(ps);
}

parser_set_error :: (ps: *Parser_State, msg: string) {
    if !ps.has_error {
        ps.has_error = true;
        ps.error_message = msg;
    }
}

parser_set_error_fmt :: (ps: *Parser_State, fmt: string, args: .. Any) {
    if !ps.has_error {
        ps.has_error = true;
        ps.error_message = tprint(fmt, ..args);
    }
}

parser_skip_whitespace :: (ps: *Parser_State) {
    while ps.offset < ps.data.count {
        c := ps.data[ps.offset];
        if c != #char " " && c != #char "\t" && c != #char "\n" && c != #char "\r" break;
        parser_advance(ps);
    }
}

parser_match_keyword :: (ps: *Parser_State, keyword: string) -> bool {
    remaining := parser_remaining(ps);
    if remaining < keyword.count return false;
    for 0..keyword.count-1 {
        if ps.data[ps.offset + it] != keyword[it] return false;
    }
    next_idx := ps.offset + keyword.count;
    if next_idx < ps.data.count {
        nc := ps.data[next_idx];
        if (nc >= #char "a" && nc <= #char "z") ||
           (nc >= #char "A" && nc <= #char "Z") ||
           (nc >= #char "0" && nc <= #char "9") ||
           nc == #char "_" return false;
    }
    parser_advance_n(ps, keyword.count);
    return true;
}

// value dispatch

internal_parse_value :: (ps: *Parser_State) -> *Json_Value {
    parser_skip_whitespace(ps);
    if ps.has_error return null;
    if parser_remaining(ps) == 0 {
        parser_set_error(ps, "Unexpected end of input");
        return null;
    }

    c := parser_peek(ps);

    if c == #char "\"" return internal_parse_string_value(ps);
    if c == #char "{"  return internal_parse_object(ps);
    if c == #char "["  return internal_parse_array(ps);
    if c == #char "t" || c == #char "f" return internal_parse_boolean(ps);
    if c == #char "n"  return internal_parse_null(ps);
    if c == #char "-" || (c >= #char "0" && c <= #char "9") return internal_parse_number(ps);

    parser_set_error_fmt(ps, "Unexpected character at line %, column %", ps.line, ps.column);
    return null;
}

// string

internal_parse_string_raw :: (ps: *Parser_State) -> string {
    if parser_peek(ps) != #char "\"" {
        parser_set_error(ps, "Expected '\"' at start of string");
        return "";
    }
    parser_advance(ps);

    // Fast path: scan for simple string (no escapes, no control chars)
    scan := ps.offset;
    simple := true;
    while scan < ps.data.count {
        ch := ps.data[scan];
        if ch == #char "\\" || ch < 0x20 { simple = false; break; }
        if ch == #char "\"" break;
        scan += 1;
    }

    if simple && scan < ps.data.count && ps.data[scan] == #char "\"" {
        src: string;
        src.data = ps.data.data + ps.offset;
        src.count = scan - ps.offset;
        parser_advance_n(ps, scan - ps.offset + 1);
        return copy_string(src);
    }

    // Slow path: escape handling
    builder: String_Builder;
    builder.allocator = temp;

    while parser_remaining(ps) > 0 {
        c := parser_peek(ps);

        if c == #char "\\" {
            parser_advance(ps);
            if parser_remaining(ps) == 0 {
                parser_set_error(ps, "Unexpected end of input in string escape");
                break;
            }
            escaped := parser_peek(ps);
            parser_advance(ps);

            if escaped == {
                case #char "\""; append(*builder, "\"");
                case #char "\\"; append(*builder, "\\");
                case #char "/";  append(*builder, "/");
                case #char "b";  append(*builder, "\x08");
                case #char "f";  append(*builder, "\x0C");
                case #char "n";  append(*builder, "\n");
                case #char "r";  append(*builder, "\r");
                case #char "t";  append(*builder, "\t");
                case #char "u";
                    codepoint := parse_hex4(ps);
                    if codepoint == 0xFFFF_FFFF {
                        parser_set_error(ps, "Invalid \\u escape");
                        break;
                    }
                    if codepoint >= 0xD800 && codepoint <= 0xDBFF {
                        if parser_remaining(ps) >= 2 &&
                           parser_peek(ps) == #char "\\" &&
                           parser_peek_at(ps, 1) == #char "u"
                        {
                            parser_advance(ps);
                            parser_advance(ps);
                            low := parse_hex4(ps);
                            if low >= 0xDC00 && low <= 0xDFFF {
                                codepoint = 0x10000 + ((codepoint - 0xD800) << 10) + (low - 0xDC00);
                            } else {
                                parser_set_error(ps, "Invalid UTF-16 surrogate pair");
                                break;
                            }
                        } else {
                            parser_set_error(ps, "Expected low surrogate after high surrogate");
                            break;
                        }
                    }
                    encode_utf8(*builder, codepoint);

                case;
                    parser_set_error_fmt(ps, "Invalid escape '\\%'", string.{1, *escaped});
                    break;
            }
            continue;
        }

        if c == #char "\"" {
            parser_advance(ps);
            tmp := builder_to_string(*builder);
            return copy_string(tmp);
        }

        if c < 0x20 {
            parser_set_error_fmt(ps, "Unescaped control character in string at line %, column %",
                ps.line, ps.column);
            break;
        }

        parser_advance(ps);
        c_str: string;
        c_str.data = ps.data.data + ps.offset - 1;
        c_str.count = 1;
        append(*builder, c_str);
    }

    if !ps.has_error parser_set_error(ps, "Unterminated string");
    tmp := builder_to_string(*builder);
    return copy_string(tmp);
}

internal_parse_string_value :: (ps: *Parser_State) -> *Json_Value {
    line := ps.line;
    col  := ps.column;
    str  := internal_parse_string_raw(ps);
    if ps.has_error return null;

    val := New(Json_Value);
    val.type = .STRING;
    val.str = str;
    val.source_line = line;
    val.source_column = col;
    return val;
}

// number

internal_parse_number :: (ps: *Parser_State) -> *Json_Value {
    line := ps.line;
    col  := ps.column;
    start_offset := ps.offset;

    if parser_peek(ps) == #char "-" parser_advance(ps);

    if parser_remaining(ps) == 0 {
        parser_set_error(ps, "Unexpected end of input in number");
        return null;
    }

    c := parser_peek(ps);
    if c == #char "0" {
        parser_advance(ps);
        if parser_remaining(ps) > 0 {
            nc := parser_peek(ps);
            if nc >= #char "0" && nc <= #char "9" {
                parser_set_error_fmt(ps, "Leading zeros not allowed at line %, column %", ps.line, ps.column);
                return null;
            }
        }
    } else if c >= #char "1" && c <= #char "9" {
        parser_advance(ps);
        while parser_remaining(ps) > 0 && parser_peek(ps) >= #char "0" && parser_peek(ps) <= #char "9"
            parser_advance(ps);
    } else {
        parser_set_error_fmt(ps, "Invalid number at line %, column %", ps.line, ps.column);
        return null;
    }

    if parser_remaining(ps) > 0 && parser_peek(ps) == #char "." {
        parser_advance(ps);
        if parser_remaining(ps) == 0 || parser_peek(ps) < #char "0" || parser_peek(ps) > #char "9" {
            parser_set_error(ps, "Expected digit after decimal point");
            return null;
        }
        while parser_remaining(ps) > 0 && parser_peek(ps) >= #char "0" && parser_peek(ps) <= #char "9"
            parser_advance(ps);
    }

    if parser_remaining(ps) > 0 && (parser_peek(ps) == #char "e" || parser_peek(ps) == #char "E") {
        parser_advance(ps);
        if parser_remaining(ps) > 0 && (parser_peek(ps) == #char "+" || parser_peek(ps) == #char "-")
            parser_advance(ps);
        if parser_remaining(ps) == 0 || parser_peek(ps) < #char "0" || parser_peek(ps) > #char "9" {
            parser_set_error(ps, "Expected digit in exponent");
            return null;
        }
        while parser_remaining(ps) > 0 && parser_peek(ps) >= #char "0" && parser_peek(ps) <= #char "9"
            parser_advance(ps);
    }

    num_str: string;
    num_str.data = ps.data.data + start_offset;
    num_str.count = ps.offset - start_offset;

    number, success, _ := string_to_float64(num_str);
    if !success {
        parser_set_error_fmt(ps, "Failed to parse number '%'", num_str);
        return null;
    }

    val := New(Json_Value);
    val.type = .NUMBER;
    val.number = number;
    val.source_line = line;
    val.source_column = col;
    return val;
}

// boolean

internal_parse_boolean :: (ps: *Parser_State) -> *Json_Value {
    line := ps.line;
    col  := ps.column;

    if parser_match_keyword(ps, "true") {
        val := New(Json_Value);
        val.type = .BOOLEAN;
        val.boolean = true;
        val.source_line = line;
        val.source_column = col;
        return val;
    }
    if parser_match_keyword(ps, "false") {
        val := New(Json_Value);
        val.type = .BOOLEAN;
        val.boolean = false;
        val.source_line = line;
        val.source_column = col;
        return val;
    }

    parser_set_error_fmt(ps, "Invalid boolean at line %, column %", ps.line, ps.column);
    return null;
}

// null

internal_parse_null :: (ps: *Parser_State) -> *Json_Value {
    line := ps.line;
    col  := ps.column;

    if parser_match_keyword(ps, "null") {
        val := New(Json_Value);
        val.type = .NULL;
        val.source_line = line;
        val.source_column = col;
        return val;
    }

    parser_set_error_fmt(ps, "Invalid null at line %, column %", ps.line, ps.column);
    return null;
}

// array

internal_parse_array :: (ps: *Parser_State) -> *Json_Value {
    line := ps.line;
    col  := ps.column;
    parser_advance(ps);

    val := New(Json_Value);
    val.type = .ARRAY;
    val.source_line = line;
    val.source_column = col;

    parser_skip_whitespace(ps);

    if parser_remaining(ps) > 0 && parser_peek(ps) == #char "]" {
        parser_advance(ps);
        return val;
    }

    while parser_remaining(ps) > 0 && !ps.has_error {
        element := internal_parse_value(ps);
        if ps.has_error return null;
        if element then array_add(*val.array, element);

        parser_skip_whitespace(ps);
        if parser_remaining(ps) == 0 {
            parser_set_error(ps, "Unterminated array");
            return null;
        }

        c := parser_peek(ps);
        if c == #char "]" { parser_advance(ps); return val; }
        if c == #char "," {
            parser_advance(ps);
            parser_skip_whitespace(ps);
            if parser_remaining(ps) > 0 && parser_peek(ps) == #char "]" {
                parser_set_error_fmt(ps, "Trailing comma in array at line %, column %", ps.line, ps.column);
                return null;
            }
        } else {
            parser_set_error_fmt(ps, "Expected ',' or ']' in array at line %, column %", ps.line, ps.column);
            return null;
        }
    }

    if !ps.has_error parser_set_error(ps, "Unterminated array");
    return null;
}

// object

internal_parse_object :: (ps: *Parser_State) -> *Json_Value {
    line := ps.line;
    col  := ps.column;
    parser_advance(ps);

    val := New(Json_Value);
    val.type = .OBJECT;
    val.source_line = line;
    val.source_column = col;

    parser_skip_whitespace(ps);

    if parser_remaining(ps) > 0 && parser_peek(ps) == #char "}" {
        parser_advance(ps);
        return val;
    }

    while parser_remaining(ps) > 0 && !ps.has_error {
        parser_skip_whitespace(ps);

        if parser_remaining(ps) == 0 || parser_peek(ps) != #char "\"" {
            parser_set_error_fmt(ps, "Expected string key at line %, column %", ps.line, ps.column);
            return null;
        }

        key := internal_parse_string_raw(ps);
        if ps.has_error return null;

        for * entry : val.object {
            if entry.key == key {
                parser_set_error_fmt(ps, "Duplicate key '%' at line %, column %", key, ps.line, ps.column);
                return null;
            }
        }

        parser_skip_whitespace(ps);
        if parser_remaining(ps) == 0 || parser_peek(ps) != #char ":" {
            parser_set_error_fmt(ps, "Expected ':' after key at line %, column %", ps.line, ps.column);
            return null;
        }
        parser_advance(ps);
        parser_skip_whitespace(ps);

        value := internal_parse_value(ps);
        if ps.has_error return null;

        entry: Json_Object_Entry;
        entry.key = key;
        entry.value = value;
        array_add(*val.object, entry);

        parser_skip_whitespace(ps);
        if parser_remaining(ps) == 0 {
            parser_set_error(ps, "Unterminated object");
            return null;
        }

        c := parser_peek(ps);
        if c == #char "}" { parser_advance(ps); return val; }
        if c == #char "," {
            parser_advance(ps);
            parser_skip_whitespace(ps);
            if parser_remaining(ps) > 0 && parser_peek(ps) == #char "}" {
                parser_set_error_fmt(ps, "Trailing comma in object at line %, column %", ps.line, ps.column);
                return null;
            }
        } else {
            parser_set_error_fmt(ps, "Expected ',' or '}' at line %, column %", ps.line, ps.column);
            return null;
        }
    }

    if !ps.has_error parser_set_error(ps, "Unterminated object");
    return null;
}


parse_hex4 :: (ps: *Parser_State) -> u32 {
    if parser_remaining(ps) < 4 return 0xFFFF_FFFF;
    result: u32 = 0;
    for 0..3 {
        c := parser_advance(ps);
        digit: u32;
        if      c >= #char "0" && c <= #char "9" digit = cast(u32)(c - #char "0");
        else if c >= #char "a" && c <= #char "f" digit = cast(u32)(c - #char "a" + 10);
        else if c >= #char "A" && c <= #char "F" digit = cast(u32)(c - #char "A" + 10);
        else return 0xFFFF_FFFF;
        result = (result << 4) | digit;
    }
    return result;
}

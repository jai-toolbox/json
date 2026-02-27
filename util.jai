#scope_module

// used by serialize.jai for sort_keys, and by parse_internal.jai for unicode

compare_strings :: (a: string, b: string) -> int {
    min_count := ifx a.count < b.count then a.count else b.count;
    for i : 0..min_count-1 {
        if a[i] < b[i] return -1;
        if a[i] > b[i] return  1;
    }
    if a.count < b.count return -1;
    if a.count > b.count return  1;
    return 0;
}

encode_utf8 :: (builder: *String_Builder, codepoint: u32) {
    buf: [4] u8;
    count: int;
    if codepoint <= 0x7F {
        buf[0] = cast(u8) codepoint;
        count = 1;
    } else if codepoint <= 0x7FF {
        buf[0] = cast(u8)(0xC0 | (codepoint >> 6));
        buf[1] = cast(u8)(0x80 | (codepoint & 0x3F));
        count = 2;
    } else if codepoint <= 0xFFFF {
        buf[0] = cast(u8)(0xE0 | (codepoint >> 12));
        buf[1] = cast(u8)(0x80 | ((codepoint >> 6) & 0x3F));
        buf[2] = cast(u8)(0x80 | (codepoint & 0x3F));
        count = 3;
    } else if codepoint <= 0x10FFFF {
        buf[0] = cast(u8)(0xF0 | (codepoint >> 18));
        buf[1] = cast(u8)(0x80 | ((codepoint >> 12) & 0x3F));
        buf[2] = cast(u8)(0x80 | ((codepoint >> 6) & 0x3F));
        buf[3] = cast(u8)(0x80 | (codepoint & 0x3F));
        count = 4;
    } else {
        buf[0] = 0xEF; buf[1] = 0xBF; buf[2] = 0xBD;
        count = 3;
    }
    s: string;
    s.data = buf.data;
    s.count = count;
    append(builder, s);
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

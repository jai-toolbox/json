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


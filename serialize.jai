json_serialize :: (val: *Json_Value, options: Json_Serialize_Options = .{}) -> string {
    builder: String_Builder;
    internal_serialize(*builder, val, options, 0);
    return builder_to_string(*builder);
}

json_serialize_to_builder :: (builder: *String_Builder, val: *Json_Value, options: Json_Serialize_Options = .{}) {
    internal_serialize(builder, val, options, 0);
}

json_pretty :: (val: *Json_Value) -> string {
    opts: Json_Serialize_Options;
    opts.pretty = true;
    return json_serialize(val, opts);
}

json_print :: (val: *Json_Value, options: Json_Serialize_Options = .{}) {
    s := json_serialize(val, options);
    print("%\n", s);
    free(s);
}

#scope_file

internal_serialize :: (builder: *String_Builder, val: *Json_Value, options: Json_Serialize_Options, depth: int) {
    if val == null { append(builder, "null"); return; }

    if val.type == {
        case .NULL;
            append(builder, "null");

        case .BOOLEAN;
            append(builder, ifx val.boolean then "true" else "false");

        case .NUMBER;
            int_val := cast(s64) val.number;
            if val.number == cast(float64) int_val
                append(builder, tprint("%", int_val));
            else
                append(builder, tprint("%", val.number));

        case .STRING;
            serialize_string(builder, val.str, options.escape_unicode);

        case .ARRAY;
            append(builder, "[");
            if val.array.count > 0 {
                for i : 0..val.array.count-1 {
                    if i > 0 append(builder, ",");
                    if options.pretty { append(builder, "\n"); write_indent(builder, options, depth + 1); }
                    internal_serialize(builder, val.array[i], options, depth + 1);
                }
                if options.pretty { append(builder, "\n"); write_indent(builder, options, depth); }
            }
            append(builder, "]");

        case .OBJECT;
            append(builder, "{");
            count := val.object.count;
            if count > 0 {
                if options.sort_keys {
                    indices := NewArray(count, int, allocator = temp);
                    for i : 0..count-1 indices[i] = i;
                    for i : 1..count-1 {
                        j := i;
                        while j > 0 && compare_strings(val.object[indices[j-1]].key, val.object[indices[j]].key) > 0 {
                            tmp := indices[j]; indices[j] = indices[j-1]; indices[j-1] = tmp;
                            j -= 1;
                        }
                    }
                    for i : 0..count-1 {
                        idx := indices[i];
                        if i > 0 append(builder, ",");
                        if options.pretty { append(builder, "\n"); write_indent(builder, options, depth + 1); }
                        serialize_string(builder, val.object[idx].key, options.escape_unicode);
                        append(builder, ":");
                        if options.pretty append(builder, " ");
                        internal_serialize(builder, val.object[idx].value, options, depth + 1);
                    }
                } else {
                    for i : 0..count-1 {
                        if i > 0 append(builder, ",");
                        if options.pretty { append(builder, "\n"); write_indent(builder, options, depth + 1); }
                        serialize_string(builder, val.object[i].key, options.escape_unicode);
                        append(builder, ":");
                        if options.pretty append(builder, " ");
                        internal_serialize(builder, val.object[i].value, options, depth + 1);
                    }
                }
                if options.pretty { append(builder, "\n"); write_indent(builder, options, depth); }
            }
            append(builder, "}");
    }
}

write_indent :: (builder: *String_Builder, options: Json_Serialize_Options, depth: int) {
    total := depth * options.indent_width;
    for 0..total-1 {
        c_str: string;
        c_str.data = *options.indent_char;
        c_str.count = 1;
        append(builder, c_str);
    }
}

serialize_string :: (builder: *String_Builder, s: string, escape_unicode: bool) {
    append(builder, "\"");
    for i : 0..s.count-1 {
        c := s[i];
        if c == {
            case #char "\""; append(builder, "\\\"");
            case #char "\\"; append(builder, "\\\\");
            case #char "\n"; append(builder, "\\n");
            case #char "\r"; append(builder, "\\r");
            case #char "\t"; append(builder, "\\t");
            case 0x08;       append(builder, "\\b");
            case 0x0C;       append(builder, "\\f");
            case;
                if c < 0x20 {
                    append(builder, tprint("\\u%", formatInt(c, base=16, minimum_digits=4)));
                } else if escape_unicode && c > 0x7F {
                    append(builder, tprint("\\u%", formatInt(c, base=16, minimum_digits=4)));
                } else {
                    c_str: string;
                    c_str.data = s.data + i;
                    c_str.count = 1;
                    append(builder, c_str);
                }
        }
    }
    append(builder, "\"");
}

json_parse :: (input: string) -> *Json_Value {
    result := json_parse_with_result(input);
    return result.value;
}

json_parse_with_result :: (input: string) -> Json_Parse_Result {
    ps := make_parser(input);
    parser_skip_whitespace(*ps);

    result: Json_Parse_Result;

    if parser_remaining(*ps) == 0 {
        result.success = false;
        result.error = .{ message = "Empty input", line = 1, column = 1, offset = 0 };
        return result;
    }

    val := internal_parse_value(*ps);

    if ps.has_error {
        result.success = false;
        result.error = .{
            message = ps.error_message,
            line    = ps.line,
            column  = ps.column,
            offset  = ps.offset
        };
        return result;
    }

    parser_skip_whitespace(*ps);
    if parser_remaining(*ps) > 0 {
        result.success = false;
        result.error = .{
            message = tprint("Unexpected trailing content at line %, column %", ps.line, ps.column),
            line    = ps.line,
            column  = ps.column,
            offset  = ps.offset
        };
        return result;
    }

    result.value = val;
    result.success = true;
    return result;
}

json_free :: (val: *Json_Value) {
    if val == null return;

    if val.type == {
        case .STRING;
            free(val.str);

        case .ARRAY;
            for val.array json_free(it);
            array_free(val.array);

        case .OBJECT;
            for * entry : val.object {
                free(entry.key);
                json_free(entry.value);
            }
            array_free(val.object);
    }

    free(val);
}

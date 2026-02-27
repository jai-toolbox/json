Json_Value_Type :: enum {
    NULL;
    BOOLEAN;
    NUMBER;
    STRING;
    ARRAY;
    OBJECT;
}

Json_Value :: struct {
    type : Json_Value_Type;

    boolean  : bool;
    number   : float64;
    str      : string;
    array    : [..] *Json_Value;
    object   : [..] Json_Object_Entry;

    source_line   : int;
    source_column : int;
}

Json_Object_Entry :: struct {
    key   : string;
    value : *Json_Value;
}

Json_Error :: struct {
    message : string;
    line    : int;
    column  : int;
    offset  : int;
}

Json_Parse_Result :: struct {
    value   : *Json_Value;
    success : bool;
    error   : Json_Error;
}

Json_Serialize_Options :: struct {
    pretty         : bool = false;
    indent_width   : int  = 2;
    indent_char    : u8   = #char " ";
    sort_keys      : bool = false;
    escape_unicode : bool = false;
}

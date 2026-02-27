// direct getters

json_get :: (obj: *Json_Value, key: string) -> *Json_Value {
    if obj == null || obj.type != .OBJECT return null;
    for * entry : obj.object {
        if entry.key == key return entry.value;
    }
    return null;
}

json_get_string :: (obj: *Json_Value, key: string, default_value: string = "") -> string {
    val := json_get(obj, key);
    if val && val.type == .STRING return val.str;
    return default_value;
}

json_get_number :: (obj: *Json_Value, key: string, default_value: float64 = 0) -> float64 {
    val := json_get(obj, key);
    if val && val.type == .NUMBER return val.number;
    return default_value;
}

json_get_int :: (obj: *Json_Value, key: string, default_value: int = 0) -> int {
    val := json_get(obj, key);
    if val && val.type == .NUMBER return cast(int) val.number;
    return default_value;
}

json_get_bool :: (obj: *Json_Value, key: string, default_value: bool = false) -> bool {
    val := json_get(obj, key);
    if val && val.type == .BOOLEAN return val.boolean;
    return default_value;
}

json_get_array :: (obj: *Json_Value, key: string) -> *Json_Value {
    val := json_get(obj, key);
    if val && val.type == .ARRAY return val;
    return null;
}

json_get_object :: (obj: *Json_Value, key: string) -> *Json_Value {
    val := json_get(obj, key);
    if val && val.type == .OBJECT return val;
    return null;
}

// array access

json_array_count :: (arr: *Json_Value) -> int {
    if arr == null || arr.type != .ARRAY return 0;
    return arr.array.count;
}

json_array_get :: (arr: *Json_Value, index: int) -> *Json_Value {
    if arr == null || arr.type != .ARRAY return null;
    if index < 0 || index >= arr.array.count return null;
    return arr.array[index];
}

// object introspection

json_has_key :: (obj: *Json_Value, key: string) -> bool {
    if obj == null || obj.type != .OBJECT return false;
    for * entry : obj.object {
        if entry.key == key return true;
    }
    return false;
}

json_keys :: (obj: *Json_Value) -> [] string {
    if obj == null || obj.type != .OBJECT {
        empty: [] string;
        return empty;
    }
    result := NewArray(obj.object.count, string, allocator = temp);
    for i : 0..obj.object.count-1 {
        result[i] = obj.object[i].key;
    }
    return result;
}

// path queries: "user.address.city", "items.0.name"

json_query :: (root: *Json_Value, path: string) -> *Json_Value {
    if root == null return null;
    if path.count == 0 return root;

    current := root;
    remainder := path;

    while remainder.count > 0 && current != null {
        dot_pos := -1;
        for i : 0..remainder.count-1 {
            if remainder[i] == #char "." { dot_pos = i; break; }
        }

        segment: string;
        if dot_pos < 0 {
            segment = remainder;
            remainder.count = 0;
        } else {
            segment.data = remainder.data;
            segment.count = dot_pos;
            remainder.data = remainder.data + dot_pos + 1;
            remainder.count = remainder.count - dot_pos - 1;
        }

        if segment.count == 0 continue;

        if current.type == .OBJECT {
            current = json_get(current, segment);
        } else if current.type == .ARRAY {
            index, success, _ := string_to_int(segment);
            if success  current = json_array_get(current, index);
            else        return null;
        } else {
            return null;
        }
    }

    return current;
}

json_query_string :: (root: *Json_Value, path: string, default_value: string = "") -> string {
    val := json_query(root, path);
    if val && val.type == .STRING return val.str;
    return default_value;
}

json_query_number :: (root: *Json_Value, path: string, default_value: float64 = 0) -> float64 {
    val := json_query(root, path);
    if val && val.type == .NUMBER return val.number;
    return default_value;
}

json_query_int :: (root: *Json_Value, path: string, default_value: int = 0) -> int {
    val := json_query(root, path);
    if val && val.type == .NUMBER return cast(int) val.number;
    return default_value;
}

json_query_bool :: (root: *Json_Value, path: string, default_value: bool = false) -> bool {
    val := json_query(root, path);
    if val && val.type == .BOOLEAN return val.boolean;
    return default_value;
}

// type checks

json_is_null    :: inline (val: *Json_Value) -> bool { return val != null && val.type == .NULL; }
json_is_bool    :: inline (val: *Json_Value) -> bool { return val != null && val.type == .BOOLEAN; }
json_is_number  :: inline (val: *Json_Value) -> bool { return val != null && val.type == .NUMBER; }
json_is_string  :: inline (val: *Json_Value) -> bool { return val != null && val.type == .STRING; }
json_is_array   :: inline (val: *Json_Value) -> bool { return val != null && val.type == .ARRAY; }
json_is_object  :: inline (val: *Json_Value) -> bool { return val != null && val.type == .OBJECT; }

json_is_integer :: (val: *Json_Value) -> bool {
    if val == null || val.type != .NUMBER return false;
    return val.number == cast(float64)(cast(s64) val.number);
}

json_type_name :: (val: *Json_Value) -> string {
    if val == null return "null (pointer)";
    if val.type == {
        case .NULL;    return "null";
        case .BOOLEAN; return "boolean";
        case .NUMBER;  return "number";
        case .STRING;  return "string";
        case .ARRAY;   return "array";
        case .OBJECT;  return "object";
    }
    return "unknown";
}

// equality

json_equal :: (a: *Json_Value, b: *Json_Value) -> bool {
    if a == null && b == null return true;
    if a == null || b == null return false;
    if a.type != b.type return false;

    if a.type == {
        case .NULL;    return true;
        case .BOOLEAN; return a.boolean == b.boolean;
        case .NUMBER;  return a.number == b.number;
        case .STRING;  return a.str == b.str;
        case .ARRAY;
            if a.array.count != b.array.count return false;
            for i : 0..a.array.count-1 {
                if !json_equal(a.array[i], b.array[i]) return false;
            }
            return true;
        case .OBJECT;
            if a.object.count != b.object.count return false;
            for * ea : a.object {
                found := false;
                for * eb : b.object {
                    if ea.key == eb.key {
                        if !json_equal(ea.value, eb.value) return false;
                        found = true;
                        break;
                    }
                }
                if !found return false;
            }
            return true;
    }
    return false;
}

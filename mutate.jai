// builders allocated via context.allocator

json_make_null :: () -> *Json_Value {
    val := New(Json_Value);
    val.type = .NULL;
    return val;
}

json_make_bool :: (b: bool) -> *Json_Value {
    val := New(Json_Value);
    val.type = .BOOLEAN;
    val.boolean = b;
    return val;
}

json_make_number :: (n: float64) -> *Json_Value {
    val := New(Json_Value);
    val.type = .NUMBER;
    val.number = n;
    return val;
}

json_make_int :: (n: int) -> *Json_Value {
    val := New(Json_Value);
    val.type = .NUMBER;
    val.number = cast(float64) n;
    return val;
}

json_make_string :: (s: string) -> *Json_Value {
    val := New(Json_Value);
    val.type = .STRING;
    val.str = copy_string(s);
    return val;
}

json_make_array :: () -> *Json_Value {
    val := New(Json_Value);
    val.type = .ARRAY;
    return val;
}

json_make_object :: () -> *Json_Value {
    val := New(Json_Value);
    val.type = .OBJECT;
    return val;
}

// array mutation

json_array_append :: (arr: *Json_Value, element: *Json_Value) {
    if arr == null || arr.type != .ARRAY || element == null return;
    array_add(*arr.array, element);
}

json_array_insert :: (arr: *Json_Value, index: int, element: *Json_Value) {
    if arr == null || arr.type != .ARRAY || element == null return;
    if index < 0 || index > arr.array.count return;
    array_insert_at(*arr.array, element, index);
}

json_array_remove :: (arr: *Json_Value, index: int) -> *Json_Value {
    if arr == null || arr.type != .ARRAY return null;
    if index < 0 || index >= arr.array.count return null;
    removed := arr.array[index];
    array_ordered_remove_by_index(*arr.array, index);
    return removed;
}

// object mutation

json_object_set :: (obj: *Json_Value, key: string, value: *Json_Value) {
    if obj == null || obj.type != .OBJECT || value == null return;
    for * entry : obj.object {
        if entry.key == key {
            entry.value = value;
            return;
        }
    }
    entry: Json_Object_Entry;
    entry.key = copy_string(key);
    entry.value = value;
    array_add(*obj.object, entry);
}

json_object_set_string :: (obj: *Json_Value, key: string, value: string) {
    json_object_set(obj, key, json_make_string(value));
}

json_object_set_number :: (obj: *Json_Value, key: string, value: float64) {
    json_object_set(obj, key, json_make_number(value));
}

json_object_set_int :: (obj: *Json_Value, key: string, value: int) {
    json_object_set(obj, key, json_make_int(value));
}

json_object_set_bool :: (obj: *Json_Value, key: string, value: bool) {
    json_object_set(obj, key, json_make_bool(value));
}

json_object_set_null :: (obj: *Json_Value, key: string) {
    json_object_set(obj, key, json_make_null());
}

json_object_remove :: (obj: *Json_Value, key: string) -> *Json_Value {
    if obj == null || obj.type != .OBJECT return null;
    for i : 0..obj.object.count-1 {
        if obj.object[i].key == key {
            removed := obj.object[i].value;
            array_ordered_remove_by_index(*obj.object, i);
            return removed;
        }
    }
    return null;
}

// clone goes through context.allocator

json_clone :: (val: *Json_Value) -> *Json_Value {
    if val == null return null;

    result := New(Json_Value);
    result.type = val.type;
    result.source_line = val.source_line;
    result.source_column = val.source_column;

    if val.type == {
        case .BOOLEAN; result.boolean = val.boolean;
        case .NUMBER;  result.number = val.number;
        case .STRING;  result.str = copy_string(val.str);
        case .ARRAY;
            array_reserve(*result.array, val.array.count);
            for val.array array_add(*result.array, json_clone(it));
        case .OBJECT;
            array_reserve(*result.object, val.object.count);
            for * entry : val.object {
                new_entry: Json_Object_Entry;
                new_entry.key = copy_string(entry.key);
                new_entry.value = json_clone(entry.value);
                array_add(*result.object, new_entry);
            }
    }

    return result;
}

/*
 JSON Module Usage Guide

 TABLE OF CONTENTS
 -----------------
 1. Parsing
 2. Memory Management
 3. Reading Values (Accessors)
 4. Path Queries
 5. Type Checking
 6. Building JSON from Scratch
 7. Mutating Existing JSON
 8. Serialization
 9. Cloning & Equality
 10. Error Handling
 11. Full Example


 1. PARSING

 Basic parse uses whatever context.allocator is set to:

     root := json_parse(json_string);

 Parse with error info:

     result := json_parse_with_result(json_string);
     if !result.success {
         print("Parse error: % at line %:%\n",
             result.error.message,
             result.error.line,
             result.error.column);
     } else {
         root := result.value;
         // ... use root ...
     }


 2. MEMORY MANAGEMENT

 The parser allocates through context.allocator, so the caller
 controls lifetime by pushing the appropriate allocator.

 Option A: Temp storage (no cleanup needed) 

     push_allocator(temp);
     root := json_parse(json_string);
     name := json_get_string(root, "name");
     // ... use values ...
     // Everything is freed on next reset_temporary_storage()

 Option B: Arena (bulk free)

     pool: Flat_Pool;
     flat_pool_init(*pool);
     defer flat_pool_destroy(*pool);

     push_allocator(flat_pool_allocator(*pool));
     root := json_parse(json_string);
     // ... use root for as long as you want ...
     // flat_pool_destroy frees everything at once

 Option C: Default heap (manual free)

     root := json_parse(json_string);
     defer json_free(root);
     // json_free walks the tree and frees every node


 3. READING VALUES (ACCESSORS)

 Given JSON:
   {
     "name": "Alice",
     "age": 30,
     "active": true,
     "address": { "city": "Portland" },
     "scores": [95, 87, 92]
   }

 Get a child value by key 

     val := json_get(root, "name");
     // Returns *Json_Value or null if not found / wrong type

 Typed getters with defaults

     name   := json_get_string(root, "name");           // "Alice"
     name   := json_get_string(root, "missing", "???"); // "???"

     age    := json_get_number(root, "age");             // 30.0
     age_i  := json_get_int(root, "age");                // 30

     active := json_get_bool(root, "active");            // true
     active := json_get_bool(root, "missing", true);     // true (default)

 Get nested object

     address := json_get_object(root, "address");
     city    := json_get_string(address, "city");        // "Portland"

 Get array 

     scores := json_get_array(root, "scores");
     count  := json_array_count(scores);                 // 3
     first  := json_array_get(scores, 0);                // *Json_Value (.NUMBER, 95)

 Object introspection 

     json_has_key(root, "name");   // true
     json_has_key(root, "email");  // false

     keys := json_keys(root);
     // ["name", "age", "active", "address", "scores"]
     // Note: returned slice is temp-allocated


 4. PATH QUERIES

 Dot-separated paths that traverse nested objects and arrays.
 Array elements are accessed by integer index.

 Given JSON:
   {
     "users": [
       { "name": "Alice", "address": { "city": "Portland" } },
       { "name": "Bob",   "address": { "city": "Seattle" } }
     ]
   }

     city := json_query_string(root, "users.0.address.city");
     // "Portland"

     bob := json_query(root, "users.1");
     // *Json_Value for Bob's object

     missing := json_query(root, "users.5.name");
     // null (index out of bounds)

 Typed query variants:

     json_query_string(root, path)            // -> string
     json_query_string(root, path, "default") // -> string with default
     json_query_number(root, path)            // -> float64
     json_query_int(root, path)               // -> int
     json_query_bool(root, path)              // -> bool


 5. TYPE CHECKING

     val := json_get(root, "name");

     json_is_null(val)       // false
     json_is_string(val)     // true
     json_is_number(val)     // false
     json_is_bool(val)       // false
     json_is_array(val)      // false
     json_is_object(val)     // false

     // For numbers: check if it has no fractional part
     age := json_get(root, "age");
     json_is_integer(age)    // true  (30.0 == 30)

     // Debug-friendly type name
     json_type_name(val)     // "string"
     json_type_name(null)    // "null (pointer)"


 6. BUILDING JSON FROM SCRATCH

 All json_make_* functions allocate through context.allocator.

     // Build: {"name": "Alice", "scores": [95, 87], "active": true}

     obj := json_make_object();

     json_object_set_string(obj, "name", "Alice");
     json_object_set_bool(obj, "active", true);

     scores := json_make_array();
     json_array_append(scores, json_make_int(95));
     json_array_append(scores, json_make_int(87));
     json_object_set(obj, "scores", scores);

     output := json_serialize(obj);
     // {"name":"Alice","active":true,"scores":[95,87]}

 Available builders:

     json_make_null()            // -> *Json_Value  (.NULL)
     json_make_bool(true)        // -> *Json_Value  (.BOOLEAN)
     json_make_number(3.14)      // -> *Json_Value  (.NUMBER)
     json_make_int(42)           // -> *Json_Value  (.NUMBER, 42.0)
     json_make_string("hello")   // -> *Json_Value  (.STRING)
     json_make_array()           // -> *Json_Value  (.ARRAY, empty)
     json_make_object()          // -> *Json_Value  (.OBJECT, empty)


 7. MUTATING EXISTING JSON

 Object set/remove

     // Set or overwrite a key:
     json_object_set(obj, "key", some_json_value);

     // Typed convenience setters:
     json_object_set_string(obj, "name", "Bob");
     json_object_set_number(obj, "score", 99.5);
     json_object_set_int(obj, "level", 5);
     json_object_set_bool(obj, "verified", true);
     json_object_set_null(obj, "deleted_at");

     // Remove a key (returns the removed value):
     old := json_object_remove(obj, "name");
     // old is the *Json_Value that was unlinked
     // In arena/temp mode, memory is reclaimed with the pool
     // In heap mode, caller can json_free(old) if desired

 Array append/insert/remove

     json_array_append(arr, json_make_string("new item"));

     // Insert at index (shifts elements right):
     json_array_insert(arr, 0, json_make_string("first"));

     // Remove at index (returns the removed element):
     removed := json_array_remove(arr, 2);

 8. SERIALIZATION

 Compact (default)

     s := json_serialize(root);
     // {"name":"Alice","age":30}

 Pretty-printed

     s := json_pretty(root);
     // {
     //   "name": "Alice",
     //   "age": 30
     // }

 Custom options

     opts: Json_Serialize_Options;
     opts.pretty         = true;
     opts.indent_width   = 4;       // 4 spaces per level
     opts.indent_char    = #char " ";
     opts.sort_keys      = true;    // alphabetical key order
     opts.escape_unicode = true;    // \uXXXX for non-ASCII

     s := json_serialize(root, opts);

 Tab indentation

     opts: Json_Serialize_Options;
     opts.pretty       = true;
     opts.indent_width = 1;
     opts.indent_char  = #char "\t";

     s := json_serialize(root, opts);

 Write to an existing String_Builder

     builder: String_Builder;
     append(*builder, "data = ");
     json_serialize_to_builder(*builder, root);
     append(*builder, ";\n");
     output := builder_to_string(*builder);

 Quick debug print to console

     json_print(root);
     // prints compact + newline to stdout

     opts: Json_Serialize_Options;
     opts.pretty = true;
     json_print(root, opts);
     // prints pretty + newline to stdout

 9. CLONING & EQUALITY

 Deep clone

     // Clone allocates through context.allocator, so push
     // a different allocator to clone across arenas:

     copy := json_clone(root);
     // Independent deep copy, same allocator as current context

     // Clone from temp into a long-lived arena:
     push_allocator(flat_pool_allocator(*my_pool));
     long_lived := json_clone(temp_parsed_root);

 Structural equality

     if json_equal(a, b) {
         print("Same structure and values\n");
     }

     // Objects are compared regardless of key order.
     // Arrays are compared in order.
     // Numbers compared as float64.
     // null == null is true.
     // Different types are never equal.


 10. ERROR HANDLING

 The parser detects and reports:
   - Empty input
   - Unexpected characters
   - Unterminated strings, arrays, objects
   - Invalid escape sequences
   - Unescaped control characters in strings
   - Leading zeros in numbers (e.g. 007)
   - Missing digits after decimal point or exponent
   - Trailing commas in arrays/objects
   - Duplicate keys in objects
   - Trailing content after root value
   - Invalid/incomplete \uXXXX escapes
   - Invalid UTF-16 surrogate pairs

 All errors include line and column numbers:

     result := json_parse_with_result(bad_json);
     if !result.success {
         print("Error at line %:% (offset %): %\n",
             result.error.line,
             result.error.column,
             result.error.offset,
             result.error.message);
     }

 json_parse() silently returns null on error. Use
 json_parse_with_result() when you need diagnostics.


 11. FULL EXAMPLE

     main :: () {
         json_string := #string END
         {
             "server": {
                 "host": "localhost",
                 "port": 8080,
                 "debug": false
             },
             "users": [
                 {"name": "Alice", "role": "admin"},
                 {"name": "Bob",   "role": "user"}
             ]
         }
         END

         // Parse into temp — no cleanup needed
         push_allocator(temp);

         result := json_parse_with_result(json_string);
         if !result.success {
             print("Parse error: %\n", result.error.message);
             return;
         }

         root := result.value;

         // Read config via path queries
         host  := json_query_string(root, "server.host");
         port  := json_query_int(root, "server.port");
         debug := json_query_bool(root, "server.debug");

         print("Connecting to %:% (debug=%)\n", host, port, debug);

         // Iterate users array
         users := json_get_array(root, "users");
         for i : 0..json_array_count(users)-1 {
             user := json_array_get(users, i);
             name := json_get_string(user, "name");
             role := json_get_string(user, "role");
             print("  User: % (%)\n", name, role);
         }

         // Mutate: add a new user
         new_user := json_make_object();
         json_object_set_string(new_user, "name", "Charlie");
         json_object_set_string(new_user, "role", "user");
         json_array_append(users, new_user);

         // Mutate: update server config
         server := json_get_object(root, "server");
         json_object_set_int(server, "port", 9090);
         json_object_set_bool(server, "debug", true);

         // Serialize back out
         print("\nUpdated config:\n");
         json_print(root, .{pretty = true, sort_keys = true});

         // Check equality
         clone := json_clone(root);
         print("\nClone matches original: %\n", json_equal(root, clone));
     }

   Output:
     Connecting to localhost:8080 (debug=false)
       User: Alice (admin)
       User: Bob (user)

     Updated config:
     {
       "server": {
         "debug": true,
         "host": "localhost",
         "port": 9090
       },
       "users": [
         {
           "name": "Alice",
           "role": "admin"
         },
         {
           "name": "Bob",
           "role": "user"
         },
         {
           "name": "Charlie",
           "role": "user"
         }
       ]
     }

     Clone matches original: true
*/

#import "Basic";

#load "types.jai";
#load "parse.jai";
#load "parse_internal.jai";
#load "accessors.jai";
#load "mutate.jai";
#load "serialize.jai";
#load "util.jai";

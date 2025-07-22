module allib.c_wrapper;

import allib.allib;
import core.stdc.stdlib;
import core.stdc.string;
import std.conv;
import std.json;
import std.datetime;
import std.string;

// Opaque handles for C
extern(C) struct ALSessionHandle;
extern(C) struct ALClientHandle;

// Callback types
extern(C) alias ScriptCallback = int function(ALClientHandle* client); // returns milliseconds to wait
extern(C) alias EventCallback = void function(ALClientHandle* client, const char* event_name, const char* json_data);

// Session functions
extern(C) ALSessionHandle* allib_create_session(const char* addr)
{
    try {
        auto session = allib.allib.ALSession.INSTANCE();
        return cast(ALSessionHandle*)cast(void*)session;
    } catch (Exception e) {
        import core.stdc.stdio;
        fprintf(stderr, "Error creating session: %.*s\n", cast(int)e.msg.length, e.msg.ptr);
        return null;
    }
}

// Client functions
extern(C) ALClientHandle* allib_create_client(ALSessionHandle* session_ptr, const char* char_name, const char* server)
{
    try {
        auto session = cast(allib.allib.ALSession)(cast(void*)session_ptr);
        auto client = session.createClient(to!string(char_name), server ? to!string(server) : null);
        return cast(ALClientHandle*)client;
    } catch (Exception e) {
        import core.stdc.stdio;
        fprintf(stderr, "Error creating client: %.*s\n", cast(int)e.msg.length, e.msg.ptr);
        return null;
    }
}

// Client lifecycle
extern(C) void allib_start_client(ALClientHandle* client_ptr, ScriptCallback script_cb, EventCallback event_cb)
{
    try {
        auto client = cast(allib.allib.ALClient)(cast(void*)client_ptr);
        
        // Start client with script callback
        client.start((allib.allib.ALClient c) {
            return dur!"msecs"(script_cb(client_ptr));
        });
    } catch (Exception e) {
        import core.stdc.stdio;
        fprintf(stderr, "Error starting client: %.*s\n", cast(int)e.msg.length, e.msg.ptr);
    }
}

// Movement functions
extern(C) void allib_move(ALClientHandle* client_ptr, double x, double y)
{
    try {
        auto client = cast(allib.allib.ALClient)(cast(void*)client_ptr);
        client.move(x, y);
    } catch (Exception e) {
        import core.stdc.stdio;
        fprintf(stderr, "Error moving: %.*s\n", cast(int)e.msg.length, e.msg.ptr);
    }
}

// Skill functions
extern(C) void allib_use_skill(ALClientHandle* client_ptr, const char* skill_name)
{
    try {
        auto client = cast(allib.allib.ALClient)(cast(void*)client_ptr);
        client.useSkill(to!string(skill_name));
    } catch (Exception e) {
        import core.stdc.stdio;
        fprintf(stderr, "Error using skill: %.*s\n", cast(int)e.msg.length, e.msg.ptr);
    }
}

// Targeting functions
extern(C) void allib_change_target(ALClientHandle* client_ptr, const char* target_id)
{
    try {
        auto client = cast(allib.allib.ALClient)(cast(void*)client_ptr);
        client.changeTarget(to!string(target_id), "");
    } catch (Exception e) {
        import core.stdc.stdio;
        fprintf(stderr, "Error changing target: %.*s\n", cast(int)e.msg.length, e.msg.ptr);
    }
}

// Utility functions
extern(C) double allib_distance(double x1, double y1, double x2, double y2)
{
    return distance(x1, y1, x2, y2);
}

// Memory management
extern(C) void allib_free_session(ALSessionHandle* session_ptr)
{
    // GC will handle in D
}

extern(C) void allib_free_client(ALClientHandle* client_ptr)
{
    // GC will handle in D
}
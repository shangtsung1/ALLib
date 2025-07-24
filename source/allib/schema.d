module allib.schema;

import allib.logger;

import std.json;
import std.exception;
import std.conv;
import std.format;
import std.datetime;
import std.exception : enforce;
import std.typecons : Nullable;

struct GameData{
    int data_version;//version
    JSONValue achievements;
    JSONValue animations;
    JSONValue monsters;
    JSONValue sprites;
    JSONValue maps;
    JSONValue geometry;
    JSONValue npcs;
    JSONValue tilesets;

    JSONValue imagesets;
    JSONValue items;
    JSONValue tokens;
    JSONValue sets;
    JSONValue craft;
    JSONValue dismantle;
    JSONValue conditions;

    JSONValue cosmetics;
    JSONValue emotions;
    JSONValue projectiles;
    JSONValue classes;
    JSONValue dimensions;

    JSONValue images;
    JSONValue levels;
    JSONValue positions;
    JSONValue skills;
    JSONValue events;
    JSONValue games;
    JSONValue multipliers;
    JSONValue docs;
    JSONValue drops;

    static GameData fromJson(JSONValue json) {
        GameData data;

        data.data_version = json["version"].get!int;
        data.achievements  = json["achievements"];
        data.animations   = json["animations"];
        data.monsters     = json["monsters"];
        data.sprites      = json["sprites"];
        data.maps         = json["maps"];
        data.geometry     = json["geometry"];
        data.npcs         = json["npcs"];
        data.tilesets     = json["tilesets"];
        data.imagesets    = json["imagesets"];
        data.items        = json["items"];
        data.tokens       = json["tokens"];
        data.sets         = json["sets"];
        data.craft        = json["craft"];
        data.dismantle    = json["dismantle"];
        data.conditions   = json["conditions"];
        data.cosmetics    = json["cosmetics"];
        data.emotions     = json["emotions"];
        data.projectiles  = json["projectiles"];
        data.classes      = json["classes"];
        data.dimensions   = json["dimensions"];
        data.images       = json["images"];
        data.levels       = json["levels"];
        data.positions    = json["positions"];
        data.skills       = json["skills"];
        data.events       = json["events"];
        data.games        = json["games"];
        data.multipliers  = json["multipliers"];
        data.docs         = json["docs"];
        data.drops        = json["drops"];
        return data;
    }
}

class BooleanObject : Object {
    bool value;
    this(bool v) { value = v; }
}

class IntegerObject : Object {
    int value;
    this(int v) { value = v; }
}

class DoubleObject : Object {
    double value;
    this(double v) { value = v; }
}

class StringObject : Object {
    string value;
    this(string v) { value = v; }
}

struct BankPack {
    string category;
    long amount;
    int level;
}

class Chest{
    string id;

    this(string i){
        this.id = i;
    }

    string getId(){
        return id;
    }
}

struct Slots {
    SlotItem ring1;
    SlotItem ring2;
    SlotItem earring1;
    SlotItem earring2;
    SlotItem belt;
    SlotItem mainhand;
    SlotItem offhand;
    SlotItem helmet;
    SlotItem chest;
    SlotItem pants;
    SlotItem shoes;
    SlotItem gloves;
    SlotItem amulet;
    SlotItem orb;
    SlotItem elixir;
    SlotItem cape;
}

struct SlotItem {
    string name;
    int level;
    Nullable!string stat_type;
    Nullable!int acc;
    Nullable!string ach;
    Nullable!SysTime expires;
    Nullable!bool ex;
    Nullable!string p;
    Nullable!(string[]) ps;
}

struct Entity {
    int hp;
    int max_hp;
    int mp;
    int max_mp;
    long xp;
    int attack;
    int heal;
    double frequency;
    int speed;
    int range;
    int armor;
    int resistance;
    int level;
    string party;
    bool rip;
    //string code;
    bool afk;
    string target;
    Nullable!string focus;
    //s;
    //c
    //q

    int age;
    double pdps;
    string id = null;
    string mapName;
    double x;
    double y;
    bool moving;
    long move_started;
    double going_x;
    double going_y;
    double from_x;
    double from_y;
    bool abs;
    long move_num;
    double angle;
    int cid;
    string controller;
    string skin;

    int m;
    //cx

    Slots slots;
    string ctype;
    string mtype;
    string type;
    string owner;

    static Entity fromJson(JSONValue json) {
        auto e = Entity();

        e.hp = getInt(json,"hp",0);
        e.max_hp = getInt(json,"max_hp",0);
        e.mp = getInt(json,"mp",0);
        e.max_mp = getInt(json,"max_mp",0);
        e.xp = getLong(json,"xp",0);
        e.attack = getInt(json,"attack",0);
        e.heal = getInt(json,"heal",0);
        e.frequency = getDouble(json,"frequency",0);
        e.speed = getInt(json,"speed",0);
        e.range = getInt(json,"range",0);
        e.armor = getInt(json,"armor",0);
        e.resistance = getInt(json,"resistance",0);
        e.level = getInt(json,"level",0);
        e.party = getString(json,"party",null);
        e.rip = getBool(json,"rip",false);
        e.mapName = getString(json,"map",null);
        //e.code = json["code"].get!bool;//can be string or bool
        e.afk = getBool(json,"afk",false);
        e.target = getString(json,"target",null);
        e.focus = nullableField!string(json, "focus");
        e.age = getInt(json,"age",0);
        e.pdps = getDouble(json,"pdps",0);
        e.id = getString(json,"id",null);
        e.x = json["x"].get!double;
        e.y = json["y"].get!double;
        e.from_x = getDouble(json,"from_x",e.x);
        e.from_y = getDouble(json,"from_y",e.y);
        e.moving = getBool(json,"moving",false);
        e.going_x = getDouble(json,"going_x",e.x);
        e.going_y = getDouble(json,"going_y",e.y);
        e.abs = getBool(json,"abs",false);
        e.move_num = getInt(json,"move_num",0);
        e.angle = getDouble(json,"angle",0);
        e.cid = getInt(json,"cid",0);
        e.m = getInt(json,"m",0);
        e.controller = getString(json,"controller",null);
        e.skin = getString(json,"skin",null);

        auto parseSlot(ref SlotItem slot, JSONValue slotJson) {
            if(slotJson.isNull())return;
            if ("name" in slotJson) slot.name = slotJson["name"].str;
            if ("level" in slotJson) slot.level = slotJson["level"].get!int;
            slot.stat_type = nullableField!string(slotJson, "stat_type");
            slot.acc = nullableField!int(slotJson, "acc");
            slot.ach = nullableField!string(slotJson, "ach");
            if ("expires" in slotJson)
                slot.expires = parseNullableSysTime(slotJson["expires"]);
            slot.ex = nullableField!bool(slotJson, "ex");
            slot.p = nullableField!string(slotJson, "p");
            if ("ps" in slotJson)
                slot.ps = nullableStringArray(slotJson["ps"]);
        }
        if("slots" in json){
            auto slots = json["slots"];
            parseSlot(e.slots.ring1,     slots["ring1"]);
            parseSlot(e.slots.ring2,     slots["ring2"]);
            parseSlot(e.slots.earring1,  slots["earring1"]);
            parseSlot(e.slots.earring2,  slots["earring2"]);
            parseSlot(e.slots.belt,      slots["belt"]);
            parseSlot(e.slots.mainhand,  slots["mainhand"]);
            parseSlot(e.slots.offhand,   slots["offhand"]);
            parseSlot(e.slots.helmet,    slots["helmet"]);
            parseSlot(e.slots.chest,     slots["chest"]);
            parseSlot(e.slots.pants,     slots["pants"]);
            parseSlot(e.slots.shoes,     slots["shoes"]);
            parseSlot(e.slots.gloves,    slots["gloves"]);
            parseSlot(e.slots.amulet,    slots["amulet"]);
            parseSlot(e.slots.orb,       slots["orb"]);
            parseSlot(e.slots.elixir,    slots["elixir"]);
            parseSlot(e.slots.cape,      slots["cape"]);
        }
        e.ctype = getString(json,"ctype",null);
        e.mtype = getString(json,"mtype",null);
        e.type = getString(json,"type",null);
        e.owner = getString(json,"owner",null);
        return e;
    }

    static string getString(JSONValue jv, string key,string def = null){
        try{
        if(key in jv){
            return jv[key].get!string;
        }
        }
        catch(Throwable t){
            logVerb(t);
        }
        return def;
    }

    static int getInt(JSONValue jv, string key,int def = 0){
        try{
        if(key in jv){
            return jv[key].get!int;
        }
        }
        catch(Throwable t){
            logVerb(t);
        }
        return def;
    }

    static double getDouble(JSONValue jv, string key,double def = 0){
        try{
        if(key in jv){
            return jv[key].get!double;
        }
        }
        catch(Throwable t){
            logVerb(t);
        }
        return def;
    }

    static long getLong(JSONValue jv, string key,long def = 0){
        try{
        if(key in jv){
            return jv[key].get!long;
        }
        }
        catch(Throwable t){
            logVerb(t);
        }
        return def;
    }

    static bool getBool(JSONValue jv, string key,bool def = 0){
        try{
            if(key in jv){
                return jv[key].get!bool;
            }
        }
        catch(Throwable t){
            logVerb(t);
        }
        return def;
    }
}








Nullable!T nullableField(T)(JSONValue v, string key)
{
    if (key in v)
    {
        auto val = v[key];
        if (val.type == JSONType.null_)
            return Nullable!T.init;
        return Nullable!T(val.get!T);
    }
    return Nullable!T.init;
}


Nullable!SysTime parseNullableSysTime(JSONValue v)
{
    if (v.type == JSONType.string)
    {
        return Nullable!SysTime(SysTime.fromISOExtString(v.str));
    }
    return Nullable!SysTime.init;
}


Nullable!(string[]) nullableStringArray(JSONValue v)
{
    if (v.type == JSONType.array) {
        string[] result;
        foreach (item; v.array)
            result ~= item.str;
         return Nullable!(string[])(result);
    }
    return Nullable!(string[]).init;
}

mixin template ListenerSet(string name, T...) {

    static string generateParamList() {
        string[] parts;
        foreach (i, Tt; T) {
            parts ~= Tt.stringof ~ " arg" ~ to!string(i);
        }
        return parts.join(", ");
    }

    static string generateArgList() {
        string[] args;
        foreach (i, _; T) {
            args ~= "arg" ~ to!string(i);
        }
        return args.join(", ");
    }

    enum listenerTypeName = name ~ "Listener";
    enum listenersArrayName = name ~ "Listeners";

    enum paramList = generateParamList();
    enum argList = generateArgList();

    enum mixinSrc = format(q{
        alias %s = void delegate(%s);
        private %s[] %s;

        void on%s(%s listener) {
            %s ~= listener;
        }

        void fire%s(%s) {
            foreach (listener; %s) {
                listener(%s);
            }
        }
    },
        listenerTypeName, 
        paramList,  
        listenerTypeName,
        listenersArrayName, 

        name, 
        listenerTypeName, 

        listenersArrayName,

        name,
        paramList,
        listenersArrayName,
        argList
    );

    //pragma(msg, "ListenerSet mixin for "~ name ~":\n" ~ mixinSrc);

    mixin(mixinSrc);
}




module allib.c_wrapper;

import allib.allib;
import core.stdc.stdlib;
import core.stdc.string;
import std.conv;
import std.json;
import std.datetime;
import std.string;
import core.stdc.stdio;
import vibe.vibe : runApplication;
static import allib.schema;

extern(C) struct ALSessionHandle;
extern(C) struct ALClientHandle;

extern(C) alias ScriptCallback = int function(ALClientHandle* client);
extern(C) alias EventCallback = void function(ALClientHandle* client, const char* event_name, const char* json_data);

extern(C):

struct ALSlotItem {
    char* name;
    int level;
};

struct ALSlots {
    ALSlotItem ring1;
    ALSlotItem ring2;
    ALSlotItem earring1;
    ALSlotItem earring2;
    ALSlotItem belt;
    ALSlotItem mainhand;
    ALSlotItem offhand;
    ALSlotItem helmet;
    ALSlotItem chest;
    ALSlotItem pants;
    ALSlotItem shoes;
    ALSlotItem gloves;
    ALSlotItem amulet;
    ALSlotItem orb;
    ALSlotItem elixir;
    ALSlotItem cape;
};

struct ALEntity {
    int hp, max_hp;
    int mp, max_mp;
    long xp;
    int attack, heal;
    double frequency;
    int speed, range;
    int armor, resistance;
    int level;
    int age;
    bool rip;
    bool afk;
    bool moving;
    double x, y;
    double from_x, from_y;
    double going_x, going_y;
    long move_started;
    double angle;
    int cid;
    int m;
    char* id;
    char* map;
    char* target;
    char* focus;
    char* controller;
    char* skin;
    ALSlots slots;
};

struct ALBankPack {
    char* category;
    long amount;
    int level;
};

struct ALChest {
    const char* id;
};

private ALEntity toALEntity(allib.schema.Entity e) {
    ALEntity outs;
    outs.hp = e.hp;
    outs.max_hp = e.max_hp;
    outs.mp = e.mp;
    outs.max_mp = e.max_mp;
    outs.xp = e.xp;
    outs.attack = e.attack;
    outs.heal = e.heal;
    outs.frequency = e.frequency;
    outs.speed = e.speed;
    outs.range = e.range;
    outs.armor = e.armor;
    outs.resistance = e.resistance;
    outs.level = e.level;
    outs.age = e.age;
    outs.rip = e.rip;
    outs.afk = e.afk;
    outs.moving = e.moving;
    outs.x = e.x;
    outs.y = e.y;
    outs.from_x = e.from_x;
    outs.from_y = e.from_y;
    outs.going_x = e.going_x;
    outs.going_y = e.going_y;
    outs.move_started = e.move_started;
    outs.angle = e.angle;
    outs.cid = e.cid;
    outs.m = e.m;
    outs.id = cast(char*)toStringz(e.id);
    outs.map = cast(char*)toStringz(e.mapName);
    outs.target = cast(char*)toStringz(e.target);
    outs.focus = e.focus.isNull ? null : cast(char*)toStringz(e.focus.get);
    outs.controller = cast(char*)toStringz(e.controller);
    outs.skin = cast(char*)toStringz(e.skin);

    auto copySlot = (ref ALSlotItem dst, allib.schema.SlotItem src) {
        dst.name = cast(char*)toStringz(src.name.to!string);
        dst.level = src.level;
    };

    auto s = e.slots;
    copySlot(outs.slots.ring1, s.ring1);
    copySlot(outs.slots.ring2, s.ring2);
    copySlot(outs.slots.earring1, s.earring1);
    copySlot(outs.slots.earring2, s.earring2);
    copySlot(outs.slots.belt, s.belt);
    copySlot(outs.slots.mainhand, s.mainhand);
    copySlot(outs.slots.offhand, s.offhand);
    copySlot(outs.slots.helmet, s.helmet);
    copySlot(outs.slots.chest, s.chest);
    copySlot(outs.slots.pants, s.pants);
    copySlot(outs.slots.shoes, s.shoes);
    copySlot(outs.slots.gloves, s.gloves);
    copySlot(outs.slots.amulet, s.amulet);
    copySlot(outs.slots.orb, s.orb);
    copySlot(outs.slots.elixir, s.elixir);
    copySlot(outs.slots.cape, s.cape);

    return outs;
}

ALEntity allib_get_entity(ALClientHandle* client_ptr) {
    auto e = (cast(ALClient)(cast(void*)client_ptr)).player;
    return toALEntity(e);
}

extern(C) bool allib_is_alive(ALClientHandle* client_ptr) {
    return (cast(ALClient)(cast(void*)client_ptr)).isAlive();
}

extern(C) bool allib_is_dead(ALClientHandle* client_ptr) {
    return (cast(ALClient)(cast(void*)client_ptr)).isDead();
}

extern(C) bool allib_is_moving(ALClientHandle* client_ptr) {
    return (cast(ALClient)(cast(void*)client_ptr)).isMoving();
}

extern(C) bool allib_has_target(ALClientHandle* client_ptr) {
    return (cast(ALClient)(cast(void*)client_ptr)).hasTarget();
}

extern(C) ALEntity allib_get_target_entity(ALClientHandle* client_ptr) {
    auto ent = (cast(ALClient)(cast(void*)client_ptr)).getTargetEntity();
    return toALEntity(ent);
}

extern(C) bool allib_is_target_alive(ALClientHandle* client_ptr) {
    return (cast(ALClient)(cast(void*)client_ptr)).isTargetAlive();
}

extern(C) double allib_distance_to(ALClientHandle* client_ptr, double x, double y) {
    auto c = cast(ALClient)(cast(void*)client_ptr);
    return distance(c.player.x, c.player.y, x, y);
}

extern(C) double allib_distance_to_entity(ALClientHandle* client_ptr, ALEntity ent) {
    auto c = cast(ALClient)(cast(void*)client_ptr);
    return distance(c.player.x, c.player.y, ent.x, ent.y);
}

extern(C) double allib_distance_to_client(ALClientHandle* client_ptr, ALClientHandle* other_ptr) {
    auto c1 = cast(ALClient)(cast(void*)client_ptr);
    auto c2 = cast(ALClient)(cast(void*)other_ptr);
    return distance(c1.player.x, c1.player.y, c2.player.x, c2.player.y);
}

extern(C) bool allib_is_within_range(ALClientHandle* client_ptr, double x, double y, double range) {
    return (cast(ALClient)(cast(void*)client_ptr)).isWithinRange(x, y, range);
}

extern(C) bool allib_is_within_range_of_entity(ALClientHandle* client_ptr, ALEntity ent, double range) {
    auto c = cast(ALClient)(cast(void*)client_ptr);
    return c.isWithinRange(ent.x, ent.y, range);
}

extern(C) void allib_move_to_entity(ALClientHandle* client_ptr, ALEntity ent) {
    (cast(ALClient)(cast(void*)client_ptr)).move(ent.x, ent.y);
}

extern(C) void allib_move_to_client(ALClientHandle* client_ptr, ALClientHandle* other_ptr) {
    auto other = cast(ALClient)(cast(void*)other_ptr);
    (cast(ALClient)(cast(void*)client_ptr)).move(other.player.x, other.player.y);
}

extern(C) bool allib_can_attack_entity(ALClientHandle* client_ptr, ALEntity ent) {
    allib.schema.Entity e;
    e.x = ent.x;
    e.y = ent.y;
    return (cast(ALClient)(cast(void*)client_ptr)).canAttackEntity(e);
}

extern(C) long allib_skill_cooldown_remaining(ALClientHandle* client_ptr, const char* name) {
    return (cast(ALClient)(cast(void*)client_ptr)).skillCooldownRemaining((name).to!string);
}

extern(C) bool allib_is_skill_ready(ALClientHandle* client_ptr, const char* name) {
    return (cast(ALClient)(cast(void*)client_ptr)).isSkillReady((name).to!string);
}

extern(C) bool allib_is_health_low(ALClientHandle* client_ptr, double ratio) {
    return (cast(ALClient)(cast(void*)client_ptr)).isHealthLow(ratio);
}

extern(C) bool allib_is_mana_low(ALClientHandle* client_ptr, double ratio) {
    return (cast(ALClient)(cast(void*)client_ptr)).isManaLow(ratio);
}

extern(C) void allib_use_hp_if_low(ALClientHandle* client_ptr, double ratio) {
    (cast(ALClient)(cast(void*)client_ptr)).useHpIfLow(ratio);
}

extern(C) void allib_use_mp_if_low(ALClientHandle* client_ptr, double ratio) {
    (cast(ALClient)(cast(void*)client_ptr)).useMpIfLow(ratio);
}

extern(C) void allib_travel_to_town(ALClientHandle* client_ptr) {
    (cast(ALClient)(cast(void*)client_ptr)).travelToTown();
}

extern(C) bool allib_is_on_map(ALClientHandle* client_ptr, const char* name) {
    return (cast(ALClient)(cast(void*)client_ptr)).isOnMap((name).to!string);
}

extern(C) void allib_stop_movement(ALClientHandle* client_ptr) {
    (cast(ALClient)(cast(void*)client_ptr)).stopMovement();
}

extern(C) void allib_follow_entity(ALClientHandle* client_ptr, ALEntity ent, double dist) {
    allib.schema.Entity e;
    e.x = ent.x;
    e.y = ent.y;
    (cast(ALClient)(cast(void*)client_ptr)).followEntity(e, dist);
}

extern(C) void allib_follow_client(ALClientHandle* client_ptr, ALClientHandle* other_ptr, double dist) {
    auto other = cast(ALClient)(cast(void*)other_ptr);
    (cast(ALClient)(cast(void*)client_ptr)).followClient(other, dist);
}

extern(C) ALSessionHandle* allib_create_session(const char* addr) {
    try {
        auto session = ALSession.INSTANCE();
        return cast(ALSessionHandle*)cast(void*)session;
    } catch (Exception e) {
        fprintf(stderr, "Error creating session: %.*s\n", cast(int)e.msg.length, e.msg.ptr);
        return null;
    }
}

extern(C) void allib_free_session(ALSessionHandle* session_ptr) {}
extern(C) void allib_run_app() { runApplication(); }

extern(C) ALClientHandle* allib_create_client(ALSessionHandle* session_ptr, const char* char_name, const char* server) {
    try {
        auto session = cast(ALSession)(cast(void*)session_ptr);
        auto client = session.createClient(to!string(char_name), server ? to!string(server) : null);
        return cast(ALClientHandle*)client;
    } catch (Exception e) {
        fprintf(stderr, "Error creating client: %.*s\n", cast(int)e.msg.length, e.msg.ptr);
        return null;
    }
}

extern(C) void allib_free_client(ALClientHandle* client_ptr) {}
extern(C) void allib_start_client(ALClientHandle* client_ptr, ScriptCallback script_cb, EventCallback event_cb) {
    auto client = cast(ALClient)(cast(void*)client_ptr);
    client.start((ALClient c) => dur!"msecs"(script_cb(client_ptr)));
}

extern(C) void allib_move(ALClientHandle* client_ptr, double x, double y) {
    (cast(ALClient)(cast(void*)client_ptr)).move(x, y);
}

extern(C) void allib_move_precise(ALClientHandle* client_ptr, double x, double y, double fx, double fy) {
    (cast(ALClient)(cast(void*)client_ptr)).move(x, y, fx, fy);
}

extern(C) bool allib_smart_move(ALClientHandle* client_ptr, const char* dest) {
    (cast(ALClient)(cast(void*)client_ptr)).smartMove(to!string(dest));
    return true;
}

extern(C) bool allib_smart_move_coords(ALClientHandle* client_ptr, double x, double y) {
    (cast(ALClient)(cast(void*)client_ptr)).smartMove([x, y]);
    return true;
}

extern(C) void allib_respawn(ALClientHandle* client_ptr) {
    (cast(ALClient)(cast(void*)client_ptr)).respawn();
}

extern(C) void allib_town(ALClientHandle* client_ptr) {
    (cast(ALClient)(cast(void*)client_ptr)).town();
}

extern(C) void allib_stop(ALClientHandle* client_ptr) {
    (cast(ALClient)(cast(void*)client_ptr)).stop();
}

extern(C) void allib_change_target(ALClientHandle* client_ptr, const char* target_id) {
    (cast(ALClient)(cast(void*)client_ptr)).changeTarget(to!string(target_id), "");
}

extern(C) void allib_attack(ALClientHandle* client_ptr, const char* target_id) {
    (cast(ALClient)(cast(void*)client_ptr)).attack(to!string(target_id));
}

extern(C) void allib_use_skill(ALClientHandle* client_ptr, const char* name) {
    (cast(ALClient)(cast(void*)client_ptr)).useSkill(to!string(name));
}

extern(C) bool allib_can_use(ALClientHandle* client_ptr, const char* name) {
    return (cast(ALClient)(cast(void*)client_ptr)).canUse(to!string(name));
}

extern(C) bool allib_is_on_cooldown(ALClientHandle* client_ptr, const char* name) {
    return (cast(ALClient)(cast(void*)client_ptr)).isOnCooldown(to!string(name));
}

extern(C) void allib_set_cooldown(ALClientHandle* client_ptr, const char* name, long ms) {
    (cast(ALClient)(cast(void*)client_ptr)).setCooldown(to!string(name), ms);
}

extern(C) bool allib_equip(ALClientHandle* client_ptr, int num, const char* slot) {
    return (cast(ALClient)(cast(void*)client_ptr)).equip(num, to!string(slot));
}

extern(C) bool allib_unequip(ALClientHandle* client_ptr, int slot) {
    return (cast(ALClient)(cast(void*)client_ptr)).unequip(slot);
}

extern(C) bool allib_use_slot(ALClientHandle* client_ptr, int slot) {
    return (cast(ALClient)(cast(void*)client_ptr)).use(slot);
}

extern(C) bool allib_use_item(ALClientHandle* client_ptr, const char* name) {
    return (cast(ALClient)(cast(void*)client_ptr)).use(to!string(name));
}

extern(C) void allib_use_hp(ALClientHandle* client_ptr) {
    (cast(ALClient)(cast(void*)client_ptr)).useHp();
}

extern(C) void allib_use_mp(ALClientHandle* client_ptr) {
    (cast(ALClient)(cast(void*)client_ptr)).useMp();
}

extern(C) bool allib_send_gold(ALClientHandle* client_ptr, const char* name, int amount) {
    return (cast(ALClient)(cast(void*)client_ptr)).sendGold((name).to!string, amount);
}

extern(C) bool allib_send_item(ALClientHandle* client_ptr, const char* name, int num, int quantity) {
    return (cast(ALClient)(cast(void*)client_ptr)).sendItem((name).to!string, num, quantity);
}

extern(C) bool allib_send_mail(ALClientHandle* client_ptr, const char* to, const char* subject, const char* message, bool with_item) {
    return (cast(ALClient)(cast(void*)client_ptr)).sendMail((to).to!string,(subject).to!string,(message).to!string, with_item);
}

extern(C) bool allib_send_party_invite(ALClientHandle* client_ptr, const char* name) {
    return (cast(ALClient)(cast(void*)client_ptr)).sendPartyInvite((name).to!string, false);
}

extern(C) bool allib_accept_party_invite(ALClientHandle* client_ptr, const char* name) {
    return (cast(ALClient)(cast(void*)client_ptr)).acceptPartyInvite((name).to!string);
}

extern(C) bool allib_leave_party(ALClientHandle* client_ptr) {
    return (cast(ALClient)(cast(void*)client_ptr)).leaveParty();
}

extern(C) bool allib_kick_party_member(ALClientHandle* client_ptr, const char* name) {
    return (cast(ALClient)(cast(void*)client_ptr)).kickPartyMember((name).to!string);
}

extern(C) void allib_open_stand(ALClientHandle* client_ptr, int num) {
    (cast(ALClient)(cast(void*)client_ptr)).open_stand(num);
}

extern(C) void allib_close_stand(ALClientHandle* client_ptr) {
    (cast(ALClient)(cast(void*)client_ptr)).close_stand();
}

extern(C) void allib_bank_deposit(ALClientHandle* client_ptr, int gold) {
    (cast(ALClient)(cast(void*)client_ptr)).bankDeposit(gold);
}

extern(C) void allib_bank_withdraw(ALClientHandle* client_ptr, int gold) {
    (cast(ALClient)(cast(void*)client_ptr)).bankWithdraw(gold);
}

extern(C) char* allib_find_closest_monster_of_type(ALClientHandle* client_ptr, const char* type) {
    auto ent = (cast(ALClient)(cast(void*)client_ptr)).findClosestMonsterByType((type).to!string);
    return ent.id ? cast(char*)toStringz(ent.id) : null;
}

extern(C) double allib_distance(double x1, double y1, double x2, double y2) {
    return distance(x1, y1, x2, y2);
}

extern(C) double allib_get_x(ALClientHandle* client_ptr) {
    return (cast(ALClient)(cast(void*)client_ptr)).player.x;
}

extern(C) double allib_get_y(ALClientHandle* client_ptr) {
    return (cast(ALClient)(cast(void*)client_ptr)).player.y;
}

extern(C) char* allib_get_id(ALClientHandle* client_ptr) {
    return cast(char*)toStringz((cast(ALClient)(cast(void*)client_ptr)).player.id);
}

extern(C) void allib_set_boolean(ALClientHandle* client_ptr, const char* key, bool value) {
    (cast(ALClient)(cast(void*)client_ptr)).setBoolean((key).to!string, value);
}

extern(C) bool allib_get_boolean(ALClientHandle* client_ptr, const char* key) {
    return (cast(ALClient)(cast(void*)client_ptr)).getBoolean((key).to!string);
}

extern(C) void allib_set_integer(ALClientHandle* client_ptr, const char* key, int value) {
    (cast(ALClient)(cast(void*)client_ptr)).setInteger((key).to!string, value);
}

extern(C) int allib_get_integer(ALClientHandle* client_ptr, const char* key) {
    return (cast(ALClient)(cast(void*)client_ptr)).getInteger((key).to!string);
}

extern(C) void allib_set_double(ALClientHandle* client_ptr, const char* key, double value) {
    (cast(ALClient)(cast(void*)client_ptr)).setDouble((key).to!string, value);
}

extern(C) double allib_get_double(ALClientHandle* client_ptr, const char* key) {
    return (cast(ALClient)(cast(void*)client_ptr)).getDouble((key).to!string);
}

extern(C) void allib_set_string(ALClientHandle* client_ptr, const char* key, const char* value) {
    (cast(ALClient)(cast(void*)client_ptr)).setString((key).to!string, (value).to!string);
}

extern(C) char* allib_get_string(ALClientHandle* client_ptr, const char* key) {
    return cast(char*)toStringz((cast(ALClient)(cast(void*)client_ptr)).getString((key).to!string));
}

extern(C) void allib_save_attachments(ALClientHandle* client_ptr, const char* path) {
    (cast(ALClient)(cast(void*)client_ptr)).saveAttachments((path).to!string);
}

extern(C) void allib_load_attachments(ALClientHandle* client_ptr, const char* path) {
    (cast(ALClient)(cast(void*)client_ptr)).loadAttachments((path).to!string);
}

#ifndef ALLIB_C_WRAPPER_H
#define ALLIB_C_WRAPPER_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ALSessionHandle ALSessionHandle;
typedef struct ALClientHandle ALClientHandle;

typedef int (*ScriptCallback)(ALClientHandle* client);
typedef void (*EventCallback)(ALClientHandle* client, const char* event_name, const char* json_data);

typedef struct {
    char* name;
    int level;
} ALSlotItem;

typedef struct {
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
} ALSlots;

typedef struct {
    int hp, max_hp;
    int mp, max_mp;
    long xp;
    int attack, heal;
    double frequency;
    int speed, range;
    int armor, resistance;
    int level;
    int age;
    int rip;
    int afk;
    int moving;
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
} ALEntity;

typedef struct {
    char* category;
    long amount;
    int level;
} ALBankPack;

typedef struct {
    const char* id;
} ALChest;

// Session
ALSessionHandle* allib_create_session(const char* addr);
void allib_free_session(ALSessionHandle* session_ptr);
void allib_run_app(void);

// Client
ALClientHandle* allib_create_client(ALSessionHandle* session_ptr, const char* char_name, const char* server);
void allib_free_client(ALClientHandle* client_ptr);
void allib_start_client(ALClientHandle* client_ptr, ScriptCallback script_cb, EventCallback event_cb);

// Entity
ALEntity allib_get_entity(ALClientHandle* client_ptr);

// Movement
void allib_move(ALClientHandle* client_ptr, double x, double y);
void allib_move_precise(ALClientHandle* client_ptr, double x, double y, double fx, double fy);
int allib_smart_move(ALClientHandle* client_ptr, const char* dest);
int allib_smart_move_coords(ALClientHandle* client_ptr, double x, double y);
void allib_respawn(ALClientHandle* client_ptr);
void allib_town(ALClientHandle* client_ptr);
void allib_stop(ALClientHandle* client_ptr);

// Combat
void allib_change_target(ALClientHandle* client_ptr, const char* target_id);
void allib_attack(ALClientHandle* client_ptr, const char* target_id);
void allib_use_skill(ALClientHandle* client_ptr, const char* name);
int allib_can_use(ALClientHandle* client_ptr, const char* name);
int allib_is_on_cooldown(ALClientHandle* client_ptr, const char* name);
void allib_set_cooldown(ALClientHandle* client_ptr, const char* name, long ms);

// Inventory
int allib_equip(ALClientHandle* client_ptr, int num, const char* slot);
int allib_unequip(ALClientHandle* client_ptr, int slot);
int allib_use_slot(ALClientHandle* client_ptr, int slot);
int allib_use_item(ALClientHandle* client_ptr, const char* name);
void allib_use_hp(ALClientHandle* client_ptr);
void allib_use_mp(ALClientHandle* client_ptr);

// Interaction
int allib_send_gold(ALClientHandle* client_ptr, const char* name, int amount);
int allib_send_item(ALClientHandle* client_ptr, const char* name, int num, int quantity);
int allib_send_mail(ALClientHandle* client_ptr, const char* to, const char* subject, const char* message, int with_item);

// Party
int allib_send_party_invite(ALClientHandle* client_ptr, const char* name);
int allib_accept_party_invite(ALClientHandle* client_ptr, const char* name);
int allib_leave_party(ALClientHandle* client_ptr);
int allib_kick_party_member(ALClientHandle* client_ptr, const char* name);

// Stand
void allib_open_stand(ALClientHandle* client_ptr, int num);
void allib_close_stand(ALClientHandle* client_ptr);

// Banking
void allib_bank_deposit(ALClientHandle* client_ptr, int gold);
void allib_bank_withdraw(ALClientHandle* client_ptr, int gold);

// Utility
char* allib_find_closest_monster_of_type(ALClientHandle* client_ptr, const char* type);
double allib_distance(double x1, double y1, double x2, double y2);

// Getters
double allib_get_x(ALClientHandle* client_ptr);
double allib_get_y(ALClientHandle* client_ptr);
char* allib_get_id(ALClientHandle* client_ptr);

// Storage API
void allib_set_boolean(ALClientHandle* client_ptr, const char* key, int value);
int allib_get_boolean(ALClientHandle* client_ptr, const char* key);
void allib_set_integer(ALClientHandle* client_ptr, const char* key, int value);
int allib_get_integer(ALClientHandle* client_ptr, const char* key);
void allib_set_double(ALClientHandle* client_ptr, const char* key, double value);
double allib_get_double(ALClientHandle* client_ptr, const char* key);
void allib_set_string(ALClientHandle* client_ptr, const char* key, const char* value);
char* allib_get_string(ALClientHandle* client_ptr, const char* key);

// Attachment IO
void allib_save_attachments(ALClientHandle* client_ptr, const char* path);
void allib_load_attachments(ALClientHandle* client_ptr, const char* path);

#ifdef __cplusplus
}
#endif

#endif // ALLIB_C_WRAPPER_H

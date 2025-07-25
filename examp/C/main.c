#include "../../source/allib/allib.h"
#include <stdio.h>
#include <string.h>
#include <math.h>

extern void rt_init(); // D runtime init
extern void rt_term(); // D runtime terminate

const char* TARGET_NAME = "goo";
const double TARGET_X = -36;
const double TARGET_Y = 705;
const char* TARGET_MAP = "main";

int kill_goo_script(ALClientHandle* client_ptr) {
    ALEntity player = allib_get_entity(client_ptr);

    if (player.rip) {
        allib_respawn(client_ptr);
        printf("[WARN] Respawning\n");
        return 1000;
    }

    if (player.hp < player.max_hp / 2 && allib_can_use(client_ptr, "hp")) {
        allib_use_hp(client_ptr);
    }

    if (player.mp < player.max_mp / 2 && allib_can_use(client_ptr, "mp")) {
        allib_use_mp(client_ptr);
    }

    // Find target
    char* target_id = allib_find_closest_monster_of_type(client_ptr, TARGET_NAME);

    if (target_id != NULL) {
        ALEntity target = allib_get_target_entity(client_ptr);
        double dist = allib_distance_to_entity(client_ptr, target);

        printf("[INFO] %s attacking: %s\n", player.id, target_id);

        if (allib_can_use(client_ptr, "attack")) {
            if (dist > player.range) {
                printf("[INFO] %s moving towards target...\n", player.id);
                if (!player.moving) {
                    allib_move_to_entity(client_ptr, target);
                }
            } else {
                if (strcmp(player.target, target_id) != 0) {
                    allib_change_target(client_ptr, target_id);
                }
                allib_attack(client_ptr, target_id);
            }
        }
    } else {
        printf("[INFO] Can't find desired mob at location (%f, %f) on map %s\n", player.x, player.y, player.map);
        allib_smart_move_coords(client_ptr, TARGET_X, TARGET_Y);
    }

    return 500; // milliseconds
}

void event_handler(ALClientHandle* client, const char* event_name, const char* json_data) {
    printf("[EVENT] %s: %s\n", event_name, json_data);
}

int main() {
    rt_init();
    ALSessionHandle* session = allib_create_session();

    ALClientHandle* brute = allib_create_client(session, "FrumpyBrute", "ASIAI");
    ALClientHandle* ranger = allib_create_client(session, "FrumpyRanger", "ASIAI");
    ALClientHandle* healer = allib_create_client(session, "FrumpyHealer", "ASIAI");

    allib_start_client(brute, kill_goo_script, event_handler);
    allib_start_client(ranger, kill_goo_script, event_handler);
    allib_start_client(healer, kill_goo_script, event_handler);

    allib_run_app();

    rt_term();
    return 0;
}

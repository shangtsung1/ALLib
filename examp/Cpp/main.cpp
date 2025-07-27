#include "../../source/allib/allib.h"
#include <iostream>
#include <cstring>
#include <cmath>

extern "C" void rt_init(); // D runtime init
extern "C" void rt_term(); // D runtime terminate

const char* TARGET_NAME = "goo";
const double TARGET_X = -36;
const double TARGET_Y = 705;
const char* TARGET_MAP = "main";

int killGooScript(ALClientHandle* clientPtr) {
    ALEntity player = allib_get_entity(clientPtr);

    if (player.rip) {
        allib_respawn(clientPtr);
        std::cout << "[WARN] Respawning" << std::endl;
        return 1000;
    }

    if (player.hp < player.max_hp / 2 && allib_can_use(clientPtr, "hp")) {
        allib_use_hp(clientPtr);
    }

    if (player.mp < player.max_mp / 2 && allib_can_use(clientPtr, "mp")) {
        allib_use_mp(clientPtr);
    }

    // Find target
    char* targetId = allib_find_closest_monster_of_type(clientPtr, TARGET_NAME);

    if (targetId != nullptr) {
        ALEntity target = allib_get_target_entity(clientPtr);
        double dist = allib_distance_to_entity(clientPtr, target);

        std::cout << "[INFO] " << player.id << " attacking: " << targetId << std::endl;

        if (allib_can_use(clientPtr, "attack")) {
            if (dist > player.range) {
                std::cout << "[INFO] " << player.id << " moving towards target..." << std::endl;
                if (!player.moving) {
                    allib_move_to_entity(clientPtr, target);
                }
            } else {
                if (strcmp(player.target, targetId) != 0) {
                    allib_change_target(clientPtr, targetId);
                }
                allib_attack(clientPtr, targetId);
            }
        }
    } else {
        std::cout << "[INFO] Can't find desired mob at location (" << player.x << ", " << player.y << ") on map " << player.map << std::endl;
        allib_smart_move_coords(clientPtr, TARGET_X, TARGET_Y);
    }

    return 500; // milliseconds
}

void eventHandler(ALClientHandle* client, const char* eventName, const char* jsonData) {
    std::cout << "[EVENT] " << eventName << ": " << jsonData << std::endl;
}

int main() {
    rt_init();
    ALSessionHandle* session = allib_create_session();

    ALClientHandle* brute = allib_create_client(session, "FrumpyBrute", "ASIAI");
    ALClientHandle* ranger = allib_create_client(session, "FrumpyRanger", "ASIAI");
    ALClientHandle* healer = allib_create_client(session, "FrumpyHealer", "ASIAI");

    allib_start_client(brute, killGooScript, eventHandler);
    allib_start_client(ranger, killGooScript, eventHandler);
    allib_start_client(healer, killGooScript, eventHandler);

    allib_run_app();

    rt_term();
    return 0;
}

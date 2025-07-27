import std.stdio;
import std.datetime;

import core.thread;

import vibe.vibe : runApplication,runTask;
import allib;
import std.file;
import std.json;
import std.datetime;
import std.conv;

void main()
{
	ALSession session = ALSession.INSTANCE();
	ALClient frumpyBrute = session.createClient("FrumpyBrute");
	new Thread(() => initClient(frumpyBrute,JSONValue())).start();


	ALClient frumpyRanger = session.createClient("FrumpyRanger");
	new Thread(() => initClient(frumpyRanger,JSONValue())).start();

	ALClient frumpyHealer = session.createClient("FrumpyHealer");
	new Thread(() => initClient(frumpyHealer,JSONValue())).start();

	runApplication();
}

void initClient(ALClient c, JSONValue args) nothrow{
    try{
        c.start((ALClient a){
        	return killStuff(a, args);
        });
    }
    catch(Throwable t){
        try{
            logError(t);
        }catch(Throwable tt){
        }
    }
}


Duration killStuff(ALClient client, JSONValue args){

	string targetName = "goo";
    double targetX = -36;
    double targetY = 705;
    string targetMap = "main";

    if(args.type == JSONType.object){
        if("targetName" in args) targetName = args["targetName"].get!string;
        if("targetX" in args) targetX = args["targetX"].get!double;
        if("targetY" in args) targetY = args["targetY"].get!double;
        if("targetMap" in args) targetMap = args["targetMap"].get!string;
    }

	if (client.player.rip) {
        client.respawn();
        logWarn("Respawn");
        return 1000.msecs;
    }

    if (client.player.hp < client.player.max_hp / 2 && client.canUse("hp")){
        client.useHp();
    }
    if (client.player.mp < client.player.max_mp / 2 && client.canUse("mp")){
        client.useMp();
    }
    
    client.lootAll();
	Entity target = client.findClosestEntity((Entity e) {
            return e.type == targetName && !e.rip;
    });
	if(target.id !is null){
        logInfo(client.player.id," attacking: ", target.id);
        if(client.canUse("attack")){
			if (distance(client.player, target) > client.player.range) {
				logInfo(client.player.id," moving towards target...");
				if (!client.player.moving) {
					//client.smartMove(client.player.mapName,target.x, target.y);
					client.move(target.x, target.y);
				}
			}
			else{
				if(client.player.target != target.id){
					client.changeTarget(target.id, target.id);
				}
				client.attack(target.id);
			}
        }
	}
	else{
		logInfo("Can't find desired mob at location (", client.player.x, ", ",client.player.y, ") on map ", client.player.mapName);
		client.smartMove(targetMap,targetX,targetY);
	}
	return 500.msecs;
}
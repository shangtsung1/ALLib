import std.stdio;
import std.datetime;

import core.thread;

import vibe.vibe : runApplication,runTask;
import allib;



void main()
{
	ALSession session = ALSession.INSTANCE();
	ALClient frumpyBrute = session.createClient("FrumpyBrute");
	new Thread(() => initClient(frumpyBrute)).start();
	new ALViewer(frumpyBrute,400,300).start();


	ALClient frumpyRanger = session.createClient("FrumpyRanger");
	new Thread(() => initClient(frumpyRanger)).start();
	new ALViewer(frumpyRanger,400,300).start();

	ALClient frumpyHealer = session.createClient("FrumpyHealer");
	new Thread(() => initClient(frumpyHealer)).start();
	new ALViewer(frumpyHealer,400,300).start();

	runApplication();
}

void initClient(ALClient c) nothrow{
	try{
		c.start((ALClient a){
				switch(a.player.ctype){
					case "warrior":
					case "paladin":
					case "rogue":
					case "ranger":
					case "mage":
					case "priest":
						return killGoo(a);
						break;
					case "merchant":
						break;
					default:
						logError("unknown class",a.player.ctype);
				}
			 	return 1000.msecs;
			 });
	}
	catch(Throwable t){
		try{
			logError(t);
		}catch(Throwable tt){
		}
	}
}

string targetName = "goo";
float targetX = -36;
float targetY = 705;
string targetMap = "main";

Duration killGoo(ALClient client){
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
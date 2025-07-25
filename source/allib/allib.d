module allib.allib;

import allib.logger;
import allib.schema;
import allib.httpwrapper;

import core.sync.mutex;
import core.thread;

import std.datetime;
import std.conv;
import std.stdio;
import std.json;
import std.math;
import std.algorithm;
import std.string;
import std.array;
import std.range;
import std.regex;
import std.container;
import std.typecons;

import vibe.http.websockets;
import vibe.http.client;

static import allib.pathfinder;

alias Pathwalker = allib.pathfinder.PathWalker;
alias PathSegment = allib.pathfinder.PathSegment;
alias Pathfinder = allib.pathfinder.Pathfinder;


shared Mutex allib_instanceLock;
shared static this() {
    allib_instanceLock = new shared Mutex();
}

class ALSession{
    public:
        static shared GameData gameData;
        __gshared JSONValue G;
    private:
        static shared string token;
        static shared ALSession instance;



    public static ALSession INSTANCE(){
        allib_instanceLock.lock();
        scope(exit) allib_instanceLock.unlock();
        if(instance is null){
            instance = new shared ALSession("https://adventure.land");
        }
        return cast(ALSession)instance;
    }

    private shared this(string addr){
        allib.httpwrapper.ADDR = addr;
        auto loginResponse = allib.httpwrapper.login();
        if(loginResponse.length <= 0){
            logError("failed to login");
            throw new Exception("Failed to login.");
        }
        this.token = loginResponse;
        allib.httpwrapper.updateServersAndCharacters();
        logInfo("FoundCharacters:");
        string chars = "";
        foreach(chara ; characters){
            chars~=chara["name"].get!string~",";
        }
        logInfo("  ",chars);
        logInfo("FoundServers:");
        string servs = "";
        foreach(serv ; servers){
            servs~=serv["key"].get!string~",";
        }
        logInfo("  ",servs);
        allib.httpwrapper.grabG();
        gameData = GameData.fromJson(allib.httpwrapper.G);
        this.G = allib.httpwrapper.G;
    }

    public JSONValue[string] getCharacters(){
        return characters;
    }

    public JSONValue getCharacter(string name){
        foreach(chara ; characters){
            if(chara["name"].get!string == name){
                return chara;
            }
        }
        throw new Exception("Character not Found "~name);
    }

    public JSONValue[string] getServers(){
        return servers;
    }

    public JSONValue getServer(string key){
        foreach(serv ; servers){
            if(serv["key"].get!string == key){
                return serv;
            }
        }
        throw new Exception("Server not Found "~key);
    }

    public ALClient createClient(string charName,string server = null){
        if(server is null){
            if("home" in getCharacter(charName)){
                server = getCharacter(charName)["home"].get!string;
            }
            else{
                server = "USI";
            }
        }
        return new ALClient(this,getServer(server), getCharacter(charName),"wss");
    }
}

class ALClient{
    private:
        ALSession session;
        string protocol;
        WebSocket socket;
        string sid;

        Object*[string] attachments;
        bool running;
        bool awaitingAuth;
        long failTime = 15000;
        bool failed = false;
    public:
        JSONValue serverInfo;
        JSONValue character;
        
        Entity[string] monsters;
        Entity[string] players;
        Entity player;
        Chest[] chests;
        string[] party;
        long[string] nextSkill;
        BankPack[string] bankPacks;
        Pathwalker pathwalker;


    private this(ALSession session,JSONValue serverInfo, JSONValue character,string protocol){
        this.session = session;
        this.serverInfo = serverInfo;
        this.character = character;
        this.protocol = protocol;
        this.running = true;
        this.awaitingAuth = true;
        pathwalker = new Pathwalker(this);
    }

    public void resetClient(){
        awaitingAuth = true;
        monsters = typeof(monsters).init;
        players = typeof(players).init;
        pathwalker = new Pathwalker(this);
    }

    void start(Duration delegate(ALClient) script){
        fireInit();
        while(running){
            auto url = URL(protocol~"://" ~ serverInfo["addr"].get!string ~ ":" ~ serverInfo["port"].get!int.to!string ~ "/socket.io/?EIO=4&transport=websocket");
            HTTPClientSettings settings = new HTTPClientSettings;
            settings.readTimeout = 14.days;
            settings.connectTimeout = 14.days;
            settings.defaultKeepAliveTimeout = 5.seconds;
            try {
                socket = connectWebSocket(url,settings);
                logInfo("Waiting for connection...");
                while (!socket.connected && socket.closeCode() == 0) {
                    Thread.sleep(5.msecs);
                }
                logInfo("Connected!");
            } catch (Throwable t) {
                logError(t.msg, t," codes=",socket.closeCode," ",socket.closeReason);
                socket.close();
                return;
            }
            long lastPing = lastEpoch();
            long lastUpdate = lastEpoch();
            long nextScriptTime = lastEpoch();
            while (socket.connected && running && !failed) {
                try {
                    while (socket.dataAvailableForRead()) {
                        auto message = socket.receiveText();
                        processEngineIOMessage(message);
                    }

                    if (awaitingAuth) {
                        Thread.sleep(1.msecs);
                        continue;
                    }

                    long now = lastEpoch();
                    if (now - lastPing >= 3000) {
                        lastPing = now;
                        ping();
                    }

                    if (now - lastUpdate >= 50) {
                        lastUpdate = now;
                        if (!player.rip) {
                            lerpEntity(player);
                        }
                        pathwalker.update();
                    }

                    if (now >= nextScriptTime) {
                        auto waitDuration = script(this);
                        nextScriptTime = lastEpoch() + waitDuration.total!"msecs";
                    }

                    fireUpdateLoop();

                } catch (Throwable t) {
                    logError(t, t.msg);
                    failed = true;
                    resetClient();
                    try socket.close(); catch(Throwable) {}
                    socket = null;
                    break; // break inner loop to reconnect
                }
            }
            logError("Disconnected, waiting ",failTime," seconds");
            Thread.sleep(failTime.msecs);                
        }
    }

    long lastEpoch(){
        return cast(ulong)round(Clock.currTime.stdTime()/10000);
    }

    private void processEngineIOMessage(string message) {
        if (message.length == 0) return;
        switch (message[0]) {
            case '0':
                logVerb(message);
                auto json = parseJSON(message[1..$]);
                int pingInterval = json["pingInterval"].get!int;
                int pingTimeout = json["pingTimeout"].get!int;
                handleOpen(json);
                break;
            case '1':
                logWarn("Server closed the connection");
                resetClient();
                break;
            case '2':
                logDebug("Pong!",message);
                sendPong();
                break;
            case '4':
                logVerb(message);
                processSocketIOMessage(message[1..$]);
                break;
            default:
                logError("Unknown message: ", message);
                break;
        }
    }

    private void handleOpen(JSONValue json) {
        try {
            if (json.type == JSONType.object && json["sid"].type == JSONType.string) {
                sid = json["sid"].str;
            }
            socket.send("40");
        } catch (Throwable t) {
            logError("Error parsing open message: ", t.msg);
        }
    }

    private void sendPong() {
        socket.send("3");
    }

    private void processSocketIOMessage(string message) {
        if (message.length < 1) return;

        switch (message[0]) {
            case '0':
                logInfo("Socket.IO: Connect packet");
                break;
            case '1':
                logInfo("Socket.IO: Disconnect packet", message);
                resetClient();
                break;
            case '2':
                handleEvent(message[1..$]);
                break;
            case '3':
                logInfo("Socket.IO: Ack packet: ", message[1..$]);
                break;
            case '4':
                logInfo("Socket.IO: Error packet: ", message[1..$]);
                break;
            default:
                logError("unhandled message event id = ", message[0]);
                break;
        }
    }

    private void handleEvent(string payload) {
        try {
            auto json = parseJSON(payload);
            if (json.type == JSONType.array && json.array.length > 0) {
                string eventName = json.array[0].str;
                string[] args;
                foreach (arg; json.array[1..$]) {
                    args ~= arg.to!string;
                }
                parsePacket(eventName, args);
            }
        } catch (Exception e) {
            logError("Error parsing event: ", e.msg, payload, e);
        }
    }
    mixin ListenerSet!("Init");
    mixin ListenerSet!("UpdateLoop");


    mixin ListenerSet!("Invite", string);
    mixin ListenerSet!("UI", JSONValue);
    mixin ListenerSet!("Hit", JSONValue);
    mixin ListenerSet!("Death", JSONValue);
    mixin ListenerSet!("DisappearingText", JSONValue);
    mixin ListenerSet!("Action", JSONValue);
    mixin ListenerSet!("Disappear", JSONValue);
    mixin ListenerSet!("Drop", Chest);
    mixin ListenerSet!("ChestOpened", string);
    mixin ListenerSet!("Welcome", JSONValue);
    mixin ListenerSet!("Entities", JSONValue);
    mixin ListenerSet!("Start", JSONValue);
    mixin ListenerSet!("Player", JSONValue);
    mixin ListenerSet!("NewMap", JSONValue);
    mixin ListenerSet!("PingTrig", JSONValue);
    mixin ListenerSet!("PingAck", JSONValue);
    mixin ListenerSet!("PartyUpdate", JSONValue);
    mixin ListenerSet!("Correction", JSONValue);
    mixin ListenerSet!("Eval", JSONValue);
    mixin ListenerSet!("SkillTimeout", JSONValue);
    mixin ListenerSet!("Emotion", JSONValue);
    mixin ListenerSet!("GameEvent", JSONValue);
    mixin ListenerSet!("Notice", JSONValue);
    mixin ListenerSet!("ServerMessage", JSONValue);
    mixin ListenerSet!("GameResponse", JSONValue);
    mixin ListenerSet!("QData", JSONValue);
    mixin ListenerSet!("Upgrade", JSONValue);
    mixin ListenerSet!("GameLog", JSONValue);
    void parsePacket(string event,string[] msgs){
        try
        {
            logVerb(event);
            switch(event){
                case "game_error":
                    logError("GameError: "~msgs[0]);
                    if(msgs[0]== "Failed: ingame"){
                        resetClient();
                    }
                    auto m = match(msgs[0], `Failed: wait_(\d+)_seconds`);
                    if (m.hit) {
                        int seconds = to!int(m.captures[1]);
                        failTime = 1000*seconds;
                        failed = true;
                        resetClient();
                    }
                    return;
                case "disconnect_reason":
                    resetClient();
                    return;
                case "code_eval":
                    logInfo("eval",msgs[0]);
                    handleEval(msgs[0]);
                    return;
                default:break;
            }
            JSONValue msg = parseJSON(msgs[0]);
            switch(event){
                case "welcome":
                    sendWelcome();
                    fireWelcome(msg);
                    break;
                case "entities":
                    parseEntities(msg,false);
                    fireEntities(msg);
                    break;
                case "start":
                    parseStart(msg);
                    awaitingAuth=false;
                    fireStart(msg);
                    break;
                case "player":
                    players[msg["id"].get!string] = Entity.fromJson(msg);
                    player = players[msg["id"].get!string];
                    firePlayer(msg);
                    break;
                case "new_map":
                    monsters = typeof(monsters).init;
                    players = typeof(players).init;
                    parseEntities(msg,true);
                    if(player.id !is null)
                        pathwalker.onMapChanged(player.mapName, player.x,player.y);
                    fireNewMap(msg);
                    break;
                case "ping_trig":
                    JSONValue data = JSONValue([
                        "id": JSONValue(msg["id"].get!string)
                    ]);
                    emit("ping_ack",data);
                    firePingTrig(msg);
                    break;
                case "invite":
                    fireInvite(msg["name"].get!string);
                    break;
                case "ui":
                    fireUI(msg);
                    break;
                case "hit":
                    fireHit(msg);
                break;
                case "death":
                    fireDeath(msg);
                break;
                case "notthere":
                case "disappear":
                    if("id" in msg){
                        auto id = msg["id"].get!string;
                        if(id in monsters){
                            monsters.remove(id);
                        }
                        else if(id in players){
                            players.remove(id);
                        }
                        if(id == player.id){
                            player.rip=true;
                        }
                    }
                    fireDisappear(msg);
                break;
                case "disappearing_text":
                    fireDisappearingText(msg);
                break;
                case "action":
                    fireAction(msg);
                break;
                case "drop":
                    //{id:id}
                    Chest c = new Chest(msg["id"].get!string);
                    chests ~= c;
                    fireDrop(c);
                    break;
                case "chest_opened":
                    chests = chests.filter!(c => c.id != msg["id"].get!string).array;
                    fireChestOpened(msg["id"].get!string);
                    break;

                case "ping_ack":
                    firePingAck(msg);
                break;
                case "party_update":
                    party.length=0;
                    if("list" in msg.object){
                        if(msg["list"].type == JSONType.array){
                            foreach(s; msg["list"].array){
                                party~=s.get!string;
                            }
                        }
                    }
                    firePartyUpdate(msg);
                break;
                case "correction":
                    string id = player.id;
                    players[id].x = msg["x"].get!double;
                    players[id].y = msg["y"].get!double;
                    players[id].going_x = players[id].x;
                    players[id].going_y = players[id].y;
                    players[id].moving = false;
                    players[id].from_x = players[id].x;
                    players[id].from_y = players[id].y;
                    player = players[id];
                    fireCorrection(msg);
                break;

                case "eval":
                    handleEval(msg["code"].get!string);
                    fireEval(msg);
                break;
                case "skill_timeout":
                    long ms = msg["ms"].get!long;
                    //long penalty = msg["penalty"].get!long;
                    string name = msg["name"].get!string;
                    nextSkill[name] = lastEpoch()+ms;
                    fireSkillTimeout(msg);
                break;

                case "emotion":
                    fireEmotion(msg);
                    break;

                case "game_event":
                    fireGameEvent(msg);
                    break;

                case "notice":
                    fireNotice(msg);
                    break;

                case "server_message":
                    fireServerMessage(msg);
                    break;

                case "game_response":
                    logInfo("GameResponse: ",msg);
                    fireGameResponse(msg);
                    break;

                case "q_data":
                    fireQData(msg);
                    break;

                case "upgrade":
                    fireUpgrade(msg);
                    break;

                case "game_log":
                    fireGameLog(msg);
                    logInfo("TODOE=",event," MSG=",msg);
                    //if(msg.type == JSONType.string && msg.get!string == "This might have happened if your network is too slow"){
                    //    socket.disconnect();
                    //}
                break;
                default:
                    logError("EVENT=",event," MSG=",msg);
                    break;
            }
        }
        catch(Throwable e){
            logError(e);
            import core.stdc.stdlib;
            //exit(1);
            resetClient();
        }
    }

        double lerp(double a, double b, double t) {
        return a + (b - a) * t;
    }

    void lerpEntity(Entity entity) {
        if(!entity.moving){
            return;
        }
        long currentTime = lastEpoch();

        double elapsedTime = (currentTime - entity.move_started) / 1000.0;

        double totalDistance = distance(entity.from_x, entity.from_y, entity.going_x, entity.going_y);

        if (totalDistance == 0.0) {
            // Snap to destination
            entity.x=entity.going_x;
            entity.y=entity.going_y;
            entity.moving = false;
            return;
        }

        double fraction = (entity.speed * elapsedTime) / totalDistance;

        fraction = min(fraction, 1.0);
        entity.x = (lerp(entity.from_x, entity.going_x, fraction));
        entity.y = (lerp(entity.from_y, entity.going_y, fraction));

        if (fraction >= 1.0) {
            entity.moving = false;
        }
    }

    void parseStart(JSONValue msg){
        //TODO: parse bank
        parseEntities(msg["entities"],false);
        msg.object.remove("entities");
        players[msg["id"].get!string] = Entity.fromJson(msg);
        logInfo("LoggedIn:",players[msg["id"].get!string].id);
        player = players[msg["id"].get!string];
    }

    void parseEntities(JSONValue msg, bool b) {
        if(!b){
            string type = msg["type"].get!string;
            if (type == "all" && awaitingAuth) {
                login();
                return;
            }
        }
        // === Players ===
        if ("players" in msg) {
            auto playerz = msg["players"].array;
            foreach (playar; playerz) {
                string id = playar["id"].get!string;
                players[id] = Entity.fromJson(playar);
                if(id == player.id){
                    player = players[id];
                }
            }
        }
        // === Monsters ===
        if ("monsters" in msg) {
            auto monsterz = msg["monsters"].array;
            foreach (monster; monsterz) {
                string id = monster["id"].get!string; 
                monsters[id] = Entity.fromJson(monster);
            }
        }
    }

    void emit(string eventName, JSONValue arg) {
        emit(eventName, [arg]);
    }

    void emit(string eventName) {
        string payload = "42[\"" ~ eventName ~ "\"]";
        socket.send(payload);
    }

    void emit(string eventName, JSONValue[] args) {
        string payload = "42[\"" ~ eventName ~ "\"";
        foreach (arg; args) {
            payload ~= "," ~ arg.toString();
        }
        payload ~= "]";
        socket.send(payload);
    }

    int pingCounter = 10000;
    void ping(){
        JSONValue data = JSONValue([
            "id": JSONValue((pingCounter++).to!string)
        ]);
        emit("ping_trig",data);
    }

    void sendWelcome(){
        JSONValue data = JSONValue([
            "success": JSONValue(1),
            "width": JSONValue(3840),
            "height": JSONValue(2160),
            "scale": JSONValue(2)
        ]);
        emit("loaded",data);
    }

    void login() {
        string auth = session.token;
        auto user = auth[auth.indexOf("=") + 1 .. auth.indexOf("-")];
        auto token = auth[auth.indexOf("-") + 1 .. $];
        auto charId = character["id"].get!string;
        JSONValue data = JSONValue.init;
        data.object = [
            "user": JSONValue(user),
            "character": JSONValue(charId),
            "code_slot": JSONValue(charId),
            "auth": JSONValue(token),
            "width": JSONValue(3840),
            "height": JSONValue(2160),
            "scale": JSONValue(2),
            "passphrase": JSONValue(""),
            "no_html": JSONValue(""),
            "no_graphics": JSONValue("")
        ];
        emit("auth", data);
        ping();
    }

    void moveTowards( double targetX, double targetY, double fraction) {
        double currentX = player.x;
        double currentY = player.y;

        double newX = currentX + (targetX - currentX) * fraction;
        double newY = currentY + (targetY - currentY) * fraction;

        move(newX, newY);
    }

    void moveTowards(ALClient target, double fraction) {
        moveTowards(target.player.x,target.player.y,fraction);
    }

    void moveTowards(Entity target, double fraction) {
        moveTowards(target.x,target.y,fraction);
    }

    bool isOnCooldown(string skill) {
        auto skills = session.G["skills"];
        if (skill in skills.object) {
            auto skillObj = skills[skill];
            if ("share" in skillObj.object) {
                string sharedSkill = skillObj["share"].get!string;
                return isOnCooldown(sharedSkill);
            }
        }
        if (skill in nextSkill && lastEpoch() < nextSkill[skill]) {
            return true;
        }
        return false;
    }

    void setCooldown(string name, long ms) {
        auto skills = session.G["skills"];
        long time = 0;

        if (ms < 0 && name in skills.object) {
            auto skillObj = skills[name];

            bool hasCooldown = ("cooldown" in skillObj.object) !is null;
            bool hasReuseCooldown = ("reuse_cooldown" in skillObj.object) !is null;

            if (hasCooldown || hasReuseCooldown) {
                if (hasCooldown && skillObj["cooldown"].type == JSONType.integer) {
                    time = skillObj["cooldown"].get!long;
                } else if (hasReuseCooldown && skillObj["reuse_cooldown"].type == JSONType.integer) {
                    time = skillObj["reuse_cooldown"].get!long;
                }
            } else if ("share" in skillObj.object) {
                string sharedSkill = skillObj["share"].get!string;
                auto sharedObj = skills[sharedSkill];
                long sharedCooldown = sharedObj["cooldown"].get!long;
                long multiplier = "cooldown_multiplier" in skillObj.object ? skillObj["cooldown_multiplier"].get!long : 1;
                time = sharedCooldown * multiplier;
            }
        } else if (name == "attack" && ms < 0) {
            time = cast(long)(1000.0 / player.frequency);
        }

        if (time < 0) time = 0;
        nextSkill[name] = (lastEpoch()+time);
    }


    void pot_timeout(long ms)
    {
        nextSkill["use_hp"] = lastEpoch()+ms;
        nextSkill["use_mp"] = lastEpoch()+ms;
    }

    void handleEval(string payload)
    {
        auto m = payload.matchFirst(regex(r"^([a-zA-Z_][a-zA-Z0-9_]*)\((.*)\)$"));
        if (m)
        {
            string functionName = m.captures[1].strip;
            string argsRaw = m.captures[2].strip;

            // Dispatch
            switch (functionName)
            {
                case "pot_timeout":
                    long arg = to!long(argsRaw);
                    pot_timeout(arg);
                    break;

                default:
                    writeln("Unknown eval function: ", functionName);
                    break;
            }
        }
        else
        {
            writeln("Invalid eval format: ", payload);
        }
    }

    bool canUse(string name)
    {
        if(name !in nextSkill || lastEpoch()>nextSkill[name]) return true;
        return false;
    }

    void lootAll(){
        foreach(chest; chests){
            openChest(chest.getId());
        }
    }

    void sendSkill(string name, string[] ids) {
        JSONValue jo = JSONValue.init;
        jo.object = ["name": JSONValue(name), "ids": JSONValue(ids)];
        emit("skill", jo);
    }

    void transport(string targetMap, double spawn) {
        JSONValue transportData = JSONValue.init;
        transportData.object = ["to": JSONValue(targetMap)];

        if (spawn == -1) {
            int defaultSpawn = session.G["npcs"]["transporter"]["places"][targetMap].get!int;
            transportData["s"] = JSONValue(defaultSpawn);
        } else {
            transportData["s"] = JSONValue(spawn);
        }
        //writeln("transport", transportData);
        emit("transport", transportData);
    }

    void openChest(string id) { emit("open_chest", json(["id": JSONValue(id)])); }
    void join(string id) { emit("join", json(["name": JSONValue(id)])); }
    void leaveGoo() { emit("transport", json(["s": JSONValue(9), "to": JSONValue("main")])); }
    void changeTarget(string id, string xid) {
        player.target=id;
        players[player.id] = player;
        emit("target", json(["id": JSONValue(id), "xid": JSONValue(xid)]));
    }

    bool move(double x, double y) {
        return move(x,y,player.x,player.y);
    }

    bool move(double x, double y, double fromX, double fromY) {
        if (!x.isFinite || !y.isFinite || !fromX.isFinite || !fromY.isFinite) return false;
        player.from_x = fromX;
        player.from_y = fromY;
        player.going_x = x;
        player.going_y = y;
        player.move_started = lastEpoch();//TODO:??
        player.moving = true;
        players[player.id] = player;
        emit("move", json([
            "x": JSONValue(fromX), "y": JSONValue(fromY),
            "going_x": JSONValue(x), "going_y": JSONValue(y),
            "m": JSONValue(player.m)
        ]));
        return true;
    }

    Entity findClosestEntity(bool delegate(Entity) predicate) {
        Entity closest;
        double closestDist = double.max;

        foreach (e; players.byValue) {
            if (predicate(cast(Entity)e)) {
                double dist = distance(player.x, player.y, e.x, e.y);
                if (dist < closestDist) {
                    closestDist = dist;
                    closest = cast(Entity)e;
                }
            }
        }

        foreach (e; monsters.byValue) {
            if (predicate(cast(Entity)e)) {
                double dist = distance(player.x, player.y, e.x, e.y);
                if (dist < closestDist) {
                    closestDist = dist;
                    closest = cast(Entity)e;
                }
            }
        }
        return closest;
    }

    Entity findClosestMonsterByType(string type) {
        Entity closest;
        double closestDist = double.max;

        foreach (e; monsters.byValue) {
            if ((e.type == type) && !e.rip) {
                double dist = distance(player.x, player.y, e.x, e.y);
                if (dist < closestDist) {
                    closestDist = dist;
                    closest = cast(Entity)e;
                }
            }
        }
        return closest;
    }

    Entity[] findClosestEntities(bool delegate(Entity) predicate, int limit, bool searchMonsters = true,bool searchPlayers = true) {
        // Select the correct map and convert to Entity[]
        Entity[] entitiesArray;

        if (searchMonsters && searchPlayers) {
            entitiesArray = chain(
                players.byValue.map!(p => cast(Entity)p),
                monsters.byValue.map!(m => cast(Entity)m)
            ).array;
        } else if (searchPlayers) {
            entitiesArray = players.byValue.map!(p => cast(Entity)p).array;
        } else if (searchMonsters) {
            entitiesArray = monsters.byValue.map!(m => cast(Entity)m).array;
        } else {
            return [];
        }

        // Filter by predicate and sort by distance ascending
        auto filteredSorted = entitiesArray
            .filter!(e => predicate(e))
            .map!(e => tuple(e, distance(player.x, player.y, e.x, e.y)))
            .array;

        filteredSorted.sort!((a, b) => a[1] < b[1]);

        // Take up to limit closest entities
        Entity[] results;
        foreach (i; 0 .. filteredSorted.length.min(limit)) {
            results ~= filteredSorted[i][0];
        }

        return results;
    }

    bool useSkill(string name, Nullable!Entity targete = Nullable!Entity.init, string arg = null) {
        JSONValue payload = JSONValue.init;
        string target = targete.isNull() || targete.get().id is null
            ? null
            : targete.get().id;

        if (name == "use_hp" || name == "hp") {
            return use("hp");
        } else if (name == "use_mp" || name == "mp") {
            return use("mp");
        } else if (name == "regen_hp") {
            payload["item"] = JSONValue("hp");
            emit("use", payload);
            return true;
        } else if (name == "regen_mp") {
            payload["item"] = JSONValue("mp");
            emit("use", payload);
            return true;
        } else if (name == "stop") {
            move(player.x, player.y + 0.00001, player.x, player.y);
            emit("stop");
            return true;
        } else if (name == "use_town" || name == "town") {
            if (player.rip) {
                emit("respawn");
                return true;
            } else {
                emit("town");
                return true;
            }
        } else if (name == "3shot" || name == "5shot") {
            Entity[] targets;
            if (!targete.isNull()) {
                targets = [targete.get()];
            } else {
                if (name == "3shot") {
                    targets = findClosestEntities(a => distance(a, cast(Entity)player) < player.range - 2, 3);
                } else {
                    targets = findClosestEntities(a => distance(a, cast(Entity)player) < player.range - 2, 3, true, false);
                }
            }
            if (targets.length == 0) return false;

            auto ids = targets.map!(t => JSONValue(t.id)).array;
            payload["name"] = JSONValue(name);
            payload["ids"] = JSONValue(ids);
            emit("skill", payload);
            return true;
        }

        auto skills = session.G["skills"];
        if (skills.type == JSONType.object && name in skills.object) {
            auto skillObj = skills[name];
            payload["name"] = JSONValue(name);
            if (skillObj.type == JSONType.object && "target" in skillObj.object && target !is null) {
                payload["id"] = JSONValue(target);
            }
            emit("skill", payload);
            return true;
        }

        payload["name"] = JSONValue(name);
        emit("skill", payload);
        return false;
    }

    bool useSkill(string name, Entity targete) {
        return useSkill(name, Nullable!Entity(targete), null);
    }

    bool useSkill(string name) {
        return useSkill(name, Nullable!Entity.init, null);
    }



    bool attack(string id) {
        emit("attack", json(["id": JSONValue(id)]));
        return true;
    }

    bool equip(int num, string slot) {
        if (num < 0) { writeln("Can't equip ", num); return false; }
        auto payload = json(["num": JSONValue(num)]);
        if (slot !is null) payload["slot"] = JSONValue(slot);
        emit("equip", payload);
        return true;
    }

    bool unequip(int slot) { emit("unequip", json(["slot": JSONValue(slot)])); return true; }
    bool use(int slot) { emit("equip", json(["num": JSONValue(slot)])); return true;}
    bool use(string item) { emit("use", json(["item": JSONValue(item)])); return true;}
    void useMp(){
        use("mp");
    }
    void useHp(){
        use("hp");
    }
    void respawn() { emit("respawn"); }
    void setHome() { emit("set_home"); }

    void bankDeposit(int gold) { emit("bank", json(["operation": JSONValue("deposit"), "amount": JSONValue(gold)])); }
    void bankWithdraw(int gold) { emit("bank", json(["operation": JSONValue("withdraw"), "amount": JSONValue(gold)])); }

    void bankStore(int num, string pack, int packNum) {
        emit("bank", json([
            "operation": JSONValue("swap"),
            "pack": JSONValue(pack), "str": JSONValue(packNum), "inv": JSONValue(num)
        ]));
    }

    void bankRetrieve(string pack, int packNum, int num = -1) {
        emit("bank", json([
            "operation": JSONValue("swap"),
            "pack": JSONValue(pack), "str": JSONValue(packNum), "inv": JSONValue(num)
        ]));
    }

    void bankSwap(string pack, int a, int b) {
        emit("bank", json([
            "operation": JSONValue("move"),
            "pack": JSONValue(pack), "a": JSONValue(a), "b": JSONValue(b)
        ]));
    }

    void swap(int a, int b) { emit("imove", json(["a": JSONValue(a), "b": JSONValue(b)])); }

    bool sendGold(string receiver, int gold) {
        if (receiver is null) { writeln("No receiver sent to send_gold"); return false; }
        emit("send", json(["name": JSONValue(receiver), "gold": JSONValue(gold)]));
        return true;
    }

    bool sendItem(string receiver, int num, int quantity = 1) {
        if (receiver is null) { writeln("No receiver sent to send_item"); return false; }
        emit("send", json(["name": JSONValue(receiver), "num": JSONValue(num), "q": JSONValue(quantity)]));
        return true;
    }

    bool sendCx(string receiver, int cx) {
        if (receiver is null) { writeln("No receiver sent to send_cx"); return false; }
        emit("send", json(["name": JSONValue(receiver), "cx": JSONValue(cx)]));
        return true;
    }

    bool sendMail(string to, string subject, string message, bool item) {
        emit("mail", json([
            "to": JSONValue(to), "subject": JSONValue(subject),
            "message": JSONValue(message), "item": JSONValue(item)
        ]));
        return true;
    }

    bool sendPartyInvite(string name, bool isRequest) {
        emit("party", json([
            "event": JSONValue(isRequest ? "request" : "invite"),
            "name": JSONValue(name)
        ]));
        return true;
    }

    bool sendPartyRequest(string name) { return sendPartyInvite(name, true); }
    bool acceptPartyInvite(string name) { emit("party", json(["event": JSONValue("accept"), "name": JSONValue(name)])); return true; }
    bool acceptPartyRequest(string name) { emit("party", json(["event": JSONValue("raccept"), "name": JSONValue(name)])); return true; }
    bool leaveParty() { emit("party", json(["event": JSONValue("leave")])); return true; }
    bool kickPartyMember(string name) { emit("party", json(["event": JSONValue("kick"), "name": JSONValue(name)])); return true; }
    bool acceptMagiport(string name) { emit("magiport", json(["name": JSONValue(name)])); return true; }
    bool unfriend(string name) { emit("friend", json(["event": JSONValue("unfriend"), "name": JSONValue(name)])); return true; }

    void open_stand(int num) {
        if (num == -1) { writeln("Can't open stand, no stand"); return; }
        emit("merchant", json(["num": JSONValue(num)]));
    }

    void close_stand() { emit("merchant", json(["close": JSONValue(1)])); }
    void exchange(int slot, int q) { emit("exchange", json(["item_num": JSONValue(slot), "q": JSONValue(q)])); }
    void buy_with_gold(string name, int quantity) { emit("buy", json(["name": JSONValue(name), "quantity": JSONValue(quantity)])); }
    void buy_with_shells(string name, int quantity) { emit("buy_with_cash", json(["name": JSONValue(name), "quantity": JSONValue(quantity)])); }

    void compound(int item0, int item1, int item2, int scroll, int offering, bool calculate, int clevel) {
        JSONValue jo = JSONValue.init;
        jo.object = [
            "items": JSONValue([item0, item1, item2]),
            "scroll_num": JSONValue(scroll),
            "clevel": JSONValue(clevel),
            "calculate": JSONValue(calculate)
        ];
        if (offering > -1) jo["offering_num"] = JSONValue(offering);
        emit("compound", jo);
    }

    void upgrade(int item, int scroll, int offering, bool calculate, int clevel) {
        JSONValue jo = JSONValue.init;
        jo.object = [
            "item_num": JSONValue(item), "scroll_num": JSONValue(scroll),
            "clevel": JSONValue(clevel), "calculate": JSONValue(calculate)
        ];
        if (offering > -1) jo["offering_num"] = JSONValue(offering);
        emit("upgrade", jo);
    }

    void leaveJail() { emit("leave"); }
    void sell(int slot, int quantity = 1) { emit("sell", json(["num": JSONValue(slot), "quantity": JSONValue(quantity)])); }
    void stop() { emit("stop"); }
    void town() { emit("town"); }
    void sendSkill(string name, string target) { emit("skill", json(["id": JSONValue(target), "name": JSONValue(name)])); }
    void sendSkill(string name) { emit("skill", json(["name": JSONValue(name)])); }





    bool smartMove(ALClient client) {
        return smartMove(client.player.mapName,client.player.x,client.player.y);
    }

    void smartMoveImpl(string map, double x, double y) {
        auto G = session.G;

        if (map.length == 0) {
            writeln("Failed to recognize smartMove target: map is empty.");
            return;
        }

        JSONValue mapData;
        if (map in G["maps"].object) {
            mapData = G["maps"][map];
        } else {
            mapData = JSONValue();
        }

        if (map == "jail") {
            writeln("Leave Jail??? ", map);
            leaveJail();
            return;
        } else if (map == "goobrawl") {
            writeln("Leave Goo??? ", map);
            leaveGoo();
            return;
        }

        if (mapData.isNull() || !("doors" in mapData.object) || mapData["doors"].array.length == 0) {
            writeln("Failed to find door to map: ", map);
            return;
        }

        JSONValue geom;
        if (map in G["geometry"].object) {
            geom = G["geometry"][map];
        } else {
            geom = JSONValue();
        }

        if (geom.type == JSONType.object) {
            double minX = "min_x" in geom.object ? geom["min_x"].get!float : -double.infinity;
            double maxX = "max_x" in geom.object ? geom["max_x"].get!float : double.infinity;
            double minY = "min_y" in geom.object ? geom["min_y"].get!float : -double.infinity;
            double maxY = "max_y" in geom.object ? geom["max_y"].get!float : double.infinity;

            if (x <= minX || x >= maxX || y <= minY || y >= maxY) {
                writeln("Cannot walk outside the map bounds: ", map, " target=(", x, ", ", y, ")");
                return;
            }
        }

        smartMove(map, x, y);
    }

    bool smartMove(string targetMap, double targetX, double targetY) {
        //TODO: do this in another thread so we dont fall behind on our pinging.
        if(pathwalker.hasPath())return false;
        import std.datetime.stopwatch;
        auto sw = StopWatch(AutoStart.yes);
        auto pf = new Pathfinder(this, player.mapName, player.x, player.y, targetMap, targetX, targetY);
        PathSegment[] path = pf.findPath();
        if (path.length == 0) {
            writeln("Failed to fetch or empty path");
            return false;
        }

        pathwalker.setPath(path);
        auto elapsedMs = sw.peek.total!"msecs";
        if(pathwalker.hasPath()){
            writeln("Path found in ",elapsedMs);
            return true;
        }
        else{
            writeln("Path not found");
            return false;
        }
    }

    void smartMove(string to) {
        string map = "";
        double tx, ty;

        auto G = session.G;

        if (to == "town") to = "main";

        if (to == "upgrade" || to == "compound") {
            map = "main"; tx = -204; ty = -129;
        } else if (to == "exchange") {
            map = "main"; tx = -26; ty = -432;
        } else if (to == "bank") {
            map = "bank"; tx = -1; ty = -258;
        } else if (to == "potions") {
            string pMap = player.mapName;
            if (pMap == "halloween") {
                map = "halloween"; tx = 149; ty = -182;
            } else if (["winterland", "winter_inn", "winter_cave"].canFind(pMap)) {
                map = "winter_inn"; tx = -84; ty = -173;
            } else {
                map = "main"; tx = 56; ty = -122;
            }
        } else if (to == "scrolls") {
            map = "main"; tx = -465; ty = -71;
        } else if (G.type == JSONType.object && "monsters" in G.object && to in G["monsters"].object) {
            foreach (mapName, mapData; G["maps"].object) {
                if ("monsters" in mapData.object) {
                    foreach (pack; mapData["monsters"].array) {
                        if (pack["type"].get!string != to) continue;
                        bool ignore = "ignore" in pack.object ? pack["ignore"].boolean : false;
                        bool instance = "instance" in pack.object ? pack["instance"].boolean : false;

                        if (ignore || instance) continue;

                        if ("boundaries" in pack.object) {
                            auto boundary = pack["boundaries"].array[0].array;
                            map = boundary[0].get!string;
                            tx = (boundary[1].integer + boundary[3].integer) / 2.0;
                            ty = (boundary[2].integer + boundary[4].integer) / 2.0;
                            goto found;
                        } else if ("boundary" in pack.object) {
                            auto boundary = pack["boundary"].array;
                            map = mapName;
                            tx = (boundary[0].integer + boundary[2].integer) / 2.0;
                            ty = (boundary[1].integer + boundary[3].integer) / 2.0;
                            goto found;
                        }
                    }
                }
            }
        }

    found:
        if (map.length == 0) {
            writeln("Unknown smartMove target: ", to);
            return;
        }
        smartMoveImpl( map, tx, ty);
    }

    void smartMove(double[2] coords) {
        string map = player.mapName;
        smartMoveImpl(map, coords[0], coords[1]);
    }

    void smartMove(JSONValue dest) {
        if (dest.type == JSONType.string) {
            smartMove(dest.str);
        } else if (dest.type == JSONType.array && dest.array.length >= 2) {
            smartMove([dest[0].get!float, dest[1].get!float]);
        } else if (dest.type == JSONType.object) {
            string map = "map" in dest.object ? dest["map"].get!string : player.mapName;
            double x = "x" in dest.object ? dest["x"].get!float : player.x;
            double y = "y" in dest.object ? dest["y"].get!float : player.y;
            smartMoveImpl( map, x, y);
        } else {
            writeln("Unsupported JSONValue for smartMove: ", dest);
        }
    }

    void smartMove(Entity target) {
        smartMoveImpl(target.mapName, target.x, target.y);
    }





    void setBoolean(string key, bool value) {
        attachments[key] = cast(Object*)(new BooleanObject(value));
    }
    
    bool getBoolean(string key) {
        auto obj = attachments.get(key, null);
        if (auto bo = cast(BooleanObject) obj) {
            return bo.value;
        }
        return false;
    }

    void setInteger(string key, int value) {
        attachments[key] = cast(Object*)new IntegerObject(value);
    }
    
    int getInteger(string key) {
        auto obj = attachments.get(key, null);
        if (auto io = cast(IntegerObject) obj) {
            return io.value;
        }
        return 0;
    }

    void setDouble(string key, double value) {
        attachments[key] = cast(Object*)new DoubleObject(value);
    }
    
    double getDouble(string key) {
        auto obj = attachments.get(key, null);
        if (auto dbl = cast(DoubleObject) obj) {
            return dbl.value;
        }
        return double.nan;
    }

    void setString(string key, string value) {
        attachments[key] = cast(Object*)new StringObject(value);
    }
    
    string getString(string key) {
        auto obj = attachments.get(key, null);
        if (auto str = cast(StringObject) obj) {
            return str.value;
        }
        return null;
    }
    void saveAttachments( string filename) {
        JSONValue[] entries;

        foreach (key, obj; attachments) {
            JSONValue entry;

            if (auto bo = cast(BooleanObject)obj) {
                entry = parseJSON(`{"key": "` ~ key ~ `", "type": "boolean", "value": ` ~ to!string(bo.value) ~ `}`);
            } else if (auto io = cast(IntegerObject)obj) {
                entry = parseJSON(`{"key": "` ~ key ~ `", "type": "integer", "value": ` ~ to!string(io.value) ~ `}`);
            } else if (auto dbl = cast(DoubleObject)obj) {
                entry = parseJSON(`{"key": "` ~ key ~ `", "type": "double", "value": ` ~ to!string(dbl.value) ~ `}`);
            } else if (auto str = cast(StringObject)obj) {
                entry = parseJSON(`{"key": "` ~ key ~ `", "type": "string", "value": "` ~ str.value ~ `"}`);
            } else {
                continue; // Skip unknown types
            }

            entries ~= entry;
        }

        auto json = JSONValue(entries);
        static import std.file;
        std.file.write(filename, json.toPrettyString());
    }
    void loadAttachments(string filename) {
        static import std.file;
        string data = std.file.readText(filename);
        JSONValue json = parseJSON(data);

        foreach (entry; json.array()) {
            string key = entry["key"].get!string;
            string type = entry["type"].get!string;
            JSONValue value = entry["value"];

            Object* obj;

            switch (type) {
                case "boolean":
                    obj = cast(Object*)new BooleanObject(value.get!bool);
                    break;
                case "integer":
                    obj = cast(Object*)new IntegerObject(value.get!int);
                    break;
                case "double":
                    obj = cast(Object*)new DoubleObject(value.get!double());
                    break;
                case "string":
                    obj = cast(Object*)new StringObject(value.str());
                    break;
                default:
                    continue; // Skip unknown types
            }

            attachments[key] = obj;
        }
    }

    void bankPacksInit(){
        bankPacks["items0"] = BankPack("bank", 0L, 0);
        bankPacks["items1"] = BankPack("bank", 0L, 0);
        bankPacks["items2"] = BankPack("bank", 75000000L, 600);
        bankPacks["items3"] = BankPack("bank", 75000000L, 600);
        bankPacks["items4"] = BankPack("bank", 100000000L, 800);
        bankPacks["items5"] = BankPack("bank", 100000000L, 800);
        bankPacks["items6"] = BankPack("bank", 112500000L, 900);
        bankPacks["items7"] = BankPack("bank", 112500000L, 900);
        bankPacks["items8"] = BankPack("bank_b", 0L, 0);
        bankPacks["items9"] = BankPack("bank_b", 475000000L, 1000);
        bankPacks["items10"] = BankPack("bank_b", 675000000L, 1150);
        bankPacks["items11"] = BankPack("bank_b", 825000000L, 1150);
        bankPacks["items12"] = BankPack("bank_b", 975000000L, 1200);
        bankPacks["items13"] = BankPack("bank_b", 975000000L, 1200);
        bankPacks["items14"] = BankPack("bank_b", 975000000L, 1200);
        bankPacks["items15"] = BankPack("bank_b", 975000000L, 1200);
        bankPacks["items16"] = BankPack("bank_b", 975000000L, 1200);
        bankPacks["items17"] = BankPack("bank_b", 1075000000L, 1200);
        bankPacks["items18"] = BankPack("bank_b", 1175000000L, 1200);
        bankPacks["items19"] = BankPack("bank_b", 1275000000L, 1200);
        bankPacks["items20"] = BankPack("bank_b", 1375000000L, 1200);
        bankPacks["items21"] = BankPack("bank_b", 1475000000L, 1200);
        bankPacks["items22"] = BankPack("bank_b", 1575000000L, 1200);
        bankPacks["items23"] = BankPack("bank_b", 1675000000L, 1200);
        bankPacks["items24"] = BankPack("bank_u", 0L, 0);
        bankPacks["items25"] = BankPack("bank_u", 2075000000L, 1350);
        bankPacks["items26"] = BankPack("bank_u", 2075000000L, 1350);
        bankPacks["items27"] = BankPack("bank_u", 2075000000L, 1350);
        bankPacks["items28"] = BankPack("bank_u", 2075000000L, 1350);
        bankPacks["items29"] = BankPack("bank_u", 3075000000L, 1350);
        bankPacks["items30"] = BankPack("bank_u", 3075000000L, 1350);
        bankPacks["items31"] = BankPack("bank_u", 3075000000L, 1350);
        bankPacks["items32"] = BankPack("bank_u", 3075000000L, 1350);
        bankPacks["items33"] = BankPack("bank_u", 3075000000L, 1350);
        bankPacks["items34"] = BankPack("bank_u", 3075000000L, 1350);
        bankPacks["items35"] = BankPack("bank_u", 4075000000L, 1450);
        bankPacks["items36"] = BankPack("bank_u", 5075000000L, 1450);
        bankPacks["items37"] = BankPack("bank_u", 6075000000L, 1450);
        bankPacks["items38"] = BankPack("bank_u", 7075000000L, 1450);
        bankPacks["items39"] = BankPack("bank_u", 8075000000L, 1450);
        bankPacks["items40"] = BankPack("bank_u", 9075000000L, 1650);
        bankPacks["items41"] = BankPack("bank_u", 9075000000L, 1650);
        bankPacks["items42"] = BankPack("bank_u", 9975000000L, 1650);
        bankPacks["items43"] = BankPack("bank_u", 9975000000L, 1650);
        bankPacks["items44"] = BankPack("bank_u", 9975000000L, 1650);
        bankPacks["items45"] = BankPack("bank_u", 9975000000L, 1850);
        bankPacks["items46"] = BankPack("bank_u", 9975000000L, 1850);
        bankPacks["items47"] = BankPack("bank_u", 9995000000L, 1850);
    }
}

double distance(double x1, double y1, double x2, double y2)
{
    return sqrt(pow(x1 - x2, 2) + pow(y1 - y2, 2));
}

double distance(Entity a, Entity b)
{
    return distance(a.x, a.y, b.x, b.y);
}

double distance(ALClient a1, ALClient b1)
{
    auto a = a1.player;
    auto b = b1.player;
    return distance(a.x, a.y, b.x, b.y);
}
JSONValue json(JSONValue[string] map) {
    JSONValue obj = JSONValue.init;
    obj.object = map;
    return obj;
}
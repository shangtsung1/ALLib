module allib.monitor;

import vibe.vibe;
import std.conv : to;
import std.json : JSONValue, JSONType;
import std.algorithm : sort, uniq;
import std.array : array;
import allib.allib;

class MonitorService {
    ALClient[] clients;

    this(ALClient[] clients) {
        this.clients = clients;
    }

@path("/")
void index(HTTPServerResponse res) {
    res.contentType = "text/html; charset=utf-8";
    res.writeBody(
         "<!DOCTYPE html>\n" ~
               "<html>\n" ~
               "<head>\n" ~
               "  <meta charset=\"utf-8\">\n" ~
               "  <title>Bot Monitor</title>\n" ~
               "  <style>canvas { border:1px solid #000; }</style>\n" ~
               "</head>\n" ~
               "<body>\n" ~
               "  <h1>Bot Monitor</h1>\n" ~
               "  <select id=\"mapSel\"></select>\n" ~
               "  <canvas id=\"mapCanvas\" width=\"800\" height=\"800\"></canvas>\n" ~
               "  <script>\n" ~
               "    let geo = {};\n" ~
               "    let bots = [];\n" ~
               "    let currentMap = '';\n" ~
               "    const sel = document.getElementById('mapSel');\n" ~
               "    const canvas = document.getElementById('mapCanvas');\n" ~
               "    const ctx = canvas.getContext('2d');\n" ~
               "    sel.addEventListener('change', draw);\n" ~
               "    function fetchData(){\n" ~
               "      fetch('data').then(r=>r.json()).then(d=>{\n" ~
               "        bots = d.bots;\n" ~
               "        geo = d.geometry;\n" ~
               "        updateSelect();\n" ~
               "        draw();\n" ~
               "      });\n" ~
               "    }\n" ~
               "    function updateSelect(){\n" ~
               "      const maps = Object.keys(geo);\n" ~
               "      sel.innerHTML = maps.map(m=>`<option value=\"${m}\">${m}</option>`).join('');\n" ~
               "      if(!currentMap || !geo[currentMap]) currentMap = maps[0] || '';\n" ~
               "      sel.value = currentMap;\n" ~
               "    }\n" ~
               "    function draw(){\n" ~
               "      currentMap = sel.value;\n" ~
               "      ctx.clearRect(0,0,canvas.width,canvas.height);\n" ~
               "      const g = geo[currentMap];\n" ~
               "      if(!g) return;\n" ~
               "      const sx = canvas.width/(g.max_x - g.min_x);\n" ~
               "      const sy = canvas.height/(g.max_y - g.min_y);\n" ~
               "      ctx.strokeStyle = '#888';\n" ~
               "      ctx.beginPath();\n" ~
               "      if(g.x_lines) g.x_lines.forEach(l=>{ ctx.moveTo((l[0]-g.min_x)*sx,(l[1]-g.min_y)*sy); ctx.lineTo((l[0]-g.min_x)*sx,(l[2]-g.min_y)*sy); });\n" ~
               "      if(g.y_lines) g.y_lines.forEach(l=>{ ctx.moveTo((l[1]-g.min_x)*sx,(l[0]-g.min_y)*sy); ctx.lineTo((l[2]-g.min_x)*sx,(l[0]-g.min_y)*sy); });\n" ~
               "      ctx.stroke();\n" ~
               "      bots.forEach(b=>{\n" ~
               "        if(b.map!==currentMap) return;\n" ~
               "        const x=(b.x-g.min_x)*sx;\n" ~
               "        const y=(b.y-g.min_y)*sy;\n" ~
               "        ctx.fillStyle='red';\n" ~
               "        ctx.beginPath();\n" ~
               "        ctx.arc(x,y,5,0,2*Math.PI); ctx.fill();\n" ~
               "        ctx.fillStyle='black';\n" ~
               "        ctx.fillText(b.id,x+6,y);\n" ~
               "      });\n" ~
               "    }\n" ~
               "    setInterval(fetchData, 1000);\n" ~
               "    fetchData();\n" ~
               "  </script>\n" ~
               "</body>\n" ~
               "</html>\n");
    }

    @path("/data")
    @contentType("application/json")
    string data() {
        JSONValue[] botsJson;
        string[] maps;
        foreach (client; clients) {
            if (client.player.id is null)
                continue;
            botsJson ~= JSONValue([
                "id": JSONValue(client.player.id),
                "x": JSONValue(client.player.x),
                "y": JSONValue(client.player.y),
                "map": JSONValue(client.player.mapName),
                "hp": JSONValue(client.player.hp),
                "max_hp": JSONValue(client.player.max_hp)
            ]);
            maps ~= client.player.mapName;
        }

        auto uniqueMaps = maps.sort.uniq.array;
        JSONValue[string] geom;
        auto G = ALSession.INSTANCE().G;
        foreach (m; uniqueMaps) {
            if (G["geometry"].type == JSONType.object && m in G["geometry"].object)
                geom[m] = G["geometry"][m];
        }

        JSONValue res = JSONValue([
            "bots": JSONValue(botsJson),
            "geometry": JSONValue(geom)
        ]);
        return res.toString();
    }
}

void startMonitor(ALClient[] clients) {
    runTask( () nothrow {
        try {
            auto settings = new HTTPServerSettings;
            settings.port = 9001;
            settings.bindAddresses = ["0.0.0.0"];
            auto router = new URLRouter;
            router.registerWebInterface(new MonitorService(clients));
            listenHTTP(settings, router);
        } catch (Throwable) {
        }
    });
}

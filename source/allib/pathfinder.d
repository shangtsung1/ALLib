module allib.pathfinder;


import allib.allib;
import allib.logger;

import std.math;
import std.stdio;
import std.json;
import std.container.array;
import std.array;
import std.algorithm;
import std.datetime;
import std.math : abs, sqrt, pow, PI, cos, sin, atan2, floor, ceil;
import std.conv : to;
import std.typecons : Tuple, tuple, Flag, Yes, No;


struct PathSegment {
    string map;
    double startX, startY;
    double endX, endY;
    bool isDoor;
    JSONValue door;
}

struct GeometryLine {
    double position;
    double start;
    double end;
    bool isXLine;
}

struct MapBounds {
    double minX, minY, maxX, maxY;
}

public Tuple!(GeometryLine[], MapBounds) getMapGeometry(JSONValue G,string mapName) {
    GeometryLine[] lines;
    MapBounds bounds;

    if (G["geometry"].type == JSONType.object &&
        G["geometry"][mapName].type == JSONType.object) {
        auto geo = G["geometry"][mapName];

        bounds.minX = geo["min_x"].get!double;
        bounds.minY = geo["min_y"].get!double;
        bounds.maxX = geo["max_x"].get!double;
        bounds.maxY = geo["max_y"].get!double;

        if (geo["x_lines"].type == JSONType.array) {
            foreach (line; geo["x_lines"].array) {
                if (line.type == JSONType.array && line.array.length >= 3) {
                    lines ~= GeometryLine(
                        line[0].get!double,
                        line[1].get!double,
                        line[2].get!double,
                        true
                    );
                }
            }
        }

        if (geo["y_lines"].type == JSONType.array) {
            foreach (line; geo["y_lines"].array) {
                if (line.type == JSONType.array && line.array.length >= 3) {
                    lines ~= GeometryLine(
                        line[0].get!double,
                        line[1].get!double,
                        line[2].get!double,
                        false
                    );
                }
            }
        }
    }

    return tuple(lines, bounds);
}

class Pathfinder {
    ALClient client;
    string fromMap;
    string toMap;
    double x, y, tx, ty;
    JSONValue G;
    double characterWidth = 26;
    double characterHeight = 35;
    double stepSize = 10.0;
    double gridResolution = 10.0;

    this(ALClient client, string fromMap, double x, double y, string toMap, double tx, double ty) {
        this.client = client;
        this.fromMap = fromMap;
        this.x = x;
        this.y = y;
        this.toMap = toMap;
        this.tx = tx;
        this.ty = ty;
        this.G = ALSession.INSTANCE().G;
        if(fromMap == "jail"){
            client.leaveJail();
            fromMap = "main";
            x = 2;
            y = 45;
        }
    }

    PathSegment[] findPath() {
        if (fromMap == toMap) {
            return gridBasedPath(fromMap, x, y, tx, ty);
        }
        return findCrossMapPath();
    }

    private Tuple!(GeometryLine[], MapBounds) _getMapGeometry(string map){
        return getMapGeometry(G,map);
    }

    private PathSegment[] gridBasedPath(string map, double startX, double startY, double endX, double endY) {
        auto geoData = _getMapGeometry(map);
        auto geometry = geoData[0];
        auto bounds = geoData[1];

        // Create grid
        double minX = bounds.minX;
        double minY = bounds.minY;
        double maxX = bounds.maxX;
        double maxY = bounds.maxY;

        int cols = cast(int)((maxX - minX) / gridResolution) + 1;
        int rows = cast(int)((maxY - minY) / gridResolution) + 1;

        bool[][] grid = new bool[][](rows, cols);
        for (int r = 0; r < rows; r++) {
            for (int c = 0; c < cols; c++) {
                double wx = minX + c * gridResolution;
                double wy = minY + r * gridResolution;
                grid[r][c] = isPointNearObstacle(geometry, wx, wy);
            }
        }

        // Convert world coordinates to grid indices
        int startCol = cast(int)((startX - minX) / gridResolution);
        int startRow = cast(int)((startY - minY) / gridResolution);
        int endCol = cast(int)((endX - minX) / gridResolution);
        int endRow = cast(int)((endY - minY) / gridResolution);

        // A* pathfinding on grid
        auto gridPath = aStarOnGrid(grid, startRow, startCol, endRow, endCol);
        if (gridPath.length == 0) {
            logError("No path found in " ~ map);
            return [PathSegment(map, startX, startY, endX, endY, false, JSONValue(null))];
        }

        // Convert grid path to world coordinates and create segments
        double[][] pathPoints;
        foreach (point; gridPath) {
            double wx = minX + point[1] * gridResolution;
            double wy = minY + point[0] * gridResolution;
            pathPoints ~= [wx, wy];
        }

        // Simplify path
        double[][] simplified;
        simplified ~= pathPoints[0];
        for (size_t i = 1; i < pathPoints.length - 1; i++) {
            if (!isLineOfSight(geometry, simplified[$-1], pathPoints[i+1])) {
                simplified ~= pathPoints[i];
            }
        }
        simplified ~= pathPoints[$-1];

        PathSegment[] segments;
        foreach (i; 0 .. simplified.length - 1) {
            segments ~= PathSegment(
                map,
                simplified[i][0], simplified[i][1],
                simplified[i+1][0], simplified[i+1][1],
                false,
                JSONValue(null)
            );
        }

        return segments;
    }

    private bool isPointNearObstacle(GeometryLine[] geometry, double x, double y) {
        double clearance = max(characterWidth, characterHeight) / 2;
        foreach (line; geometry) {
            if (line.isXLine) { // Vertical line
                if (abs(x - line.position) < clearance) {
                    if (y >= line.start && y <= line.end) return true;
                }
            } else { // Horizontal line
                if (abs(y - line.position) < clearance) {
                    if (x >= line.start && x <= line.end) return true;
                }
            }
        }
        return false;
    }

    private bool isLineOfSight(GeometryLine[] geometry, double[] p1, double[] p2) {
        double clearance = max(characterWidth, characterHeight) / 2;
        foreach (line; geometry) {
            if (line.isXLine) { // Vertical line
                double t = (line.position - p1[0]) / (p2[0] - p1[0]);
                if (t >= 0 && t <= 1) {
                    double yIntersect = p1[1] + t * (p2[1] - p1[1]);
                    if (yIntersect >= line.start - clearance && 
                        yIntersect <= line.end + clearance) {
                        return false;
                    }
                }
            } else { // Horizontal line
                double t = (line.position - p1[1]) / (p2[1] - p1[1]);
                if (t >= 0 && t <= 1) {
                    double xIntersect = p1[0] + t * (p2[0] - p1[0]);
                    if (xIntersect >= line.start - clearance && 
                        xIntersect <= line.end + clearance) {
                        return false;
                    }
                }
            }
        }
        return true;
    }

    private int[][] aStarOnGrid(bool[][] grid, int startRow, int startCol, int endRow, int endCol) {
        import std.container : BinaryHeap, Array;
        import std.algorithm : reverse;

        if (startRow < 0 || startRow >= grid.length || 
            startCol < 0 || startCol >= grid[0].length) {
            return [];
        }
        
        if (grid[startRow][startCol] || grid[endRow][endCol]) {
            return [];
        }

        int[2][] directions = [
            [-1,0], [1,0], [0,-1], [0,1],
            [-1,-1], [-1,1], [1,-1], [1,1]
        ];

        static struct Node {
            int row, col;
            double g, h;
            int[] parent;
            
            double f() const { return g + h; }
            
            int opCmp(ref const Node other) const {
                if (f() < other.f()) return -1;
                if (f() > other.f()) return 1;
                return 0;
            }
        }

        auto openSet = BinaryHeap!(Array!Node, "a.f() > b.f()")();
        double[][] gScore = new double[][](grid.length, grid[0].length);
        int[][][] cameFrom = new int[][][](grid.length, grid[0].length);
        
        foreach (i; 0..grid.length) {
            foreach (j; 0..grid[0].length) {
                gScore[i][j] = double.max;
                cameFrom[i][j] = null;
            }
        }

        gScore[startRow][startCol] = 0;
        openSet.insert(Node(startRow, startCol, 0, 
                           heuristic(startRow, startCol, endRow, endCol), 
                           null));

        while (!openSet.empty()) {
            Node current = openSet.front();
            openSet.removeFront();
            
            if (current.row == endRow && current.col == endCol) {
                // Reconstruct path
                int[][] path;
                int[] currentPos = [current.row, current.col];
                while (currentPos !is null) {
                    path ~= currentPos;
                    currentPos = cameFrom[currentPos[0]][currentPos[1]];
                }
                path.reverse();
                return path;
            }
            
            foreach (dir; directions) {
                int newRow = current.row + dir[0];
                int newCol = current.col + dir[1];
                
                // Check bounds and obstacles
                if (newRow < 0 || newRow >= grid.length || 
                    newCol < 0 || newCol >= grid[0].length) {
                    continue;
                }
                if (grid[newRow][newCol]) continue;
                
                // Diagonal cost is sqrt(2), others are 1
                double moveCost = (abs(dir[0]) == 1 && abs(dir[1]) == 1) ? 
                                 sqrt(2.0) : 1.0;
                double tentativeG = current.g + moveCost;
                
                if (tentativeG < gScore[newRow][newCol]) {
                    cameFrom[newRow][newCol] = [current.row, current.col];
                    gScore[newRow][newCol] = tentativeG;
                    double h = heuristic(newRow, newCol, endRow, endCol);
                    openSet.insert(Node(newRow, newCol, tentativeG, h, 
                                      [current.row, current.col]));
                }
            }
        }
        
        return [];
    }

    private double heuristic(int r1, int c1, int r2, int c2) {
        return sqrt(cast(float)(pow(r1 - r2, 2) + pow(c1 - c2, 2)));
    }

    private PathSegment[] findCrossMapPath() {
        // Build map connection graph
        JSONValue[][string] graph;
        foreach (mapName, mapDef; G["maps"].object) {
            if ("doors" in mapDef && mapDef["doors"].type == JSONType.array) {
                JSONValue[] doors;
                foreach (door; mapDef["doors"].array) {
                    doors ~= door;
                }
                graph[mapName] = doors;
            }
        }

        // BFS to find map path
        string[string] parentMap;
        JSONValue[string] parentDoor;
        string[] queue = [fromMap];
        parentMap[fromMap] = "";
        parentDoor[fromMap] = JSONValue(null);

        while (!queue.empty) {
            string current = queue.front;
            queue = queue[1..$];
            if (current == toMap) break;

            if (current in graph) {
                foreach (door; graph[current]) {
                    if (door.type != JSONType.array || door.array.length < 7) continue;
                    string nextMap = door[4].str;
                    if (nextMap !in parentMap) {
                        parentMap[nextMap] = current;
                        parentDoor[nextMap] = door;
                        queue ~= nextMap;
                    }
                }
            }
        }

        // Backtrack to get door path
        if (toMap !in parentMap) {
            logError("No path found from " ~ fromMap ~ " to " ~ toMap);
            return [];
        }
        string[] mapPath;
        JSONValue[] doorPath;
        string current = toMap;
        while (current != fromMap) {
            mapPath ~= current;
            doorPath ~= parentDoor[current];
            current = parentMap[current];
        }
        mapPath ~= fromMap;
        mapPath.reverse();
        doorPath.reverse();

        // Build path segments
        PathSegment[] segments;

        // First segment
        JSONValue firstDoor = doorPath[0];
        double doorX = firstDoor[0].get!double + firstDoor[2].get!double/2;
        double doorY = firstDoor[1].get!double + firstDoor[3].get!double/2;
        segments ~= gridBasedPath(fromMap, x, y, doorX, doorY);
        segments ~= PathSegment(
            fromMap,
            doorX, doorY,
            doorX, doorY,
            true,
            firstDoor
        );
        // Intermediate segments
        foreach (i; 0..doorPath.length-1) {
            JSONValue doorIn = doorPath[i];
            string currentMap = doorIn[4].str;
            
            // Get spawn position for this door
            JSONValue spawn = JSONValue.emptyArray;
            if (G["maps"][currentMap].type == JSONType.object &&
                G["maps"][currentMap]["spawns"].type == JSONType.array) {
                int spawnIndex = doorIn[6].get!int;
                JSONValue spawns = G["maps"][currentMap]["spawns"];
                if (spawnIndex >= 0 && spawnIndex < spawns.array.length) {
                    spawn = spawns[spawnIndex];
                }
            }
            
            double spawnX = spawn.array.length >= 2 ? spawn[0].get!double : 0;
            double spawnY = spawn.array.length >= 2 ? spawn[1].get!double : 0;
            
            // Next door position
            JSONValue nextDoor = doorPath[i+1];
            double nextDoorX = nextDoor[0].get!double + nextDoor[2].get!double/2;
            double nextDoorY = nextDoor[1].get!double + nextDoor[3].get!double/2;
            
            segments ~= gridBasedPath(
                currentMap,
                spawnX, spawnY,
                nextDoorX, nextDoorY
            );
            segments ~= PathSegment(
                currentMap,
                nextDoorX, nextDoorY,
                nextDoorX, nextDoorY,
                true,
                nextDoor
            );
        }

        // Final segment
        JSONValue lastDoor = doorPath[$-1];
        JSONValue lastSpawn = JSONValue.emptyArray;
        if (G["maps"][toMap].type == JSONType.object &&
            G["maps"][toMap]["spawns"].type == JSONType.array) {
            int spawnIndex = lastDoor[6].get!int;
            JSONValue spawns = G["maps"][toMap]["spawns"];
            if (spawnIndex >= 0 && spawnIndex < spawns.array.length) {
                lastSpawn = spawns[spawnIndex];
            }
        }
        
        double lastSpawnX = lastSpawn.array.length >= 2 ? lastSpawn[0].get!double : 0;
        double lastSpawnY = lastSpawn.array.length >= 2 ? lastSpawn[1].get!double : 0;
        
        segments ~= gridBasedPath(
            toMap,
            lastSpawnX, lastSpawnY,
            tx, ty
        );

        return segments;
    }
}

class PathWalker {
    private ALClient client;
    private PathSegment[] path;
    private size_t currentSegment = 0;
    private bool awaitingMapChange = false;

    this(ALClient client) {
        this.client = client;
    }

    void setPath(PathSegment[] newPath) {
        path = newPath.dup;
        currentSegment = 0;
        awaitingMapChange = false;
    }

    bool hasPath() {
        return currentSegment < path.length;
    }

    void reset() {
        path = [];
        currentSegment = 0;
        awaitingMapChange = false;
    }

    PathSegment[] getPath(){
        return path;
    }

    size_t getCurrentSegment(){
        return currentSegment;
    }

    void update() {
        if(client.player.rip){return;}
        if (!hasPath()) return;
        if(client.player.mapName == "jail"){
            client.leaveJail();
        }
        if (awaitingMapChange) return;
        if(client.player.moving)return;
        

        auto seg = path[currentSegment];
        auto map = client.player.mapName;
        auto cx = client.player.x;
        auto cy = client.player.y;

        if (map != seg.map) {
            reset();
            return;
        }

        double dx = seg.endX - cx;
        double dy = seg.endY - cy;
        double dist = sqrt(dx * dx + dy * dy);

        if (dist > 5.0) {
            // Move towards segment end
            client.move(seg.endX, seg.endY);
        } else {
            if (seg.isDoor) {
                logDebug("Door ",seg.door[4].str," ", seg.door[5].get!int);
                client.transport(seg.door[4].str, seg.door[5].get!int);
                awaitingMapChange = true;
            } else {
                currentSegment++;
            }
        }
    }

    void onMapChanged(string map, double x, double y) {
        if (!hasPath()) return;
        auto seg = path[currentSegment];
        if (seg.isDoor && map == seg.door[4].str) {
            awaitingMapChange = false;
            currentSegment++;
        }
    }
}
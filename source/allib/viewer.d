module allib.viewer;

import allib.schema;
import allib.allib;
import allib.pathfinder;
import std.stdio;
import std.string;
import core.atomic;
import std.conv;
import core.thread;
import core.sync.mutex;

import derelict.sdl2.sdl;

__gshared bool sdl2Loaded = false;

class ALViewer {
    ALClient client;
    int WIDTH;
    int HEIGHT;
    bool inited = false;

    SDL_Window* window = null;
    SDL_Renderer* renderer = null;
    static shared Mutex renderMutex;
    shared static this() {
        renderMutex = new shared Mutex();
    }

    this(ALClient client, int width, int height) {
        this.client = client;
        this.WIDTH = width;
        this.HEIGHT = height;

        if (!atomicLoad(sdl2Loaded)) {
            atomicStore(sdl2Loaded, true);
            DerelictSDL2.load();
            if (SDL_Init(SDL_INIT_VIDEO) != 0) {
                writeln("SDL_Init failed: ", to!string(SDL_GetError()));
                import core.stdc.stdlib : exit;
                exit(2);
            }
        }
        client.onUpdateLoop(&this.update);
    }

    void start() {
        if (!inited) {
            string title = "AdventurelanD";
            window = SDL_CreateWindow(title.toStringz,
                SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                WIDTH, HEIGHT, SDL_WINDOW_SHOWN);
            if (window is null) {
                writeln("SDL_CreateWindow failed: ", to!string(SDL_GetError()));
                import core.stdc.stdlib : exit;
                exit(2);
            }

            renderer = SDL_CreateRenderer(window, -1,
                SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
            if (renderer is null) {
                writeln("SDL_CreateRenderer failed: ", to!string(SDL_GetError()));
                SDL_DestroyWindow(window);
                import core.stdc.stdlib : exit;
                exit(2);
            }

            inited = true;
        }
    }

    void update() {
        if (!inited) return;

        SDL_Event e;
        while (SDL_PollEvent(&e) != 0) {
            if (e.type == SDL_QUIT) {
                stop();
                return;
            }
        }

        renderMutex.lock();
        scope(exit) { renderMutex.unlock(); }

        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        SDL_RenderClear(renderer);

        auto p = client.player;
        if (p.id !is null) {
            string title = "AdventurelanD - " ~ client.player.id;
            SDL_SetWindowTitle(window, title.toStringz);

            string mapName = p.mapName;
            float posX = p.x;
            float posY = p.y;

            auto geoTuple = getMapGeometry(ALSession.INSTANCE().G, mapName);
            auto lines = geoTuple[0];
            // auto bounds = geoTuple[1]; // unused here

            float screenWidth = cast(float)WIDTH;
            float screenHeight = cast(float)HEIGHT;
            float zoom = 1.0f; // tweak zoom here
            float centerX = screenWidth / 2.0f;
            float centerY = screenHeight / 2.0f;

            void drawLine(float sx, float sy, float ex, float ey, SDL_Color color) {
                SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
                SDL_RenderDrawLine(renderer, cast(int)sx, cast(int)sy, cast(int)ex, cast(int)ey);
            }

            // Colors
            enum SDL_Color BLACK = SDL_Color(0, 0, 0, 255);
            enum SDL_Color WHITE = SDL_Color(255, 255, 255, 255);
            enum SDL_Color RED = SDL_Color(255, 0, 0, 255);
            enum SDL_Color GREEN = SDL_Color(0, 255, 0, 255);
            enum SDL_Color BLUE = SDL_Color(0, 0, 255, 255);
            enum SDL_Color ORANGE = SDL_Color(255, 165, 0, 255);
            enum SDL_Color YELLOW = SDL_Color(255, 255, 0, 255);

            // Draw geometry lines
            foreach (line; lines) {
                float startX, startY, endX, endY;

                if (line.isXLine) {
                    startX = (line.position - posX) * zoom + centerX;
                    endX   = (line.position - posX) * zoom + centerX;
                    startY = (line.start - posY) * zoom + centerY;
                    endY   = (line.end - posY) * zoom + centerY;
                } else {
                    startX = (line.start - posX) * zoom + centerX;
                    endX   = (line.end - posX) * zoom + centerX;
                    startY = (line.position - posY) * zoom + centerY;
                    endY   = (line.position - posY) * zoom + centerY;
                }

                drawLine(startX, startY, endX, endY, WHITE);
            }

            // Draw pathwalker paths
            if (client.pathwalker.hasPath()) {
                auto path = client.pathwalker.getPath();
                size_t currentSegment = client.pathwalker.getCurrentSegment();

                foreach (i; currentSegment .. path.length) {
                    auto seg = path[i];
                    if (seg.map != mapName) continue;

                    float sx = (seg.startX - posX) * zoom + centerX;
                    float sy = (seg.startY - posY) * zoom + centerY;
                    float ex = (seg.endX - posX) * zoom + centerX;
                    float ey = (seg.endY - posY) * zoom + centerY;

                    auto color = seg.isDoor ? YELLOW : ORANGE;
                    drawLine(sx, sy, ex, ey, color);

                    drawCircle(renderer, cast(int)ex, cast(int)ey, 3, color);
                }
            }

            // Draw monsters
            foreach (ea; client.monsters) {
                if (ea.rip) continue;
                float ex = (ea.x - posX) * zoom + centerX;
                float ey = (ea.y - posY) * zoom + centerY;
                drawCircle(renderer, cast(int)ex, cast(int)ey, 3, RED);
            }

            // Draw players
            foreach (ea; client.players) {
                if (ea.rip) continue;
                float ex = (ea.x - posX) * zoom + centerX;
                float ey = (ea.y - posY) * zoom + centerY;
                drawCircle(renderer, cast(int)ex, cast(int)ey, 3, BLUE);
            }

            // Draw player center point
            drawCircle(renderer, cast(int)centerX, cast(int)centerY, 5, GREEN);
        }

        SDL_RenderPresent(renderer);
    }

    void stop() {
        if (renderer !is null) {
            SDL_DestroyRenderer(renderer);
            renderer = null;
        }
        if (window !is null) {
            SDL_DestroyWindow(window);
            window = null;
        }
        SDL_Quit();
        inited = false;
    }

    //(midpoint circle algorithm)
    void drawCircle(SDL_Renderer* rend, int x0, int y0, int radius, SDL_Color color) {
        SDL_SetRenderDrawColor(rend, color.r, color.g, color.b, color.a);

        int x = radius;
        int y = 0;
        int err = 0;

        while (x >= y) {
            drawCirclePoints(rend, x0, y0, x, y);
            y++;
            if (err <= 0) {
                err += 2 * y + 1;
            } 
            if (err > 0) {
                x--;
                err -= 2 * x + 1;
            }
        }
    }

    void drawCirclePoints(SDL_Renderer* rend, int cx, int cy, int x, int y) {
        SDL_RenderDrawPoint(rend, cx + x, cy + y);
        SDL_RenderDrawPoint(rend, cx + y, cy + x);
        SDL_RenderDrawPoint(rend, cx - y, cy + x);
        SDL_RenderDrawPoint(rend, cx - x, cy + y);
        SDL_RenderDrawPoint(rend, cx - x, cy - y);
        SDL_RenderDrawPoint(rend, cx - y, cy - x);
        SDL_RenderDrawPoint(rend, cx + y, cy - x);
        SDL_RenderDrawPoint(rend, cx + x, cy - y);
    }
}

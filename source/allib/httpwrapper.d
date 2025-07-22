module allib.httpwrapper;

import std.net.curl;
import std.json;
import std.file;
import std.regex;
import std.conv;
import std.string;
import std.algorithm;
import std.exception;
import std.typecons;
import std.range;
import std.stdio;
import std.array;
import std.format;

import allib.logger;

// Helper for URL encoding
string urlEncode(string s) {
    auto app = appender!string();
    foreach (c; s) {
        if ((c >= '0' && c <= '9') ||
            (c >= 'a' && c <= 'z') ||
            (c >= 'A' && c <= 'Z') ||
            (c == '-' || c == '_' || c == '.' || c == '~')) {
            app.put(c);
        } else {
            formattedWrite(app, "%%%02X", cast(ubyte)c);
        }
    }
    return app.data;
}

struct HTTPCookie {
    string name;
    string value;
}
__gshared string ADDR = "https://adventure.land";

// Global state
__gshared int online_version;
__gshared string password;
__gshared string email;
__gshared string session_cookie;
__gshared string auth;
__gshared string cookie;
__gshared string userID;
__gshared JSONValue[string] servers;
__gshared JSONValue[string] characters;
__gshared JSONValue G;

void grabG() {
    string url = ADDR~"/data.js";
    string data;

    // Download the file
    try {
        data = cast(string)get(url);
    } catch (Exception e) {
        logError("Failed to download: ", e.msg);
        return;
    }

    // Remove leading "var G="
    immutable prefix = "var G=";
    if (data.startsWith(prefix))
        data = data[prefix.length .. $];

    // Remove trailing ';'
    data = data[0 .. $ - 2];
    std.file.write("data.json", data);
    G=parseJSON(data);
}

bool do_request(string url, ref string output) {
    auto http = HTTP();
    string response;

    http.url = url;
    http.method = HTTP.Method.get;

    if (!cookie.empty) {
        http.addRequestHeader("Cookie", cookie);
    }

    http.onReceive = (ubyte[] data) {
        response ~= cast(string) data;
        return data.length;
    };

    try {
        http.perform();

        if (http.statusLine.code == 200) {
            output = response;
            logInfo("GET ", url, " [200 OK]");
            return true;
        } else {
            logError("GET failed: ", http.statusLine.code);
        }
    } catch (CurlException e) {
        logError("CURL error: ", e.msg);
    }

    return false;
}

bool do_post(string url, string args, string method, ref string output, ref HTTPCookie[] cookies) {
    auto http = HTTP();
    string response;

    http.url = url;
    http.method = HTTP.Method.post;

    string postData = "method=" ~ method ~ "&arguments=" ~ urlEncode(args);
    http.setPostData(cast(void[]) postData, "application/x-www-form-urlencoded");

    if (!cookie.empty) {
        http.addRequestHeader("Cookie", cookie);
    }

    http.onReceive = (ubyte[] data) {
        response ~= cast(string) data;
        return data.length;
    };

    http.onReceiveHeader = (in char[] key, in char[] value) {
        if (key == "set-cookie") {
            auto c = value.split(";")[0];
            auto parts = c.split("=");
            if (parts.length == 2) {
                cookies ~= HTTPCookie(parts[0].to!string,parts[1].to!string);
            }
        }
    };

    try {
        http.perform();

        if (http.statusLine.code == 200) {
            output = response;
            logInfo("POST ", url, " [200 OK]");
            return true;
        } else {
            logError("POST failed: ", http.statusLine.code);
        }
    } catch (CurlException e) {
        logError("CURL error: ", e.msg);
    }

    return false;
}

string login() {
    logInfo("Attempting login...");
    if (exists(".env")) {
        auto lines = readText(".env").splitLines();
        email = lines[0].split("=")[1];
        password = lines[1].split("=")[1];
        string args = `{"email":"` ~ email ~ `","password":"` ~ password ~ `","only_login":true}`;
        string outs;
        HTTPCookie[] cookies;
        
        if (do_post(ADDR~"/api/signup_or_login", args, "signup_or_login", outs, cookies)) {
            foreach (c; cookies) {
                if (c.name == "auth") {
                    session_cookie = c.value;
                    cookie = "auth=" ~ session_cookie;
                    userID = session_cookie.split("-")[0];
                    auth = session_cookie.split("-")[1];
                    logInfo("Login successful");
                    return c.value;
                }
                else{
                    logInfo(c.name);
                }
            }
            logError("Auth cookie missing");
        }
    } else {
        logError(".env file missing");
    }
    return "";
}

bool updateServersAndCharacters() {
    if (auth.empty || session_cookie.empty) {
        throw new Exception("You must login first.");
    }

    string url = ADDR~"/api/servers_and_characters";
    string postData = "method=servers_and_characters";
    string response;
    HTTPCookie[] cookies;

    if (!do_post(url, "{}", "servers_and_characters", response, cookies)) {
        logError("Failed to fetch server and character info");
        return false;
    }

    try {
        auto parsed = parseJSON(response);
        if (parsed.type != JSONType.array || parsed.array.length == 0) {
            logError("Unexpected JSON structure");
            return false;
        }

        auto result = parsed[0];

        // Populate servers
        if ("servers" in result) {
            foreach (server; result["servers"].array) {
                string region = server["region"].str;
                string name = server["name"].str;
                servers[region ~ name] = server;
            }
        }

        // Populate characters
        if ("characters" in result) {
            foreach (character; result["characters"].array) {
                string charName = character["name"].str;
                characters[charName] = character;
            }
        }

        logInfo("Servers and characters updated successfully");
        return true;

    } catch (Exception e) {
        logError("Failed to parse JSON response: " ~ e.msg);
        return false;
    }
}
module allib.logger;

import std.datetime : Clock, LocalTime;
import std.stdio : writeln;
import std.conv : text;

enum LogLevel {
    VERBOSE,
    DEBUG,
    INFO,
    WARN,
    ERROR
}

private LogLevel CURRENT_LEVEL = LogLevel.INFO;

public:
    void setLogLevel(LogLevel level) {
        CURRENT_LEVEL = level;
    }
    void log(LogLevel level, Args...)(Args args) {
        if (level < CURRENT_LEVEL) return;
        auto now = Clock.currTime().toISOExtString();
        string levelStr;
        final switch (level) {
            case LogLevel.VERBOSE: levelStr = "VERBOSE"; break;
            case LogLevel.DEBUG: levelStr = "DEBUG"; break;
            case LogLevel.INFO:  levelStr = "INFO";  break;
            case LogLevel.WARN:  levelStr = "WARN";  break;
            case LogLevel.ERROR: levelStr = "ERROR"; break;
        }
        writeln("[", now, "] [", levelStr, "] ", text(args));
    }

    void logDebug(Args...)(Args args) { log!(LogLevel.DEBUG)(args); }
    void logInfo(Args...)(Args args)  { log!(LogLevel.INFO)(args); }
    void logWarn(Args...)(Args args)  { log!(LogLevel.WARN)(args); }
    void logError(Args...)(Args args) { log!(LogLevel.ERROR)(args); }
    void logVerb(Args...)(Args args) { log!(LogLevel.VERBOSE)(args); }

#pragma semicolon 1

#include <sdkhooks>
#undef REQUIRE_PLUGIN
#include <adminmenu>

#define PLUGIN_NAME "AFKManager"
#define PLUGIN_VERSION "1.2.4"
#define DEFAFKTIME 120
#define AFKLOGFILE "logs/afklogs.txt"

#define AFK_WARN 0
#define AFK_SPEC 1
#define AFK_KICK 2

float g_fLastAction[MAXPLAYERS+1] = {0.0, ...};
bool g_bLastAction[MAXPLAYERS+1] = {false, ...}; //Used in menu sorting.

//Player options & Menu variables
int g_iSecGone[MAXPLAYERS+1] = {DEFAFKTIME, ...};
SortOrder g_SortOrder[MAXPLAYERS+1] = {Sort_Ascending, ...};
int g_targetPlayer[MAXPLAYERS+1] = {-1, ...};

// Used for the Warn System
bool g_bWarningPlayer[MAXPLAYERS+1] = {false, ...}; //Used in menu sorting.
float g_tWarningPlayer[MAXPLAYERS+1] = {0.0, ...};
int g_warnType[MAXPLAYERS+1] = {0, ...};

Handle hTopMenu = INVALID_HANDLE;
//Message Prefix
char gamePrefix[64];

ConVar cWarnTime; //Time after being warned which the player will be kicked.
ConVar cAutoCheck; //Enables the afk check automation
ConVar cAutoMethod; //0, move to spectate, 1, kick instantly
ConVar cAutoWarnTime; //Time after the user's last input to warn them about being afk.
ConVar cAutoEnactTime; //Time after the user's last input to put them in sepctate
ConVar cMaxPlayers; //Max amount of players before it starts to kick afk players from spectate
ConVar cAutoImmuneFlag; //Flag for immunity
ConVar cMaxKickAdmin;

int immunityBits;

char logFile[512];

public Plugin myinfo = {
    name = PLUGIN_NAME,
    author = "Mitch",
    description = "Don't expect anything superficial.",
    version = PLUGIN_VERSION,
    url = "https://github.com/MitchDizzle/AFKManager"
}

public void OnPluginStart() {
    CreateConVar("sm_afkmanager_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);
    
    cWarnTime = CreateConVar("sm_afkmanager_warntime", "60.0", "Time after being warned which the player will be kicked.");
    cAutoCheck = CreateConVar("sm_afkmanager_autocheck", "1", "Enables the afk check automation");
    cAutoMethod = CreateConVar("sm_afkmanager_automethod", "0", "0, move to spectate, 1, kick instantly");
    cAutoWarnTime = CreateConVar("sm_afkmanager_autowarntime", "300.0", "Time (seconds) after the user's last input to warn them about being afk.");
    cAutoEnactTime = CreateConVar("sm_afkmanager_autoenacttime", "420.0", "Time (seconds) after the user's last input to punish the player.");
    cMaxPlayers = CreateConVar("sm_afkmanager_maxplayers", "32", "After the server hits this threshold it will start kicking afk players from spectate, 0 to disable this, requires auto check to be enabled");
    cAutoImmuneFlag = CreateConVar("sm_afkmanager_autoimmuneflag", "z", "Flag for immunity from the auto moving system");
    cMaxKickAdmin = CreateConVar("sm_afkmanager_kickadmins", "0", "If maxplayers is reached it will kick players that have access to sm_afkmenu");
    AutoExecConfig();
    checkConvars();
    cAutoImmuneFlag.AddChangeHook(immunityHook);

    BuildPath(Path_SM, logFile, sizeof(logFile), AFKLOGFILE);
    
    AddCommandListener(CommandListener);
    RegAdminCmd("sm_afk", Cmd_AFKMenu, ADMFLAG_KICK);
    RegAdminCmd("sm_afkmenu", Cmd_AFKMenu, ADMFLAG_KICK);
    RegAdminCmd("sm_warntest", Cmd_WarnTest, ADMFLAG_KICK);

    float eTime = GetEngineTime();
    for(int i = 1; i <= MaxClients; i++) {
        if(IsClientInGame(i)) {
            g_fLastAction[i] = eTime;
        }
    }

    if(GetEngineVersion() == Engine_CSGO) {
        Format(gamePrefix, sizeof(gamePrefix), "'\x10[\x09AFK\x10]\x01");
    } else {
        Format(gamePrefix, sizeof(gamePrefix), "\x07d35400[\x07e67e22AFK\x07d35400]\x01");
    }

    Handle topmenu;
    if(LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE)) {
        OnAdminMenuReady(topmenu);
    }
}

public void OnLibraryRemoved(const char[] name) {
    if(strcmp(name, "adminmenu") == 0) {
        hTopMenu = null;
    }
}

public void immunityHook(ConVar convar, const char[] oldValue, const char[] newValue) {
    checkConvars();
}

public void checkConvars() {
    char convarValue[10];
    cAutoImmuneFlag.GetString(convarValue, sizeof(convarValue));
    if(StrEqual(convarValue, "", false) || StrEqual(convarValue, "-1", false)) {
        immunityBits = 0;
    } else {
        immunityBits = ReadFlagString(convarValue);
    }
}

public void OnMapStart() {
    CreateTimer(5.0, Timer_CheckAFK, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public void OnMapEnd() {
    for(int i = 1; i <= MaxClients; i++) {
        if(IsClientInGame(i)) {
            g_bWarningPlayer[i] = false;
        }
    }
}

public void OnClientDisconnect(int client) {
    DefPlayer(client);
}

public void OnClientPutInServer(int client) {
    DefPlayer(client);
}

public void DefPlayer(int client) {
    g_fLastAction[client] = GetEngineTime();
    g_iSecGone[client] = DEFAFKTIME;
    g_SortOrder[client] = Sort_Ascending;
    g_targetPlayer[client] = -1;
    g_bWarningPlayer[client] = false;
}

public Action CommandListener(int client, const char[] cmd, int args) {
    if(StrContains(cmd, "say", false) != -1
    || StrContains(cmd, "sm_", false) != -1
    || StrContains(cmd, "spec_", false) != -1) {
        PlayerActioned(client);
    }
    return Plugin_Continue;
}

public Action Timer_CheckAFK(Handle timer) {
    if(cAutoCheck.BoolValue) {
        float time = GetEngineTime();
        float warnTime = cAutoWarnTime.FloatValue;
        bool kickAFKs = (cMaxPlayers.IntValue > 0 && GetClientCount() >= cMaxPlayers.IntValue);
        bool kickAdmins = cMaxKickAdmin.BoolValue;
        int userFlagBits;
        for(int i = 1; i <= MaxClients; i++) {
            if(IsClientInGame(i) && (time-g_fLastAction[i] >= warnTime)) {
                userFlagBits = GetUserFlagBits(i);
                if(immunityBits == 0 || !(userFlagBits & immunityBits)) {
                    if(GetClientTeam(i) > 1) {
                        PunishPlayerEx(i, AFK_WARN, 0, 1);
                    } else if(kickAFKs && (kickAdmins || !CheckCommandAccess(i, "sm_afkmenu", ADMFLAG_KICK) && !(userFlagBits & ADMFLAG_ROOT))) {
                        PunishPlayerEx(i, AFK_KICK, 0, 1);
                        return Plugin_Continue;
                    }
                }
            }
        }
    }
    return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
    static oButtons[MAXPLAYERS+1];
    if(oButtons[client] != buttons) {
        oButtons[client] = buttons;
        PlayerActioned(client);
    }
}

public void PlayerActioned(int client) {
    g_fLastAction[client] = GetEngineTime();
    if(g_bWarningPlayer[client]) {
        g_bWarningPlayer[client] = false;
        PrintToChat(client, "%s You are no longer marked as afk.", gamePrefix);
    }
}

public Action Cmd_AFKMenu(int client, int args) {
    if(client && IsClientInGame(client)) {
        CreateAFKMenu(client);
    }
    return Plugin_Handled;
}

public Action Cmd_WarnTest(int client, int args) {
    PunishPlayer(client, 0, client);
    return Plugin_Handled;
}

public void OnAdminMenuReady(Handle topmenu) {
    if(topmenu == hTopMenu) {
        return;
    }
    hTopMenu = topmenu;
    TopMenuObject player_commands = FindTopMenuCategory(hTopMenu, ADMINMENU_PLAYERCOMMANDS);
    if(player_commands != INVALID_TOPMENUOBJECT) {
        AddToTopMenu(hTopMenu, "AFKMenu", TopMenuObject_Item, AdminMenu_ShowAFKMenu, player_commands, "sm_afkmenu", ADMFLAG_KICK);
    }
}

public AdminMenu_ShowAFKMenu(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int client, char[] buffer, int maxlength) {
    if(action == TopMenuAction_DisplayOption) {
        Format(buffer, maxlength, "AFK Manager");
    }
    if(action == TopMenuAction_SelectOption) {
        CreateAFKMenu(client);
    }
}

public void CreateAFKMenu(int client) {
    char tempFormat[64];
    Menu menu = CreateMenu(Menu_Main, MENU_ACTIONS_DEFAULT);
    SetMenuTitle(menu, "AFK Manager | Main Menu:");
    AddMenuItem(menu, "show", "Show AFK Players\n \nOptions:");

    GetTimeFromStamp(g_iSecGone[client], tempFormat, sizeof(tempFormat));
    Format(tempFormat, sizeof(tempFormat), "Change AFK Time %s", tempFormat);
    AddMenuItem(menu, "afktime", tempFormat);

    Format(tempFormat, sizeof(tempFormat), "Change Order: %s", (g_SortOrder[client] == Sort_Ascending) ? "Ascending" : "Descending");
    AddMenuItem(menu, "order", tempFormat);

    SetMenuPagination(menu, MENU_NO_PAGINATION);
    SetMenuExitButton(menu, true);
    DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int Menu_Main(Handle main, MenuAction action, int client, int param2) {
    switch (action) {
        case MenuAction_End:
            CloseHandle(main);
        case MenuAction_Select: {
            char info[32];
            GetMenuItem(main, param2, info, sizeof(info));
            if (StrEqual(info,"show")) {
                CreatePlayerMenu(client);
            } else if (StrEqual(info,"afktime")) {
                CreateAFKTimeMenu(client);
            } else if (StrEqual(info,"order")) {
                g_SortOrder[client] = (g_SortOrder[client] == Sort_Ascending) ? Sort_Descending : Sort_Ascending;
                CreateAFKMenu(client);
            }
        }
    }
    return;
}

public void CreateAFKTimeMenu(int client) {
    char tempFormat[64];
    GetTimeFromStamp(g_iSecGone[client], tempFormat, sizeof(tempFormat));
    Menu menu = CreateMenu(Menu_AFKTime, MENU_ACTIONS_DEFAULT);
    SetMenuTitle(menu, "AFK Manager | AFK Time: %s", tempFormat);
    AddMenuItem(menu, "+5", "+5 Seconds");
    AddMenuItem(menu, "+1", "+1 Seconds");
    Format(tempFormat, sizeof(tempFormat), "Default %i Seconds", DEFAFKTIME);
    AddMenuItem(menu, "0", tempFormat);
    AddMenuItem(menu, "-1", "-1 Seconds");
    AddMenuItem(menu, "-5", "-5 Seconds");
    AddMenuItem(menu, "-30", "-30 Seconds");

    SetMenuExitButton(menu, true);
    SetMenuExitBackButton(menu, true);
    DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int Menu_AFKTime(Handle main, MenuAction action, int client, int param2) {
    switch (action) {
        case MenuAction_End:
            CloseHandle(main);
        case MenuAction_Cancel: {
            if(param2 == MenuCancel_ExitBack) {
                CreateAFKMenu(client);
            }
        }
        case MenuAction_Select: {
            char info[32];
            GetMenuItem(main, param2, info, sizeof(info));
            if(StrEqual(info,"0")) {
                g_iSecGone[client] = DEFAFKTIME;
            } else {
                int num = StringToInt(info);
                g_iSecGone[client] += num;
                if(g_iSecGone[client] < 1) {
                    g_iSecGone[client] = 1;
                } else if(g_iSecGone[client] > 1200) {
                    g_iSecGone[client] = 1200;
                }
            }
            CreateAFKTimeMenu(client);
        }
    }
    return;
}

public void CreatePlayerMenu(int client) {
    float engineTime = GetEngineTime();
    Menu menu = CreateMenu(Menu_Players, MENU_ACTIONS_DEFAULT);
    SetMenuTitle(menu, "AFK Manager | Players:");
    
    AddMenuItem(menu, "refresh", "Refresh Menu");
    AddMenuItem(menu, "all", "All AFKers\n--Players--");
    float tempActionVar[MAXPLAYERS+1];
    int validPlayers;
    int time; 
    for(int i = 1; i <= MaxClients; i++) {
        g_bLastAction[i] = false;
        if(IsClientInGame(i)) {
            time = RoundToNearest(engineTime - g_fLastAction[i]);
            if(time >= g_iSecGone[client] && !CheckCommandAccess(i, "sm_afkmenu", ADMFLAG_KICK)) {
                tempActionVar[validPlayers] = g_fLastAction[i];
                validPlayers++;
            }
        }
    }
    SortFloats(tempActionVar, sizeof(tempActionVar), g_SortOrder[client]);
    int x;
    char sUserid[32];
    char tempFormat[128];
    for(int i = 0; i <= MAXPLAYERS; i++) {
        if(tempActionVar[i] == 0.0) {
            continue;
        }
        x = FindUser(tempActionVar[i]);
        if(x > 0) {
            GetTimeFromStamp(time, tempFormat, sizeof(tempFormat));
            Format(tempFormat, sizeof(tempFormat), "%N %s", x, tempFormat);
            IntToString(GetClientUserId(x), sUserid, sizeof(sUserid));
            AddMenuItem(menu, sUserid, tempFormat);
        }
    }
    SetMenuExitButton(menu, true);
    SetMenuExitBackButton(menu, true);
    DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int Menu_Players(Handle main, MenuAction action, int client, int param2) {
    switch (action) {
        case MenuAction_End:
            CloseHandle(main);
        case MenuAction_Cancel: {
            if(param2 == MenuCancel_ExitBack) {
                CreateAFKMenu(client);
            }
        }
        case MenuAction_Select: {
            char info[32];
            GetMenuItem(main, param2, info, sizeof(info));
            if(StrEqual(info, "refresh", false)) {
                CreatePlayerMenu(client);
            } else if(StrEqual(info, "all", false)) {
                g_targetPlayer[client] = -1337;
                CreatePunishMenu(client);
            } else {
                int target = GetClientOfUserId(StringToInt(info));
                if(target) {
                    g_targetPlayer[client] = StringToInt(info);
                    CreatePunishMenu(client);
                } else {
                    CreatePlayerMenu(client);
                }
            }
        }
    }
    return;
}

public void CreatePunishMenu(int client) {
    char tempFormat[64];
    GetTimeFromStamp(g_iSecGone[client], tempFormat, sizeof(tempFormat));
    Menu menu = CreateMenu(Menu_Punish, MENU_ACTIONS_DEFAULT);
    
    int target = 0;
    if(g_targetPlayer[client] == -1337) {
        SetMenuTitle(menu, "AFK Manager | Punish All AFKers");
    } else {
        target = GetClientOfUserId(g_targetPlayer[client]);
        SetMenuTitle(menu, "AFK Manager \nPunish: %N", target);
    }
    AddMenuItem(menu, "0", "Warn Player", (g_targetPlayer[client] != -1337 && g_bWarningPlayer[target]) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
    AddMenuItem(menu, "1", "Move To Spectator");
    AddMenuItem(menu, "2", "Kick Player");
    SetMenuExitButton(menu, true);
    SetMenuExitBackButton(menu, true);
    DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int Menu_Punish(Handle main, MenuAction action, int client, int param2) {
    switch (action) {
        case MenuAction_End:
            CloseHandle(main);
        case MenuAction_Cancel: {
            if(param2 == MenuCancel_ExitBack) {
                CreateAFKMenu(client);
            }
        }
        case MenuAction_Select: {
            char info[32];
            GetMenuItem(main, param2, info, sizeof(info));
            int iInfo = StringToInt(info);
            if(g_targetPlayer[client] == -1337) {
                float time = GetEngineTime();
                for(int i = 1; i <= MaxClients; i++) {
                    if(IsClientInGame(i) && (time-g_fLastAction[i] >= g_iSecGone[client]) && !CheckCommandAccess(i, "sm_afkmenu", ADMFLAG_KICK)) {
                        PunishPlayer(i, iInfo, 0);
                    }
                }
                if(iInfo == 0) {
                    PrintToChat(client, "%s All AFK players will be kicked in %.0f seconds.", gamePrefix, cWarnTime.FloatValue);
                }
            } else {
                int target = GetClientOfUserId(g_targetPlayer[client]);
                if(target) {
                    PunishPlayer(target, iInfo, client);
                }
            }
        }
    }
    return;
}

public void PunishPlayer(int client, int type, int inflictor) {
    PunishPlayerEx(client, type, inflictor, 0);
}

public void PunishPlayerEx(int client, int type, int inflictor, int special) {
    switch(type) {
        case AFK_SPEC: {
            if(special == 2) {
                LogToFile(logFile, "%L was moved to spectate by the auto afk system.", client);
            }
            ChangeClientTeam(client, 1);
        }
        case AFK_KICK: {
            if(special >= 1) {
                LogToFile(logFile, "%L was kicked by the auto afk system.", client);
            }
            KickClient(client, "You were kicked for being AFK. Type retry in console to rejoin");
        }
        case AFK_WARN: {
            if(!g_bWarningPlayer[client]) {
                g_bWarningPlayer[client] = true;
                g_tWarningPlayer[client] = GetEngineTime();
                g_warnType[client] = special;
                CreateTimer(2.0, Timer_WarnRepeat, GetClientUserId(client), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
                //if(special == 2) {
                //    LogToFile(logFile, "%L was warned by the auto afk system.", client);
                //}
                if(inflictor != 0) {
                    PrintToChat(inflictor, "%s %N will be kicked in %.0f seconds.", gamePrefix, client, cWarnTime.FloatValue);
                }
            }
        }
    }
}

public Action Timer_WarnRepeat(Handle timer, any data) {
    int client = GetClientOfUserId(data);
    if(!g_bWarningPlayer[client]) {
        return Plugin_Stop;
    }
    if(g_warnType[client] == 1) {
        if(GetEngineTime() - g_tWarningPlayer[client] >= cAutoEnactTime.FloatValue) {
            if(cAutoMethod.IntValue == 0) {
                PunishPlayerEx(client, AFK_SPEC, 0, 2);
            } else {
                PunishPlayerEx(client, AFK_KICK, 0, 2);
            }
            return Plugin_Stop;
        }
    } else {
        if(GetEngineTime() - g_tWarningPlayer[client] >= cWarnTime.FloatValue) {
            PunishPlayer(client, AFK_KICK, 0);
            return Plugin_Stop;
        }
    }
    PrintToChat(client, "%s Move, shoot or type in chat or you will be moved to spectate or kicked from the server.", gamePrefix);
    return Plugin_Continue;
}

stock int FindUser(float time) {
    for(int i = 1; i <= MaxClients; i++) {
        if(g_fLastAction[i] == time && !g_bLastAction[i]) {
            g_bLastAction[i] = true;
            return i;
        }
    }
    return 0;
}

stock GetTimeFromStamp(int timestamp, char[] TimeStamp, int size) {
    int Hours = (timestamp/60/60) % 24;
    int Mins = (timestamp/60) % 60;
    int Secs = timestamp % 60;
    char sHours[8];
    if(Hours != 0) {
        Format(sHours, 8, "%2d:", Hours);
    }
    Format(TimeStamp, size, "[%s%02d:%02d]", sHours, Mins, Secs);
}
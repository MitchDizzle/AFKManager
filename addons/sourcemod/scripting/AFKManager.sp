#pragma semicolon 1

// ====[ INCLUDES ]============================================================
#include <sdkhooks>

// ====[ DEFINES ]=============================================================
#define PLUGIN_NAME "AFKManager"
#define PLUGIN_VERSION "1.0.0"
#define DEFAFKTIME 60

// ====[ CONFIG ]==============================================================

// ====[ PLYR VARS ]===========================================================
new Float:g_fLastAction[MAXPLAYERS+1] = {0.0, ...};
new bool:g_bLastAction[MAXPLAYERS+1] = {false, ...}; //Used in menu sorting.
new g_iSecGone[MAXPLAYERS+1] = {DEFAFKTIME, ...};
new SortOrder:g_SortOrder[MAXPLAYERS+1] = {Sort_Ascending, ...};
new g_targetPlayer[MAXPLAYERS+1] = {-1, ...};
new bool:g_bWarningPlayer[MAXPLAYERS+1] = {false, ...}; //Used in menu sorting.

// ====[ PLUGIN ]==============================================================
public Plugin:myinfo = {
	name = PLUGIN_NAME,
	author = "Mitch",
	description = "Don't expect anything superficial.",
	version = PLUGIN_VERSION,
	url = "https://github.com/MitchDizzle/AFKManager"
}
// ====[ EVENTS ]==============================================================
public OnPluginStart() {
	CreateConVar("sm_afkmanager_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);
	AddCommandListener(CommandListener);
	RegAdminCmd("sm_afkmenu", Cmd_AFKMenu, ADMFLAG_KICK);
	new Float:eTime = GetEngineTime();
	for(new i=1; i<=MaxClients; i++) {
		if(IsClientInGame(i)) {
			g_fLastAction[client] = eTime;
		}
	}
}

public OnMapEnd() {
	for(new i=1; i<=MaxClients; i++) {
		if(IsClientInGame(i)) {
			g_bWarningPlayer[i] = false;
		}
	}
}

public OnClientDisconnect(client) {
	g_fLastAction[client] = 0.0;
	g_iSecGone[client] = DEFAFKTIME;
	g_SortOrder[client] = Sort_Ascending;
	g_targetPlayer[client] = -1;
}


public Action:CommandListener(client, const String:cmd[], args) {
	if(StrContains(cmd, "say", false) != -1 ) {
		g_fLastAction[client] = GetEngineTime();
	}
	/*if(!StrEqual(cmd, "wait", false) &&
		StrContains(cmd, "+", false) == -1 &&
		StrContains(cmd, "-", false) == -1) {
		g_fLastAction[client] = GetEngineTime(); //Need to add some kind of list of commands that are ignored or something.
	}*/
	return Plugin_Continue;
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon, &subtype, &cmdnum, &tickcount, &seed, mouse[2]) {
	static oButtons[MAXPLAYERS+1];
	if(oButtons[client] != buttons) {
		oButtons[client] = buttons;
		g_fLastAction[client] = GetEngineTime();
	}
}
// ====[ COMMANDS ]==============================================================
public Action:Cmd_AFKMenu(client, args) {
	if(client && IsClientInGame(client)) {
		CreateAFKMenu(client);
	}
	return Plugin_Handled;
}

// ====[ MENUS ]==============================================================
CreateAFKMenu(client) {
	decl String:tempFormat[64];
	new Handle:menu = CreateMenu(Menu_Main, MENU_ACTIONS_DEFAULT);
	SetMenuTitle(menu, "AFK Manager | Main Menu:");
	AddMenuItem(menu, "show", "Show AFK Players\n \nOptions:");

	GetTimeFromStamp(g_iSecGone[client], tempFormat, sizeof(tempFormat));
	Format(tempFormat, sizeof(tempFormat), "Change AFK Time %s", tempFormat);
	AddMenuItem(menu, "afktime", tempFormat);

	Format(tempFormat, sizeof(tempFormat), "Change Order: %s", (g_SortOrder[client] == Sort_Ascending) ? "Ascending" : "Descending");
	AddMenuItem(menu, "order", tempFormat);

	SetMenuPagination(menu, MENU_NO_PAGINATION);
	SetMenuExitButton(menu, true);
	SetMenuExitBackButton(menu, true);
	DisplayMenuAtItem(menu, client, 0, MENU_TIME_FOREVER);
}

public Menu_Main(Handle:main, MenuAction:action, client, param2) {
	switch (action) {
		case MenuAction_End:
			CloseHandle(main);
		case MenuAction_Select:
		{
			new String:info[32];
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

CreateAFKTimeMenu(client) {
	decl String:tempFormat[64];
	GetTimeFromStamp(g_iSecGone[client], tempFormat, sizeof(tempFormat));
	new Handle:menu = CreateMenu(Menu_AFKTime, MENU_ACTIONS_DEFAULT);
	SetMenuTitle(menu, "AFK Manager | AFK Time: %s", tempFormat);
	AddMenuItem(menu, "+30", "+30 Seconds");
	AddMenuItem(menu, "+5", "+5 Seconds");
	AddMenuItem(menu, "+1", "+1 Seconds");
	AddMenuItem(menu, "0", "Default 60 Seconds");
	AddMenuItem(menu, "-1", "-1 Seconds");
	AddMenuItem(menu, "-5", "-5 Seconds");
	AddMenuItem(menu, "-30", "-30 Seconds");

	SetMenuPagination(menu, MENU_NO_PAGINATION);
	SetMenuExitButton(menu, true);
	SetMenuExitBackButton(menu, true);
	DisplayMenuAtItem(menu, client, 0, MENU_TIME_FOREVER);
}

public Menu_AFKTime(Handle:main, MenuAction:action, client, param2) {
	switch (action) {
		case MenuAction_End:
			CloseHandle(main);
		case MenuAction_Cancel:
			CreateAFKMenu(client);
		case MenuAction_Select:
		{
			new String:info[32];
			GetMenuItem(main, param2, info, sizeof(info));
			if (StrEqual(info,"0")) {
				g_iSecGone[client] = DEFAFKTIME;
			} else {
				new num = StringToInt(info);
				g_iSecGone[client] += num;
				if(g_iSecGone[client] < 1) g_iSecGone[client] = 1;
				else if(g_iSecGone[client] > 1200) g_iSecGone[client] = 1200;
			}
			CreateAFKTimeMenu(client);
		}
	}
	return;
}

CreatePlayerMenu(client) {
	new Handle:menu = CreateMenu(Menu_Players, MENU_ACTIONS_DEFAULT);
	SetMenuTitle(menu, "AFK Manager | Players:");
	
	AddMenuItem(menu, "refresh", "Refresh Menu");
	AddMenuItem(menu, "all", "All AFKers\n-----------");
	new Float:tempActionVar[MAXPLAYERS+1];
	for(new i = 0; i <= MAXPLAYERS; i++) {
		g_bLastAction[i] = false;
		tempActionVar[i] = g_fLastAction[i];
	}
	SortFloats(tempActionVar, sizeof(tempActionVar), g_SortOrder[client]);
	new x, time, String:sUserid[5], String:tempFormat[128], players;
	for(new i = 0; i < MAXPLAYERS; i++) {
		x = FindUser(tempActionVar[i]);
		if(x && IsClientInGame(x) && !CheckCommandAccess(x, "sm_afkmenu", ADMFLAG_KICK)) {
			time = RoundToNearest(GetEngineTime() - g_fLastAction[x]);
			if(time >= g_iSecGone[client]) {
				GetTimeFromStamp(time, tempFormat, sizeof(tempFormat));
				Format(tempFormat, sizeof(tempFormat), "%N %s", x, tempFormat);
				IntToString(GetClientUserId(x), sUserid, sizeof(sUserid));
				AddMenuItem(menu, sUserid, tempFormat);
				players++;
			}
		}
	}
	SetMenuExitButton(menu, true);
	SetMenuExitBackButton(menu, true);
	DisplayMenuAtItem(menu, client, 0, MENU_TIME_FOREVER);
}

public Menu_Players(Handle:main, MenuAction:action, client, param2) {
	switch (action) {
		case MenuAction_End:
			CloseHandle(main);
		case MenuAction_Cancel:
			CreateAFKMenu(client);
		case MenuAction_Select: {
			new String:info[32];
			GetMenuItem(main, param2, info, sizeof(info));
			if(StrEqual(info, "refresh", false)) {
				CreatePlayerMenu(client);
			} else if(StrEqual(info, "all", false)) {
				g_targetPlayer[client] = 1337;
				CreatePunishMenu(client);
			} else {
				new target = GetClientOfUserId(StringToInt(info));
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

CreatePunishMenu(client) {
	decl String:tempFormat[64];
	GetTimeFromStamp(g_iSecGone[client], tempFormat, sizeof(tempFormat));
	new Handle:menu = CreateMenu(Menu_Punish, MENU_ACTIONS_DEFAULT);
	SetMenuTitle(menu, "AFK Manager | Punish: %N", GetClientOfUserId(g_targetPlayer[client]));
	AddMenuItem(menu, "warn", "Warn Player", (g_bWarningPlayer[target]) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	AddMenuItem(menu, "spec", "Move To Spectator");
	AddMenuItem(menu, "kick", "Kick Player");

	SetMenuPagination(menu, MENU_NO_PAGINATION);
	SetMenuExitButton(menu, true);
	DisplayMenuAtItem(menu, client, 0, MENU_TIME_FOREVER);
}

public Menu_Punish(Handle:main, MenuAction:action, client, param2) {
	switch (action) {
		case MenuAction_End:
			CloseHandle(main);
		case MenuAction_Cancel:
			CreateAFKMenu(client);
		case MenuAction_Select:
		{
			new String:info[32];
			GetMenuItem(main, param2, info, sizeof(info));
			new target = GetClientOfUserId(g_targetPlayer[client]);
			if(target) {
				if (StrEqual(info,"spec")) {
					ChangeClientTeam(target, 1);
				} else if (StrEqual(info,"kick")) {
					KickClient(target, "AFK For Too Long");
				} else if (StrEqual(info,"warn")) {
					g_bWarningPlayer[target] = true;
					g_tWarningPlayer[target] = GetEngineTime();
					CreateTimer(2.0, Timer_WarnRepeat, StringToInt(info), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
					PrintToChat(target, "[AFK] You have been marked as AFK, type !unafk in chat to continue playing.");
				}
			}
		}
	}
	return;
}

public Action:Timer_WarnRepeat(Handle:timer, any:data) {
	new client = GetClientOfUserId(data);
	if(!g_bWarningPlayer[client]) {
		return Plugin_Stop;
	}
	time = RoundToNearest(GetEngineTime() - g_tWarningPlayer[client]);
	if(time >= 360) {
	
	return Plugin_Continue;
}

// ====[ STOCKS ]==============================================================
stock FindUser(Float:time) {
	for(new i = 1; i <= MaxClients; i++) {
		if(g_fLastAction[i] == time && !g_bLastAction[i]) {
			g_bLastAction[i] = true;
			return i;
		}
	}
	return 0;
}

stock GetTimeFromStamp(timestamp, String:TimeStamp[], size) {
	new Hours = (timestamp / 60 / 60) % 24;
	new Mins = (timestamp / 60) % 60;
	new Secs = timestamp % 60;
	new String:sHours[8];
	Format(sHours, 8, "%2d:", Hours);
	Format(TimeStamp, size, "[%s%02d:%02d]", 
		(Hours != 0) ? sHours : "",
		Mins, Secs);
}
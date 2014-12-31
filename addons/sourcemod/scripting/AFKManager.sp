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
new SortOrder:g_SortOrder[MAXPLAYERS+1] = {Sort_Descending, ...};



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
}

public Action:CommandListener(client, const String:cmd[], args) {
	if(!StrEqual(cmd, "wait", false) && StrContains(cmd, "+", false) == -1) {
		g_fLastAction[client] = GetEngineTime(); //Need to add some kind of list of commands that are ignored or something.
	}
	return Plugin_Continue;
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon, &subtype, &cmdnum, &tickcount, &seed, mouse[2]) {
	g_fLastAction[client] = GetEngineTime();
}
// ====[ COMMANDS ]==============================================================
public Action:Cmd_AFKMenu(client, args) {
	if(client && IsClientInGame(client)) {
		CreateAFKMenu(client);
		CreatePlayerMenu(client);
	}
	return Plugin_Handled;
}

// ====[ MENUS ]==============================================================
CreateAFKMenu(client) {
	decl String:tempFormat[64];
	new Handle:menu = CreateMenu(Menu_Main, MENU_ACTIONS_DEFAULT);
	SetMenuTitle(menu, "AFK Manager | Main Menu:");
	AddMenuItem(menu, "show", "Show AFK Players\n ");

	GetTimeFromStamp(g_iSecGone[client], tempFormat, sizeof(tempFormat));
	Format(tempFormat, sizeof(tempFormat), "Change AFK Time %s", tempFormat);
	AddMenuItem(menu, "afktime", tempFormat);

	Format(tempFormat, sizeof(tempFormat), "Change Order: %s", tempFormat, (g_SortOrder[client] == Sort_Ascending) ? "Ascending" : "Descending");
	AddMenuItem(menu, "order", tempFormat);

	SetMenuExitButton(menu, true);
	DisplayMenuAtItem(menu, client, 0, MENU_TIME_FOREVER);
}

CreatePlayerMenu(client) {

	new Handle:menu = CreateMenu(Menu_Players, MENU_ACTIONS_DEFAULT);
	SetMenuTitle(menu, "AFK Manager | Players:");
	
	new Float:tempActionVar[MAXPLAYERS+1];
	for(new i = 0; i <= MAXPLAYERS; i++) {
		g_bLastAction[i] = false;
		tempActionVar[i] = g_fLastAction[i];
	}
	SortFloats(tempActionVar, sizeof(tempActionVar), g_SortOrder[client]);
	new x, time, String:sUserid[5], String:tempFormat[128];
	for(new i = 0; i <= MAXPLAYERS; i++) {
		x = FindUser(tempActionVar[i]);
		if(x && IsClientInGame(x)) {
			time = RoundToNearest(GetEngineTime() - g_fLastAction[x]);
			if(time >= g_iSecGone[client]) {
				GetTimeFromStamp(time, tempFormat, sizeof(tempFormat));
				Format(tempFormat, sizeof(tempFormat), "%N %s", tempFormat);
				IntToString(GetClientUserId(x), sUserid, sizeof(sUserid));
				AddMenuItem(menu, sUserid, tempFormat);
			}
		}
	}
	SetMenuExitButton(menu, true);
	DisplayMenuAtItem(menu, client, 0, MENU_TIME_FOREVER);
}

// ====[ STOCKS ]==============================================================
stock FindUser(Float:time) {
	for(new i = 0; i <= MAXPLAYERS; i++) {
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
//AFKManager include file.

#if defined _AFKMANAGER_included
 #endinput
#endif
#define _AFKMANAGER_included

/**
 * Checks if a player is considered AFK.
 * -1.0 will use default menu afk time. (120 seconds afk)
 * -2.0 will use sm_afkmanager_autowarntime value
 * This is basically just a nicer wrapper for: 
 * GetEngineTime() - AFKManager_GetLastAction() > time
 */
native bool AFKManager_IsAFK(int client, float time=-1.0);

/**
 * Returns the time in which the player did an action.
 * Everytime does something different than they have previously.
 * Every action is stored from GetEngineTime();
 */
native float AFKManager_GetLastAction(int client);

public SharedPlugin __pl_AFKManager = {
	name = "AFKManager",
	file = "AFKManager.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_AFKManager_SetNTVOptional() {
	MarkNativeAsOptional("AFKManager_IsAFK");
	MarkNativeAsOptional("AFKManager_GetLastAction");
}
#endif

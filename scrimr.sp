#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <cstrike>

new String:CHAT_PREFIX[7] = "SCRIMR";

enum State {
    STATE_NULL = 0,
    STATE_WARMUP = 1,
    STATE_KNIFE = 2,
    STATE_LIVE = 3
};

new knife_winner = -1;
new map_number = 0;
new g_iAccount = -1;
new State:STATE = STATE_NULL;
new String:mapA[32], String:mapB[32], String:mapC[32];

new TEAMS_READY[2];
new WHICH_TEAMS[MAXPLAYERS + 1];

MessageChat(index, const String:format[], any:...) {
    new String:msg[2048];
    VFormat(msg, 2048, format, 3);

    if (index >= 0) {
        PrintToChat(index, "\x01 \x09[\x04%s\x09]\x01 %s", CHAT_PREFIX, msg);
    } else {
        PrintToChatAll("\x01 \x09[\x04%s\x09]\x01 %s", CHAT_PREFIX, msg);
    }
}

public Plugin:myinfo = {
    name = "Scrimr",
    author = "B1nzy",
    description = "Scrim bot for CS:GO games",
    version = "0.0.1",
    url = "github.com/b1naryth1ef/scrimr"
};

public OnPluginStart() {
    g_iAccount = FindSendPropOffs("CCSPlayer", "m_iAccount");

    RegAdminCmd("ko3", KnifeOnThree, ADMFLAG_CUSTOM1,
        "Starts the knife-round on three countdown.");
    RegAdminCmd("setup", Setup, ADMFLAG_CUSTOM1,
        "Sets up a match.");
    RegAdminCmd("next", NextMap, ADMFLAG_CUSTOM1,
        "Switches to the next map.");

    RegConsoleCmd("say", SayChat);
    RegConsoleCmd("say_team", SayChat);

    HookEvent("round_start", Event_Round_Start);
    HookEvent("round_end", Event_Round_End);
    HookEvent("announce_phase_end", MatchEnd);
    HookEvent("player_team", Event_Player_Team_Pre, EventHookMode_Pre);
}

public OnMapStart() {
    map_number += 1;
    STATE = STATE_WARMUP;
}

SwitchNextMap() {
    switch (map_number) {
        case 1:
            ServerCommand("map %s", mapB);
        case 2:
            ServerCommand("map %s", mapC);
    }
}

public MatchEnd(Handle:event, const String:name[], bool:dontBroadcast) {
}

public Event_Player_Team_Pre(Handle:event, const String:name[], bool:dontBroadcast) {
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    new new_team = GetEventInt(event, "team");
    
    if (map_number >= 2) {
        SetEventInt(event, "team", WHICH_TEAMS[client]);
    }
}


public Action:NextMap(client, args) {
    SwitchNextMap();
    return Plugin_Handled;
}

// .setup de_nuke de_inferno de_cache
public Action:Setup(client, args) {
    GetCmdArg(1, mapA, 32);
    GetCmdArg(2, mapB, 32);
    GetCmdArg(3, mapC, 32);

    if (!IsMapValid(mapA) || !IsMapValid(mapB) || !IsMapValid(mapC)) {
        MessageChat(client, "Invalid Maps!");
        return Plugin_Handled;
    }

    ServerCommand("map %s", mapA);

    return Plugin_Handled;
}


public Action:KnifeOnThree(client, args) {
    StartKnifeRound();
    return Plugin_Handled;
}

public Event_Round_Start(Handle:event, const String:name[], bool:dontBroadcast) {
    if (STATE == STATE_KNIFE) {
        for (new i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && GetClientTeam(i) > 1) {
                CS_StripButKnife(i);
                SetEntData(i, g_iAccount, 0);
            }
        }
    }
}

public Event_Round_End(Handle:event, const String:name[], bool:dontBroadcast) {
    if (STATE == STATE_KNIFE) {
        knife_winner = GetEventInt(event, "winner");
        ServerCommand("mp_pause_match 1");

        for (new i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && GetClientTeam(i) == knife_winner) {
                MessageChat(i, "Please have the team leader type .stay or .swap in chat!");
            }
        }
    }
}

stock CS_EquipKnife(client) {
    ClientCommand(client, "slot3");
}

stock CS_StripButKnife(client, bool:equip=true) {
    if (!IsClientInGame(client) || GetClientTeam(client) <= 1)
    {
        return false;
    }
    
    new item_index;
    for (new i = 0; i < 5; i++)
    {
        if (i == 2)
        {
            continue;
        }
        if ((item_index = GetPlayerWeaponSlot(client, i)) != -1)
        {
            RemovePlayerItem(client, item_index);
            RemoveEdict(item_index);
        }
        if (equip)
        {
            CS_EquipKnife(client);
        }
    }

    return true;
}


CheckReady() {
    // If both teams are ready start the game
    if (!TEAMS_READY[0] || !TEAMS_READY[1]) {
        return;
    }

    // Reset states
    TEAMS_READY[0] = false;
    TEAMS_READY[1] = false;

    // Start the match
    StartMatch();
}

StartDemo() {
    decl String:map_name[128], String:demo_filename[256], String:date[32], String:team_a[64],
        String:team_b[64];

    GetCurrentMap(map_name, sizeof(map_name));
    GetTeamName(CS_TEAM_T, team_a, sizeof(team_a));
    GetTeamName(CS_TEAM_CT, team_b, sizeof(team_b));

    FormatTime(date, sizeof(date), "%Y-%m-%d-%H%M");
    Format(demo_filename, sizeof(demo_filename), "%s-%04x-%s-%s-vs-%s", date, GetConVarInt(FindConVar("hostport")),
        map_name, team_a, team_b);

    ServerCommand("tv_record %s.dem", demo_filename);
}

StartMatch() {
    STATE = STATE_LIVE;
    MessageChat(-1, "BOTH TEAMS READY! STARTING GAME!");
    ServerCommand("mp_warmup_end");
    ServerCommand("mp_restartgame 6");
    CreateTimer(6.0, TIMER_MessageStart);

    // If this wasnt the first match, we won't have a demo running from knife round and thus need to
    //  start the demo.
    if (map_number != 1) {
        StartDemo();
    }
}

StartKnifeRound() {
    STATE = STATE_KNIFE;
    MessageChat(-1, "KNIFE ROUND IS LIVE ON THREE...");
    ServerCommand("mp_warmup_end");
    ServerCommand("mp_restartgame 6");
    CreateTimer(6.0, TIMER_MessageKnife);

    StartDemo();
}

public Action:TIMER_MessageStart(Handle:timer) {
    for (new i = 0; i < 5; i++) {
        MessageChat(-1, "!! GAME IS LIVE !!");
    }
}

public Action:TIMER_MessageKnife(Handle:timer) {
    for (new i = 0; i < 5; i++) {
        MessageChat(-1, "!! KNIFE ROUND IS LIVE !!");
    }
}

StoreTeams() {
    for (new i = 1; i <= MaxClients; i++) {
        WHICH_TEAMS[i] = GetClientTeam(i);
    }
}

public Action:SayChat(client, args) {
    if (client == 0) {
        return Plugin_Handled;
    }

    new String:message[192];
    GetCmdArgString(message, sizeof(message));
    StripQuotes(message);

    if (message[0] == '.' || message[0] == '!') {
        new String:command[192];
        strcopy(command, sizeof(message), message[1]);

        if (StrEqual(command, "stay", false) || StrEqual(command, "swap", false)) {
            if (STATE == STATE_KNIFE && knife_winner == GetClientTeam(client)) {
                new String:this_team[32]; //, String:other_team[32];
                GetTeamName(knife_winner, this_team, 32);
                // GetTeamName(knife_winner == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T, other_team, 32);

                if (StrEqual(command, "stay", false)) {
                    MessageChat(-1, "%s's team will stay.");
                    MessageChat(-1, "%s's are staying on same side.", this_team);
                } else {
                    MessageChat(-1, "%s's are switching to opposite side.", this_team);
                    ServerCommand("mp_swapteams");
                    // TODO: switch team names?
                }

                ServerCommand("mp_unpause_match 1");
                STATE = STATE_WARMUP;
                ServerCommand("mp_warmup_start");
                StoreTeams();
            }
        } else if (StrEqual(command, "ready", false)) {
            if (!TEAMS_READY[GetClientTeam(client) - 2]) {
                TEAMS_READY[GetClientTeam(client) - 2] = true;

                new String:team_name[32];
                GetTeamName(GetClientTeam(client), team_name, sizeof(team_name));
                MessageChat(-1, "%s are ready.", team_name);

                CheckReady();
            }
        } else if (StrEqual(command, "unready", false)) {
            if (TEAMS_READY[GetClientTeam(client) - 2]) {
                TEAMS_READY[GetClientTeam(client) - 2] = false;

                new String:team_name[32];
                GetTeamName(GetClientTeam(client), team_name, sizeof(team_name));
                MessageChat(-1, "%s are no longer ready.", team_name);

                CheckReady();
            }
        }
    }

    return Plugin_Handled;
}
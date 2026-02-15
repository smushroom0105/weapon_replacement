#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <clientprefs>

#define PLUGIN_VERSION "5.1"

// Weapon definitions
#define W_P2000  "weapon_hkp2000"
#define W_USP    "weapon_usp_silencer"
#define W_M4A4   "weapon_m4a1"
#define W_M4A1   "weapon_m4a1_silencer"
#define W_MP7    "weapon_mp7"
#define W_MP5    "weapon_mp5sd"
#define W_DEAGLE "weapon_deagle"
#define W_R8     "weapon_revolver"
#define W_FIVE7  "weapon_fiveseven"
#define W_TEC9   "weapon_tec9"
#define W_CZ75   "weapon_cz75a"

// Prices
#define P_P2000 200
#define P_USP   200
#define P_M4A4  3100
#define P_M4A1  2900
#define P_MP7   1500
#define P_MP5   1500
#define P_DEAGLE 700
#define P_R8    600
#define P_FIVE7 500
#define P_TEC9  500
#define P_CZ75  500

enum struct PlayerPref
{
    bool p2000;
    bool m4a4;
    bool mp7;
    bool deagle;
    bool pistols;
    bool loaded;
}

PlayerPref gPref[MAXPLAYERS + 1];

ConVar gDefP2000, gDefM4A4, gDefMP7, gDefDeagle, gDefPistols;
ConVar gGameType, gGameMode;

Handle gCookie = null;
bool gIsDM = false;

StringMap gPrices;
StringMap gSlots;

bool gSkipReplace[MAXPLAYERS + 1]; // For bot takeover protection
bool gHasReplacedOnSpawn[MAXPLAYERS + 1]; // To prevent repeated initial replacements

public Plugin myinfo =
{
    name        = "CSGO Weapon Replacer (Legacy)",
    author      = "Qwen3-Coder Plus",
    description = "根据玩家偏好自动替换武器",
    version     = PLUGIN_VERSION,
    url         = "https://github.com/smushroom0105/weapon_replacement"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_gunsettings", CmdSettings);
    RegConsoleCmd("sm_resetguns", CmdReset);

    gDefP2000   = CreateConVar("sm_weapon_default_p2000",   "1", "默认是否将P2000替换为USP", _, true, 0.0, true, 1.0);
    gDefM4A4    = CreateConVar("sm_weapon_default_m4a4",    "0", "默认是否将M4A4替换为M4A1-S", _, true, 0.0, true, 1.0);
    gDefMP7     = CreateConVar("sm_weapon_default_mp7",     "1", "默认是否将MP7替换为MP5-SD", _, true, 0.0, true, 1.0);
    gDefDeagle  = CreateConVar("sm_weapon_default_deagle",  "1", "默认是否将Deagle替换为R8", _, true, 0.0, true, 1.0);
    gDefPistols = CreateConVar("sm_weapon_default_pistols", "1", "默认是否将FN57/TEC9替换为CZ75", _, true, 0.0, true, 1.0);

    gCookie = RegClientCookie("weapon_replacement_prefs", "玩家武器替换偏好", CookieAccess_Protected);

    HookEvent("item_purchase", EventPurchase);
    HookEvent("player_spawn",  EventSpawn);
    HookEvent("player_death",  EventDeath);

    HookEvent("bot_takeover", EventBotTakeover);
    HookEvent("player_bot_replace", EventBotTakeover);
    HookEvent("bot_player_replace", EventBotTakeover);

    gGameType = FindConVar("game_type");
    gGameMode = FindConVar("game_mode");
    if (gGameType) gGameType.AddChangeHook(OnGameModeChanged);
    if (gGameMode) gGameMode.AddChangeHook(OnGameModeChanged);

    InitData();
    AutoExecConfig(true, "weapon_replacement");

    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && !IsFakeClient(i) && AreClientCookiesCached(i))
            OnClientCookiesCached(i);

    UpdateGameMode();
}

public void OnGameModeChanged(ConVar c, const char[] o, const char[] n) { UpdateGameMode(); }

void UpdateGameMode()
{
    gIsDM = (gGameType && gGameMode && gGameType.IntValue == 1 && gGameMode.IntValue == 2);
}

void InitData()
{
    gPrices = new StringMap();
    gPrices.SetValue(W_P2000, P_P2000);
    gPrices.SetValue(W_USP,   P_USP);
    gPrices.SetValue(W_M4A4,  P_M4A4);
    gPrices.SetValue(W_M4A1,  P_M4A1);
    gPrices.SetValue(W_MP7,   P_MP7);
    gPrices.SetValue(W_MP5,   P_MP5);
    gPrices.SetValue(W_DEAGLE,P_DEAGLE);
    gPrices.SetValue(W_R8,    P_R8);
    gPrices.SetValue(W_FIVE7, P_FIVE7);
    gPrices.SetValue(W_TEC9,  P_TEC9);
    gPrices.SetValue(W_CZ75,  P_CZ75);

    gSlots = new StringMap();
    gSlots.SetValue(W_M4A4, 0); gSlots.SetValue(W_M4A1, 0);
    gSlots.SetValue(W_MP7,  0); gSlots.SetValue(W_MP5,  0);
    gSlots.SetValue(W_P2000,1); gSlots.SetValue(W_USP,  1);
    gSlots.SetValue(W_FIVE7,1); gSlots.SetValue(W_TEC9, 1);
    gSlots.SetValue(W_CZ75, 1); gSlots.SetValue(W_DEAGLE,1);
    gSlots.SetValue(W_R8,   1);
}

public void OnClientCookiesCached(int client)
{
    if (IsFakeClient(client)) return;
    LoadPrefs(client);
}

void LoadPrefs(int client)
{
    char cookie[32];
    GetClientCookie(client, gCookie, cookie, sizeof(cookie));

    gPref[client].p2000  = gDefP2000.BoolValue;
    gPref[client].m4a4   = gDefM4A4.BoolValue;
    gPref[client].mp7    = gDefMP7.BoolValue;
    gPref[client].deagle = gDefDeagle.BoolValue;
    gPref[client].pistols= gDefPistols.BoolValue;

    if (strlen(cookie))
    {
        char p[5][4];
        if (ExplodeString(cookie, ",", p, 5, 4) == 5)
        {
            gPref[client].p2000  = StringToInt(p[0]) != 0;
            gPref[client].m4a4   = StringToInt(p[1]) != 0;
            gPref[client].mp7    = StringToInt(p[2]) != 0;
            gPref[client].deagle = StringToInt(p[3]) != 0;
            gPref[client].pistols= StringToInt(p[4]) != 0;
        }
        else SavePrefs(client);
    }
    else SavePrefs(client);

    gPref[client].loaded = true;
}

void SavePrefs(int client)
{
    char buf[32];
    Format(buf, sizeof(buf), "%d,%d,%d,%d,%d",
        gPref[client].p2000,
        gPref[client].m4a4,
        gPref[client].mp7,
        gPref[client].deagle,
        gPref[client].pistols);
    SetClientCookie(client, gCookie, buf);
}

public Action CmdSettings(int client, int args)
{
    if (!IsReal(client)) { ReplyToCommand(client, "[SM] 你必须在游戏中。"); return Plugin_Handled; }
    if (!gPref[client].loaded){ ReplyToCommand(client, "[SM] 设置尚未加载。"); return Plugin_Handled; }
    ShowMenu(client);
    return Plugin_Handled;
}

public Action CmdReset(int client, int args)
{
    if (!IsReal(client)) { ReplyToCommand(client, "[SM] 你必须在游戏中。"); return Plugin_Handled; }

    gPref[client].p2000  = gDefP2000.BoolValue;
    gPref[client].m4a4   = gDefM4A4.BoolValue;
    gPref[client].mp7    = gDefMP7.BoolValue;
    gPref[client].deagle = gDefDeagle.BoolValue;
    gPref[client].pistols= gDefPistols.BoolValue;

    SavePrefs(client);
    PrintToChat(client, "[SM] 武器偏好已重置为默认值！");
    if (IsPlayerAlive(client)) CheckReplace(client);
    ShowMenu(client);
    return Plugin_Handled;
}

void ShowMenu(int client)
{
    Menu m = new Menu(MenuSettings);
    m.SetTitle("武器替换设置 (%N)", client);

    char line[64];
    Format(line, sizeof(line), "P2000 → USP消音版: %s", gPref[client].p2000 ? "启用" : "禁用");
    m.AddItem("p2000", line);
    Format(line, sizeof(line), "M4A4 → M4A1-S: %s", gPref[client].m4a4 ? "启用" : "禁用");
    m.AddItem("m4a4", line);
    Format(line, sizeof(line), "MP7 → MP5-SD: %s", gPref[client].mp7 ? "启用" : "禁用");
    m.AddItem("mp7", line);
    Format(line, sizeof(line), "沙鹰 → R8左轮: %s", gPref[client].deagle ? "启用" : "禁用");
    m.AddItem("deagle", line);
    Format(line, sizeof(line), "FN57/TEC9 → CZ75: %s", gPref[client].pistols ? "启用" : "禁用");
    m.AddItem("pistols", line);

    m.ExitButton = true;
    m.Display(client, 30);
}

public int MenuSettings(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        char key[16];
        menu.GetItem(item, key, sizeof(key));

        bool recheck = false;
        if (StrEqual(key, "p2000"))   { gPref[client].p2000  = !gPref[client].p2000;  recheck = gPref[client].p2000  && GetClientTeam(client)==CS_TEAM_CT; }
        else if (StrEqual(key, "m4a4")) { gPref[client].m4a4   = !gPref[client].m4a4;   recheck = gPref[client].m4a4   && GetClientTeam(client)==CS_TEAM_CT; }
        else if (StrEqual(key, "mp7"))   { gPref[client].mp7    = !gPref[client].mp7;    recheck = gPref[client].mp7; }
        else if (StrEqual(key, "deagle")){ gPref[client].deagle = !gPref[client].deagle; recheck = gPref[client].deagle; }
        else if (StrEqual(key, "pistols")){ gPref[client].pistols= !gPref[client].pistols;recheck = gPref[client].pistols; }

        SavePrefs(client);
        if (IsPlayerAlive(client) && recheck) CheckReplace(client);
        ShowMenu(client);
    }
    else if (action == MenuAction_End) delete menu;
    return 0;
}

public Action EventSpawn(Event e, const char[] n, bool nb)
{
    int client = GetClientOfUserId(e.GetInt("userid"));
    if (!IsReal(client) || !IsPlayerAlive(client)) return Plugin_Continue;

    // Reset the flag on spawn so it only runs once per spawn cycle (when not from death)
    gHasReplacedOnSpawn[client] = false;
    
    // Only run initial replacement if not coming back from a death that immediately respawned with same weapons
    if (!gHasReplacedOnSpawn[client]) {
        CreateTimer(gIsDM ? 1.5 : 1.0, TimerInitial, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
        gHasReplacedOnSpawn[client] = true;
    }
    return Plugin_Continue;
}

public Action EventDeath(Event e, const char[] n, bool nb)
{
    int client = GetClientOfUserId(e.GetInt("userid"));
    if (IsReal(client)) {
        gSkipReplace[client] = false;
        gHasReplacedOnSpawn[client] = false; // Reset on death to allow replacement on next spawn
    }
    return Plugin_Continue;
}

public Action EventBotTakeover(Event e, const char[] name, bool nb)
{
    int userid = e.GetInt("userid");
    if (userid == 0) userid = e.GetInt("player");
    int client = GetClientOfUserId(userid);
    if (!IsReal(client)) return Plugin_Continue;

    gSkipReplace[client] = true;
    CreateTimer(0.5, TimerClearSkip, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Continue;
}

public Action TimerClearSkip(Handle t, any userid)
{
    int client = GetClientOfUserId(userid);
    if (IsReal(client)) gSkipReplace[client] = false;
    return Plugin_Stop;
}

public Action TimerInitial(Handle t, any userid)
{
    int client = GetClientOfUserId(userid);
    if (IsReal(client) && IsPlayerAlive(client) && gPref[client].loaded)
        CheckReplace(client);
    return Plugin_Stop;
}

void CheckReplace(int client)
{
    if (gSkipReplace[client])
    {
        gSkipReplace[client] = false;
        return;
    }

    int team = GetClientTeam(client);

    if (team == CS_TEAM_CT)
    {
        if (gPref[client].m4a4   && FindWeapon(client, W_M4A1) == -1) ReplaceDelayed(client, W_M4A4,  W_M4A1,  false);
        if (gPref[client].p2000  && FindWeapon(client, W_USP)  == -1) ReplaceDelayed(client, W_P2000, W_USP,  false);
        if (gPref[client].pistols&& FindWeapon(client, W_CZ75) == -1) ReplaceDelayed(client, W_FIVE7, W_CZ75, false);
    }
    else if (team == CS_TEAM_T && gPref[client].pistols)
    {
        if (FindWeapon(client, W_CZ75) == -1) ReplaceDelayed(client, W_TEC9, W_CZ75, false);
    }

    if (gPref[client].mp7    && FindWeapon(client, W_MP5) == -1) ReplaceDelayed(client, W_MP7, W_MP5, false);
    if (gPref[client].deagle && FindWeapon(client, W_R8)  == -1) ReplaceDelayed(client, W_DEAGLE, W_R8, false);
}

public Action EventPurchase(Event e, const char[] n, bool nb)
{
    int client = GetClientOfUserId(e.GetInt("userid"));
    if (!IsReal(client) || !IsPlayerAlive(client) || !gPref[client].loaded) return Plugin_Continue;

    char weapon[32];
    e.GetString("weapon", weapon, sizeof(weapon));
    // Normalize: remove "weapon_" prefix if present
    if (StrContains(weapon, "weapon_") == 0) strcopy(weapon, sizeof(weapon), weapon[7]);

    if (gPref[client].p2000 && StrEqual(weapon, "hkp2000") && FindWeapon(client, W_USP) == -1)
        ReplaceDelayed(client, W_P2000, W_USP, true);
    else if (gPref[client].m4a4 && StrEqual(weapon, "m4a1") && FindWeapon(client, W_M4A1) == -1)
        ReplaceDelayed(client, W_M4A4, W_M4A1, true);
    else if (gPref[client].mp7 && StrEqual(weapon, "mp7") && FindWeapon(client, W_MP5) == -1)
        ReplaceDelayed(client, W_MP7, W_MP5, true);
    else if (gPref[client].deagle && StrEqual(weapon, "deagle") && FindWeapon(client, W_R8) == -1)
        ReplaceDelayed(client, W_DEAGLE, W_R8, true);
    else if (gPref[client].pistols)
    {
        if (GetClientTeam(client) == CS_TEAM_CT && StrEqual(weapon, "fiveseven") && FindWeapon(client, W_CZ75) == -1)
            ReplaceDelayed(client, W_FIVE7, W_CZ75, true);
        else if (GetClientTeam(client) == CS_TEAM_T && StrEqual(weapon, "tec9") && FindWeapon(client, W_CZ75) == -1)
            ReplaceDelayed(client, W_TEC9, W_CZ75, true);
    }
    return Plugin_Continue;
}

void ReplaceDelayed(int client, const char[] oldW, const char[] newW, bool refund)
{
    DataPack dp = new DataPack();
    dp.WriteCell(GetClientUserId(client));
    dp.WriteString(oldW);
    dp.WriteString(newW);
    dp.WriteCell(refund);
    CreateTimer(gIsDM ? 0.5 : 0.2, TimerReplace, dp, TIMER_FLAG_NO_MAPCHANGE);
}

public Action TimerReplace(Handle t, DataPack dp)
{
    dp.Reset();
    int client = GetClientOfUserId(dp.ReadCell());
    char oldW[32]; dp.ReadString(oldW, sizeof(oldW));
    char newW[32]; dp.ReadString(newW, sizeof(newW));
    bool refund = dp.ReadCell();
    delete dp;

    if (!IsReal(client) || !IsPlayerAlive(client)) return Plugin_Stop;

    int oldEnt = FindWeapon(client, oldW);
    if (oldEnt == -1) return Plugin_Stop;

    if (FindWeapon(client, newW) != -1)
    {
        RemovePlayerItem(client, oldEnt);
        AcceptEntityInput(oldEnt, "Kill");
        return Plugin_Stop;
    }

    int oldPrice, newPrice;
    if (!gPrices.GetValue(oldW, oldPrice) || !gPrices.GetValue(newW, newPrice))
        return Plugin_Stop;

    int newEnt;
    if (gIsDM)
    {
        newEnt = GivePlayerItem(client, newW);
        if (newEnt != -1 && IsValidEntity(newEnt))
        {
            EquipPlayerWeapon(client, newEnt);
            RemovePlayerItem(client, oldEnt);
            AcceptEntityInput(oldEnt, "Kill");
        }
    }
    else
    {
        RemovePlayerItem(client, oldEnt);
        AcceptEntityInput(oldEnt, "Kill");
        newEnt = GivePlayerItem(client, newW);
        if (newEnt != -1 && IsValidEntity(newEnt))
            EquipPlayerWeapon(client, newEnt);
    }

    if (newEnt == -1 || !IsValidEntity(newEnt)) return Plugin_Stop;

    int slot;
    if (gSlots.GetValue(newW, slot) && GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") != newEnt)
        ClientCommand(client, "use %s", newW);

    if (refund && oldPrice != newPrice)
    {
        int money = GetEntProp(client, Prop_Send, "m_iAccount");
        money += (oldPrice - newPrice);
        if (money < 0) money = 0;
        if (money > 16000) money = 16000;
        SetEntProp(client, Prop_Send, "m_iAccount", money);
    }

    return Plugin_Stop;
}

int FindWeapon(int client, const char[] cls)
{
    for (int i = 0; i < 64; i++)
    {
        int ent = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
        if (ent == -1) break;
        char name[32];
        if (GetEntityClassname(ent, name, sizeof(name)) && StrEqual(name, cls))
            return ent;
    }
    return -1;
}

bool IsReal(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

public void OnClientDisconnect(int client)
{
    gPref[client].loaded = false;
    gSkipReplace[client] = false;
    gHasReplacedOnSpawn[client] = false;
}

public void OnPluginEnd()
{
    delete gPrices;
    delete gSlots;
}

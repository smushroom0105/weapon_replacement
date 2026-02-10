#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <clientprefs>

#define PLUGIN_VERSION "3.3"

// 武器定义常量
#define WEAPON_P2000        "weapon_hkp2000"
#define WEAPON_USP          "weapon_usp_silencer"
#define WEAPON_M4A4         "weapon_m4a1"
#define WEAPON_M4A1         "weapon_m4a1_silencer"
#define WEAPON_MP7          "weapon_mp7"
#define WEAPON_MP5          "weapon_mp5sd"
#define WEAPON_DEAGLE       "weapon_deagle"
#define WEAPON_R8           "weapon_revolver"
#define WEAPON_FIVESEVEN    "weapon_fiveseven"
#define WEAPON_TEC9         "weapon_tec9"
#define WEAPON_CZ75         "weapon_cz75a"

// 武器价格枚举
enum WeaponPrice {
    PRICE_P2000 = 200,
    PRICE_USP = 200,
    PRICE_M4A4 = 3100,
    PRICE_M4A1 = 2900,
    PRICE_MP7 = 1500,
    PRICE_MP5 = 1500,
    PRICE_DEAGLE = 700,
    PRICE_R8 = 600,
    PRICE_FIVESEVEN = 500,
    PRICE_TEC9 = 500,
    PRICE_CZ75 = 500
};

// 玩家设置结构体
enum struct PlayerSettings {
    bool ReplaceP2000;
    bool ReplaceM4A4;
    bool ReplaceMP7;
    bool ReplaceDeagle;
    bool ReplacePistols;
    bool Loaded;
}

// 全局变量
Handle g_hCookie = null;
ConVar g_cvDefaultP2000, g_cvDefaultM4A4, g_cvDefaultMP7, g_cvDefaultDeagle, g_cvDefaultPistols;
ConVar g_cvGameType, g_cvGameMode;
bool g_bIsDeathmatch = false;

PlayerSettings g_PlayerSettings[MAXPLAYERS + 1];
ArrayList g_ReplaceQueue[MAXPLAYERS + 1];

StringMap g_WeaponPrices;
StringMap g_WeaponSlots;

public Plugin myinfo = {
    name = "CS:GO 武器替换插件",
    author = "Qwen3-Coder",
    description = "根据玩家偏好自动替换武器",
    version = PLUGIN_VERSION,
    url = "https://github.com/smushroom0105/weapon_replacement"
};

void InitializeWeaponData()
{
    g_WeaponPrices = new StringMap();
    g_WeaponPrices.SetValue(WEAPON_P2000, PRICE_P2000);
    g_WeaponPrices.SetValue(WEAPON_USP, PRICE_USP);
    g_WeaponPrices.SetValue(WEAPON_M4A4, PRICE_M4A4);
    g_WeaponPrices.SetValue(WEAPON_M4A1, PRICE_M4A1);
    g_WeaponPrices.SetValue(WEAPON_MP7, PRICE_MP7);
    g_WeaponPrices.SetValue(WEAPON_MP5, PRICE_MP5);
    g_WeaponPrices.SetValue(WEAPON_DEAGLE, PRICE_DEAGLE);
    g_WeaponPrices.SetValue(WEAPON_R8, PRICE_R8);
    g_WeaponPrices.SetValue(WEAPON_FIVESEVEN, PRICE_FIVESEVEN);
    g_WeaponPrices.SetValue(WEAPON_TEC9, PRICE_TEC9);
    g_WeaponPrices.SetValue(WEAPON_CZ75, PRICE_CZ75);

    g_WeaponSlots = new StringMap();
    g_WeaponSlots.SetValue(WEAPON_USP, 1);
    g_WeaponSlots.SetValue(WEAPON_P2000, 1);
    g_WeaponSlots.SetValue(WEAPON_FIVESEVEN, 1);
    g_WeaponSlots.SetValue(WEAPON_TEC9, 1);
    g_WeaponSlots.SetValue(WEAPON_CZ75, 1);
    g_WeaponSlots.SetValue(WEAPON_DEAGLE, 1);
    g_WeaponSlots.SetValue(WEAPON_R8, 1);
    g_WeaponSlots.SetValue(WEAPON_M4A4, 0);
    g_WeaponSlots.SetValue(WEAPON_M4A1, 0);
    g_WeaponSlots.SetValue(WEAPON_MP7, 0);
    g_WeaponSlots.SetValue(WEAPON_MP5, 0);
}

public void OnPluginStart()
{
    RegConsoleCmd("sm_gunsettings", Command_GunSettings, "打开武器替换设置菜单");
    RegConsoleCmd("sm_resetguns", Command_ResetSettings, "将武器偏好重置为默认值");

    g_cvDefaultP2000 = CreateConVar("sm_weapon_default_p2000", "1", "默认是否将P2000替换为USP (0 = 否, 1 = 是)", _, true, 0.0, true, 1.0);
    g_cvDefaultM4A4 = CreateConVar("sm_weapon_default_m4a4", "0", "默认是否将M4A4替换为M4A1-S", _, true, 0.0, true, 1.0);
    g_cvDefaultMP7 = CreateConVar("sm_weapon_default_mp7", "1", "默认是否将MP7替换为MP5-SD", _, true, 0.0, true, 1.0);
    g_cvDefaultDeagle = CreateConVar("sm_weapon_default_deagle", "1", "默认是否将Deagle替换为R8", _, true, 0.0, true, 1.0);
    g_cvDefaultPistols = CreateConVar("sm_weapon_default_pistols", "1", "默认是否将FN57/TEC9替换为CZ75", _, true, 0.0, true, 1.0);

    g_hCookie = RegClientCookie("weapon_replacement_prefs", "玩家武器替换偏好", CookieAccess_Protected);

    HookEvent("item_purchase", Event_ItemPurchase);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);

    g_cvGameType = FindConVar("game_type");
    g_cvGameMode = FindConVar("game_mode");

    if (g_cvGameType != null) g_cvGameType.AddChangeHook(OnGameModeChanged);
    if (g_cvGameMode != null) g_cvGameMode.AddChangeHook(OnGameModeChanged);

    for (int i = 0; i <= MAXPLAYERS; i++) {
        g_ReplaceQueue[i] = new ArrayList(ByteCountToCells(64));
    }

    InitializeWeaponData();
    LoadTranslations("common.phrases");
    AutoExecConfig(true, "weapon_replacement");

    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i) && AreClientCookiesCached(i)) {
            OnClientCookiesCached(i);
        }
    }

    CheckGameMode();
}

public void OnGameModeChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    CheckGameMode();
}

void CheckGameMode()
{
    if (g_cvGameType == null || g_cvGameMode == null) {
        g_bIsDeathmatch = false;
        return;
    }
    g_bIsDeathmatch = (g_cvGameType.IntValue == 1 && g_cvGameMode.IntValue == 2);
}

public void OnConfigsExecuted()
{
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i) && AreClientCookiesCached(i)) {
            LoadPlayerSettings(i);
        }
    }
}

public void OnClientCookiesCached(int client)
{
    if (IsFakeClient(client)) return;
    LoadPlayerSettings(client);
}

void LoadPlayerSettings(int client)
{
    char cookie[32];
    GetClientCookie(client, g_hCookie, cookie, sizeof(cookie));

    g_PlayerSettings[client].ReplaceP2000 = g_cvDefaultP2000.BoolValue;
    g_PlayerSettings[client].ReplaceM4A4 = g_cvDefaultM4A4.BoolValue;
    g_PlayerSettings[client].ReplaceMP7 = g_cvDefaultMP7.BoolValue;
    g_PlayerSettings[client].ReplaceDeagle = g_cvDefaultDeagle.BoolValue;
    g_PlayerSettings[client].ReplacePistols = g_cvDefaultPistols.BoolValue;

    if (strlen(cookie) > 0) {
        char parts[5][8];
        if (ExplodeString(cookie, ",", parts, 5, 8) == 5) {
            bool valid = true;
            for (int i = 0; i < 5; i++) {
                TrimString(parts[i]);
                if (!IsCharNumeric(parts[i][0]) || strlen(parts[i]) != 1) {
                    valid = false;
                    break;
                }
            }
            if (valid) {
                g_PlayerSettings[client].ReplaceP2000 = StringToInt(parts[0]) != 0;
                g_PlayerSettings[client].ReplaceM4A4 = StringToInt(parts[1]) != 0;
                g_PlayerSettings[client].ReplaceMP7 = StringToInt(parts[2]) != 0;
                g_PlayerSettings[client].ReplaceDeagle = StringToInt(parts[3]) != 0;
                g_PlayerSettings[client].ReplacePistols = StringToInt(parts[4]) != 0;
            } else {
                SavePlayerSettings(client);
            }
        } else {
            SavePlayerSettings(client);
        }
    } else {
        SavePlayerSettings(client);
    }

    g_PlayerSettings[client].Loaded = true;
}

void SavePlayerSettings(int client)
{
    char buffer[32];
    Format(buffer, sizeof(buffer), "%d,%d,%d,%d,%d",
        g_PlayerSettings[client].ReplaceP2000,
        g_PlayerSettings[client].ReplaceM4A4,
        g_PlayerSettings[client].ReplaceMP7,
        g_PlayerSettings[client].ReplaceDeagle,
        g_PlayerSettings[client].ReplacePistols
    );
    SetClientCookie(client, g_hCookie, buffer);
}

public Action Command_GunSettings(int client, int args)
{
    if (!IsValidClient(client)) {
        ReplyToCommand(client, "[SM] 你必须在游戏中才能使用此命令！");
        return Plugin_Handled;
    }
    if (!g_PlayerSettings[client].Loaded) {
        ReplyToCommand(client, "[SM] 设置尚未加载，请稍后再试！");
        return Plugin_Handled;
    }
    ShowSettingsMenu(client);
    return Plugin_Handled;
}

public Action Command_ResetSettings(int client, int args)
{
    if (!IsValidClient(client)) {
        ReplyToCommand(client, "[SM] 你必须在游戏中才能使用此命令！");
        return Plugin_Handled;
    }

    g_PlayerSettings[client].ReplaceP2000 = g_cvDefaultP2000.BoolValue;
    g_PlayerSettings[client].ReplaceM4A4 = g_cvDefaultM4A4.BoolValue;
    g_PlayerSettings[client].ReplaceMP7 = g_cvDefaultMP7.BoolValue;
    g_PlayerSettings[client].ReplaceDeagle = g_cvDefaultDeagle.BoolValue;
    g_PlayerSettings[client].ReplacePistols = g_cvDefaultPistols.BoolValue;

    SavePlayerSettings(client);
    PrintToChat(client, "[SM] 武器偏好已重置为默认值！");

    if (IsPlayerAlive(client)) {
        CheckAndReplaceWeapons(client);
    }

    ShowSettingsMenu(client);
    return Plugin_Handled;
}

void ShowSettingsMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Settings, MENU_ACTIONS_ALL);
    menu.SetTitle("武器替换设置 (%N)", client);

    char buffer[64];
    Format(buffer, sizeof(buffer), "P2000 → USP消音版: %s", g_PlayerSettings[client].ReplaceP2000 ? "启用" : "禁用");
    menu.AddItem("p2000", buffer);
    Format(buffer, sizeof(buffer), "M4A4 → M4A1-S: %s", g_PlayerSettings[client].ReplaceM4A4 ? "启用" : "禁用");
    menu.AddItem("m4a4", buffer);
    Format(buffer, sizeof(buffer), "MP7 → MP5-SD: %s", g_PlayerSettings[client].ReplaceMP7 ? "启用" : "禁用");
    menu.AddItem("mp7", buffer);
    Format(buffer, sizeof(buffer), "沙漠之鹰 → R8左轮: %s", g_PlayerSettings[client].ReplaceDeagle ? "启用" : "禁用");
    menu.AddItem("deagle", buffer);
    Format(buffer, sizeof(buffer), "FN57/TEC9 → CZ75: %s", g_PlayerSettings[client].ReplacePistols ? "启用" : "禁用");
    menu.AddItem("pistols", buffer);

    menu.ExitButton = true;
    menu.Display(client, 30);
}

public int MenuHandler_Settings(Menu menu, MenuAction action, int client, int param2)
{
    if (action == MenuAction_Select) {
        char item[32];
        menu.GetItem(param2, item, sizeof(item));
        bool recheck = false;

        if (StrEqual(item, "p2000")) {
            g_PlayerSettings[client].ReplaceP2000 = !g_PlayerSettings[client].ReplaceP2000;
            PrintToChat(client, "[SM] P2000 → USP消音版: %s", g_PlayerSettings[client].ReplaceP2000 ? "已启用" : "已禁用");
            recheck = g_PlayerSettings[client].ReplaceP2000 && GetClientTeam(client) == CS_TEAM_CT;
        } else if (StrEqual(item, "m4a4")) {
            g_PlayerSettings[client].ReplaceM4A4 = !g_PlayerSettings[client].ReplaceM4A4;
            PrintToChat(client, "[SM] M4A4 → M4A1-S: %s", g_PlayerSettings[client].ReplaceM4A4 ? "已启用" : "已禁用");
            recheck = g_PlayerSettings[client].ReplaceM4A4 && GetClientTeam(client) == CS_TEAM_CT;
        } else if (StrEqual(item, "mp7")) {
            g_PlayerSettings[client].ReplaceMP7 = !g_PlayerSettings[client].ReplaceMP7;
            PrintToChat(client, "[SM] MP7 → MP5-SD: %s", g_PlayerSettings[client].ReplaceMP7 ? "已启用" : "已禁用");
            recheck = g_PlayerSettings[client].ReplaceMP7;
        } else if (StrEqual(item, "deagle")) {
            g_PlayerSettings[client].ReplaceDeagle = !g_PlayerSettings[client].ReplaceDeagle;
            PrintToChat(client, "[SM] 沙漠之鹰 → R8左轮: %s", g_PlayerSettings[client].ReplaceDeagle ? "已启用" : "已禁用");
            recheck = g_PlayerSettings[client].ReplaceDeagle;
        } else if (StrEqual(item, "pistols")) {
            g_PlayerSettings[client].ReplacePistols = !g_PlayerSettings[client].ReplacePistols;
            PrintToChat(client, "[SM] FN57/TEC9 → CZ75: %s", g_PlayerSettings[client].ReplacePistols ? "已启用" : "已禁用");
            recheck = g_PlayerSettings[client].ReplacePistols;
        }

        SavePlayerSettings(client);
        if (IsPlayerAlive(client) && recheck) {
            CheckAndReplaceWeapons(client);
        }
        ShowSettingsMenu(client);
    } else if (action == MenuAction_End) {
        delete menu;
    }
    return 0;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client) || !IsPlayerAlive(client)) return Plugin_Continue;

    g_ReplaceQueue[client].Clear();
    CreateTimer(g_bIsDeathmatch ? 1.5 : 1.0, Timer_CheckInitialWeapons, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client)) {
        g_ReplaceQueue[client].Clear();
    }
    return Plugin_Continue;
}

public Action Timer_CheckInitialWeapons(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client) || !IsPlayerAlive(client) || !g_PlayerSettings[client].Loaded) return Plugin_Stop;

    CheckAndReplaceWeapons(client);
    return Plugin_Stop;
}

void CheckAndReplaceWeapons(int client)
{
    if (GetClientTeam(client) == CS_TEAM_CT) {
        if (g_PlayerSettings[client].ReplaceM4A4 && FindWeapon(client, WEAPON_M4A1) == -1)
            ReplaceWeapon(client, WEAPON_M4A4, WEAPON_M4A1, false);
        if (g_PlayerSettings[client].ReplaceP2000 && FindWeapon(client, WEAPON_USP) == -1)
            ReplaceWeapon(client, WEAPON_P2000, WEAPON_USP, false);
        if (g_PlayerSettings[client].ReplacePistols && FindWeapon(client, WEAPON_CZ75) == -1)
            ReplaceWeapon(client, WEAPON_FIVESEVEN, WEAPON_CZ75, false);
    } else if (GetClientTeam(client) == CS_TEAM_T && g_PlayerSettings[client].ReplacePistols) {
        if (FindWeapon(client, WEAPON_CZ75) == -1)
            ReplaceWeapon(client, WEAPON_TEC9, WEAPON_CZ75, false);
    }

    if (g_PlayerSettings[client].ReplaceMP7 && FindWeapon(client, WEAPON_MP5) == -1)
        ReplaceWeapon(client, WEAPON_MP7, WEAPON_MP5, false);
    if (g_PlayerSettings[client].ReplaceDeagle && FindWeapon(client, WEAPON_R8) == -1)
        ReplaceWeapon(client, WEAPON_DEAGLE, WEAPON_R8, false);
}

public Action Event_ItemPurchase(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client) || !IsPlayerAlive(client) || !g_PlayerSettings[client].Loaded) return Plugin_Continue;

    char weapon[32];
    event.GetString("weapon", weapon, sizeof(weapon));

    char normalized[32];
    if (StrContains(weapon, "weapon_") == 0) {
        strcopy(normalized, sizeof(normalized), weapon[7]);
    } else {
        strcopy(normalized, sizeof(normalized), weapon);
    }

    g_ReplaceQueue[client].Clear();

    if (g_PlayerSettings[client].ReplaceP2000 && StrEqual(normalized, "hkp2000") && FindWeapon(client, WEAPON_USP) == -1)
        ReplaceWeapon(client, WEAPON_P2000, WEAPON_USP, true);
    else if (g_PlayerSettings[client].ReplaceM4A4 && StrEqual(normalized, "m4a1") && FindWeapon(client, WEAPON_M4A1) == -1)
        ReplaceWeapon(client, WEAPON_M4A4, WEAPON_M4A1, true);
    else if (g_PlayerSettings[client].ReplaceMP7 && StrEqual(normalized, "mp7") && FindWeapon(client, WEAPON_MP5) == -1)
        ReplaceWeapon(client, WEAPON_MP7, WEAPON_MP5, true);
    else if (g_PlayerSettings[client].ReplaceDeagle && StrEqual(normalized, "deagle") && FindWeapon(client, WEAPON_R8) == -1)
        ReplaceWeapon(client, WEAPON_DEAGLE, WEAPON_R8, true);
    else if (g_PlayerSettings[client].ReplacePistols) {
        if (GetClientTeam(client) == CS_TEAM_CT && StrEqual(normalized, "fiveseven") && FindWeapon(client, WEAPON_CZ75) == -1)
            ReplaceWeapon(client, WEAPON_FIVESEVEN, WEAPON_CZ75, true);
        else if (GetClientTeam(client) == CS_TEAM_T && StrEqual(normalized, "tec9") && FindWeapon(client, WEAPON_CZ75) == -1)
            ReplaceWeapon(client, WEAPON_TEC9, WEAPON_CZ75, true);
    }

    return Plugin_Continue;
}

void ReplaceWeapon(int client, const char[] oldWeapon, const char[] newWeapon, bool refundMoney = true)
{
    char info[64];
    Format(info, sizeof(info), "%s;%s", oldWeapon, newWeapon);
    g_ReplaceQueue[client].PushString(info);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(info);
    pack.WriteCell(refundMoney);
    float delay = g_bIsDeathmatch ? 0.5 : 0.2;
    CreateTimer(delay, Timer_ProcessReplace, pack, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ProcessReplace(Handle timer, DataPack pack)
{
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    char info[64];
    pack.ReadString(info, sizeof(info));
    bool refundMoney = pack.ReadCell();
    delete pack;

    if (!IsValidClient(client) || !IsPlayerAlive(client)) return Plugin_Stop;

    int index = g_ReplaceQueue[client].FindString(info);
    if (index == -1) return Plugin_Stop;
    g_ReplaceQueue[client].Erase(index);

    char parts[2][32];
    if (ExplodeString(info, ";", parts, 2, 32) != 2) return Plugin_Stop;

    char oldWeapon[32], newWeapon[32];
    strcopy(oldWeapon, sizeof(oldWeapon), parts[0]);
    strcopy(newWeapon, sizeof(newWeapon), parts[1]);

    int weapon = FindWeapon(client, oldWeapon);
    if (weapon == -1) return Plugin_Stop;

    if (FindWeapon(client, newWeapon) != -1) {
        RemovePlayerItem(client, weapon);
        AcceptEntityInput(weapon, "Kill");
        return Plugin_Stop;
    }

    int oldPrice, newPrice;
    if (!g_WeaponPrices.GetValue(oldWeapon, oldPrice) || !g_WeaponPrices.GetValue(newWeapon, newPrice)) return Plugin_Stop;

    int newEnt = -1;
    if (g_bIsDeathmatch) {
        newEnt = GivePlayerItem(client, newWeapon);
        if (newEnt != -1 && IsValidEntity(newEnt)) {
            EquipPlayerWeapon(client, newEnt);
            RemovePlayerItem(client, weapon);
            AcceptEntityInput(weapon, "Kill");
        }
    } else {
        RemovePlayerItem(client, weapon);
        AcceptEntityInput(weapon, "Kill");
        newEnt = GivePlayerItem(client, newWeapon);
        if (newEnt != -1 && IsValidEntity(newEnt)) {
            EquipPlayerWeapon(client, newEnt);
        }
    }

    if (newEnt == -1 || !IsValidEntity(newEnt)) return Plugin_Stop;

    int slot = GetWeaponSlot(newWeapon);
    if (slot != -1 && GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") != newEnt) {
        ClientCommand(client, "use %s", newWeapon);
    }

    if (refundMoney && oldPrice != newPrice) {
        int currentMoney = GetEntProp(client, Prop_Send, "m_iAccount");
        int diff = oldPrice - newPrice;
        int newMoney = currentMoney + diff;
        newMoney = (newMoney < 0) ? 0 : (newMoney > 16000) ? 16000 : newMoney;
        SetEntProp(client, Prop_Send, "m_iAccount", newMoney);
    }

    return Plugin_Stop;
}

int FindWeapon(int client, const char[] weaponClass)
{
    for (int i = 0; i < 64; i++) {
        int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
        if (weapon == -1) break;
        char classname[32];
        if (GetEntityClassname(weapon, classname, sizeof(classname)) && StrEqual(classname, weaponClass)) {
            return weapon;
        }
    }
    return -1;
}

int GetWeaponSlot(const char[] weapon)
{
    int slot;
    if (g_WeaponSlots.GetValue(weapon, slot)) return slot;
    return -1;
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

public void OnClientDisconnect(int client)
{
    g_PlayerSettings[client].Loaded = false;
    g_ReplaceQueue[client].Clear();
}

public void OnPluginEnd()
{
    for (int i = 0; i <= MAXPLAYERS; i++) {
        delete g_ReplaceQueue[i];
    }
    delete g_WeaponPrices;
    delete g_WeaponSlots;
}

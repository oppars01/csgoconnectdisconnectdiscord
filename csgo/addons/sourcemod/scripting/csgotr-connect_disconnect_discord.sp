#include <sourcemod>
#include <discord>
#include <csgoturkiye>
#include <geoip>
#include <steamworks>

#pragma semicolon 1

public Plugin myinfo = 
{
	name = "Connect Disconnect Discord Message", 
	author = "oppa", 
	description = "Server Player Connect and Disconnect Discord Message", 
	version = "1.0", 
	url = "csgo-turkiye.com"
};

char s_webhook[256], s_webhook_admin[256], s_flags[4], s_map_name[128], s_apikey[64], s_avatar[ MAXPLAYERS+1 ][255];
ConVar cv_webhook = null, cv_webhook_admin = null, cv_flags = null, cv_apikey = null;

public void OnPluginStart(){   
    CVAR_Load();
}

public void OnMapStart(){
    GetCurrentMap(s_map_name, sizeof(s_map_name));
    Discord_EscapeString(s_map_name, sizeof(s_map_name));
    CVAR_Load();
    LoadTranslations("csgotr-connect_disconnect_discord.phrases.txt");
}

void CVAR_Load(){
    PluginSetting();
    cv_webhook = CreateConVar( "sm_connect_disconnect_player_webhook", "", "Discord Webhook URL for players." );
    cv_apikey = CreateConVar( "sm_connect_disconnect_apikey", "", "Steam Api Key" );
    cv_webhook_admin = CreateConVar( "sm_connect_disconnect_admin_webhook", "", "Discord Webhook URL for admins." );
    cv_flags = CreateConVar( "sm_connect_disconnect_admin_flag", "-", "Who counts as admin? ROOT is automatically authorized. You can put a comma (,) between letters. Maximum 32 characters. If you use a hyphen (-), any authorized admin will be counted." );
    AutoExecConfig(true, "discord_connect_disconnect","CSGO_Turkiye");
    GetConVarString(cv_webhook, s_webhook, sizeof(s_webhook));
    GetConVarString(cv_webhook_admin, s_webhook_admin, sizeof(s_webhook_admin));
    GetConVarString(cv_flags, s_flags, sizeof(s_flags));
    GetConVarString(cv_apikey, s_apikey, sizeof(s_apikey));
    HookConVarChange(cv_flags, OnCvarChanged);
    HookConVarChange(cv_webhook, OnCvarChanged);
    HookConVarChange(cv_webhook_admin, OnCvarChanged);
    HookConVarChange(cv_apikey, OnCvarChanged);
}

public int OnCvarChanged(Handle convar, const char[] oldVal, const char[] newVal){
    if(convar == cv_webhook) strcopy(s_webhook, sizeof(s_webhook), newVal);
    else if(convar == cv_webhook_admin) strcopy(s_webhook_admin, sizeof(s_webhook_admin), newVal);
    else if(convar == cv_flags) strcopy(s_flags, sizeof(s_flags), newVal);
    else if(convar == cv_apikey) strcopy(s_apikey, sizeof(s_apikey), newVal);
}

public void OnClientPostAdminCheck(int client){
    if (IsValidClient(client))
	{
        Format(s_avatar[client], sizeof(s_avatar[]), "https://cdn.akamai.steamstatic.com/steamcommunity/public/images/avatars/fe/fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb_full.jpg");
        if(strlen(s_apikey)>=30) RequestAvatar(client);
        else DiscordMessageConnectDisconnect(client);
    }
}

public void OnClientDisconnect(int client){
    DiscordMessageConnectDisconnect(client, false);
}

void RequestAvatar(int client)
{
    if(IsValidClient(client)){
        char s_temp[255];  
        if(!GetClientAuthId(client, AuthId_SteamID64, s_temp, sizeof(s_temp)))DiscordMessageConnectDisconnect(client);
        else{
            Format(s_temp, sizeof(s_temp), "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=%s&steamids=%s&format=vdf", s_apikey, s_temp);
            Handle h_request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, s_temp);
            SteamWorks_SetHTTPRequestNetworkActivityTimeout(h_request, 10);
            SteamWorks_SetHTTPRequestContextValue(h_request, client);
            SteamWorks_SetHTTPCallbacks(h_request, GetAvatar);
            SteamWorks_SendHTTPRequest(h_request);
        }
    }
}

void GetAvatar(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, int client) 
{
    if(!IsValidClient(client)){
        delete hRequest;
    }else{
        if (!bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK) 
        {
            delete hRequest;
            PrintToServer("%s %t", s_tag, "Get Avatar Error");
        }else{
            int i_response_size;
            SteamWorks_GetHTTPResponseBodySize(hRequest, i_response_size);
            char[] s_response = new char[i_response_size];
            SteamWorks_GetHTTPResponseBodyData(hRequest, s_response, i_response_size);
            delete hRequest;
            KeyValues kv_data = new KeyValues("response");
            if (kv_data.ImportFromString(s_response))if (kv_data.JumpToKey("players"))if (kv_data.GotoFirstSubKey())kv_data.GetString("avatarfull", s_avatar[client], sizeof(s_avatar[]));
            delete kv_data;
        }
    }
    DiscordMessageConnectDisconnect(client);
} 

void DiscordMessageConnectDisconnect(int client, bool connect = true){
    if(IsValidClient(client)){
        bool b_admin = CheckAdminFlag(client, s_flags);
        char s_temp[255], s_temp_2[255];
        if(b_admin)strcopy(s_temp, sizeof(s_temp), s_webhook_admin);
        else strcopy(s_temp, sizeof(s_temp), s_webhook);
        if(!StrEqual(s_temp, "")){
            DiscordWebHook hook = new DiscordWebHook(s_temp);
            hook.SlackMode = true;
            MessageEmbed Embed = new MessageEmbed();
            if(connect)Format(s_temp, sizeof(s_temp), "#00ff00");
            else Format(s_temp, sizeof(s_temp), "#ff0000");
            Embed.SetColor(s_temp);
            if(b_admin && connect) Format(s_temp, sizeof(s_temp), "%t", "Admin Connect Title");
            else if(b_admin && !connect) Format(s_temp, sizeof(s_temp), "%t", "Admin Disconnect Title");
            else if(!b_admin && connect) Format(s_temp, sizeof(s_temp), "%t", "Player Connect Title");
            else Format(s_temp, sizeof(s_temp), "%t", "Player Disconnect Title");
            Embed.SetTitle(s_temp);
            if(GetClientAuthId(client, AuthId_SteamID64, s_temp, sizeof(s_temp)))Format(s_temp, sizeof(s_temp), "http://steamcommunity.com/profiles/%s", s_temp);
            else Format(s_temp, sizeof(s_temp), "http://steamcommunity.com");
            Embed.SetTitleLink(s_temp);
            if(StrEqual(s_avatar[client],""))Format(s_avatar[client], sizeof(s_avatar[]), "https://cdn.akamai.steamstatic.com/steamcommunity/public/images/avatars/fe/fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb_full.jpg");
            Embed.SetThumb(s_avatar[client]);
            Format(s_temp_2, sizeof(s_temp_2), "%t", "Username");
            if(!GetClientName(client, s_temp, sizeof(s_temp)))Format(s_temp, sizeof(s_temp), "%t", "Unnamed");
            Discord_EscapeString(s_temp, sizeof(s_temp));
            Format(s_temp, sizeof(s_temp), "%t", "Username Value", s_temp);
            Embed.AddField(s_temp_2, s_temp,true);
            Format(s_temp_2, sizeof(s_temp_2), "%t", "Steam ID");
            if(!GetClientAuthId(client, AuthId_Steam2, s_temp, sizeof(s_temp)))Format(s_temp, sizeof(s_temp), "%t", "Unknown Steam ID");
            Discord_EscapeString(s_temp, sizeof(s_temp));
            Format(s_temp, sizeof(s_temp), "%t", "Steam ID Value", s_temp);
            Embed.AddField(s_temp_2, s_temp, true);
            if(GetClientIP(client, s_temp_2, sizeof(s_temp_2), true)){
                if (!GeoipCountry(s_temp_2, s_temp, sizeof(s_temp)))Format(s_temp, sizeof(s_temp), "%t", "Unknown Country");
                else{
                    char s_country_code[3];
                    if(GeoipCode2(s_temp_2, s_country_code)){
                        for(int i = 0; i <= strlen(s_country_code); ++i)s_country_code[i] = CharToLower(s_country_code[i]);
                        Format(s_temp, sizeof(s_temp), "%s - :flag_%s:", s_temp, s_country_code);
                    }
                }
            }else Format(s_temp, sizeof(s_temp), "%t", "Unknown Country");
            Format(s_temp_2, sizeof(s_temp_2), "%t", "Country");
            Discord_EscapeString(s_temp, sizeof(s_temp));
            Format(s_temp, sizeof(s_temp), "%t", "Country Value", s_temp);
            Embed.AddField(s_temp_2, s_temp, false);
            Format(s_temp_2, sizeof(s_temp_2), "%t", "Map Name");
            Format(s_temp, sizeof(s_temp), "%t", "Map Name Value", s_map_name);
            Embed.AddField(s_temp_2, s_temp, false);
            int i_total = 0;
            for (int i = 1; i <= MaxClients; i++) if(IsValidClient(i)) i_total++;
            if(!connect){
                i_total--;
                if(i_total < 0) i_total = 0;
            }
            Format(s_temp_2, sizeof(s_temp_2), "%t", "Players");
            Format(s_temp, sizeof(s_temp), "%t", "Players Value", i_total, GetMaxHumanPlayers());
            Embed.AddField(s_temp_2, s_temp, false);
            if(!connect){
                Format(s_temp_2, sizeof(s_temp_2), "%t", "Time Played");
                Format(s_temp, sizeof(s_temp), "%t", "Time Played Value", RoundToCeil(GetClientTime(client)/60));
                Embed.AddField(s_temp_2, s_temp,true);
            }
            FormatTime(s_temp, sizeof(s_temp), "%d.%m.20%y ✪ %X", GetTime());
            Format(s_temp_2, sizeof(s_temp_2), "%s %t", s_tag, "Footer", s_temp );
            Embed.SetFooter(s_temp_2);
            hook.Embed(Embed);
            hook.Send();
            delete hook;
            if(!connect)Format(s_avatar[client], sizeof(s_avatar[]), "");
        }
    }
}

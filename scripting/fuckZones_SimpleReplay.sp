#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#undef REQUIRE_PLUGIN
#include <fuckZones>

#pragma newdecls required
#pragma semicolon 1

// replay meta
#define REPLAY_HEADER "{fuckZones_Replay}{TEST}"

enum struct frame_t
{
	float pos[3];
	float ang[2];
	int buttons;
	int flags;
	MoveType mt;
}

// custom cvar settings
char gS_ForcedCvars[][][] =
{
	{ "bot_quota", "1" },
	{ "bot_stop", "1" },
	{ "bot_quota_mode", "normal" },
	{ "mp_limitteams", "0" },
	{ "bot_join_after_player", "0" },
	{ "bot_chatter", "off" },
	{ "bot_flipout", "1" },
	{ "bot_zombie", "1" },
	{ "mp_autoteambalance", "0" },
	{ "bot_controllable", "0" }
};

// only 1 replay bot, sorry
ArrayList gA_ReplayFrames = null;
int gI_ReplayFrame;

// player frames
ArrayList gA_PlayerFrames[MAXPLAYERS+1];
int gI_PlayerFrames[MAXPLAYERS+1];

// server specific
float gF_Tickrate = 0.0;
char gS_Map[160];

// replay folder
char gS_ReplayFolder[PLATFORM_MAX_PATH];

public Plugin myinfo =
{
	name = "fuckZones - SimpleReplay",
	author = "Ciallo",
	description = "Simple replay plugin for fuckZones based on shavit's replay.",
	version = "1.0.0",
	url = "github.com/Bara"
};

public void OnPluginStart()
{
	gF_Tickrate = (1.0 / GetTickInterval());

	char sFolder[PLATFORM_MAX_PATH];
	FormatEx(sFolder, PLATFORM_MAX_PATH, "data/replays");
	BuildPath(Path_SM, sFolder, PLATFORM_MAX_PATH, "%s", sFolder);
	strcopy(gS_ReplayFolder, PLATFORM_MAX_PATH, sFolder);

	FindConVar("bot_stop").Flags &= ~FCVAR_CHEAT;

	for(int i = 0; i < sizeof(gS_ForcedCvars); i++)
	{
		ConVar hCvar = FindConVar(gS_ForcedCvars[i][0]);

		if(hCvar != null)
		{
			hCvar.SetString(gS_ForcedCvars[i][1]);
			hCvar.AddChangeHook(OnForcedConVarChanged);
		}
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		// late load
		if(IsValidClient(i))
		{
			OnClientPutInServer(i);
		}
	}

	RegConsoleCmd("sm_replay", Command_Replay);
}

public void OnForcedConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	char sName[32];
	convar.GetName(sName, 32);

	for(int i = 0; i < sizeof(gS_ForcedCvars); i++)
	{
		if(StrEqual(sName, gS_ForcedCvars[i][0]))
		{
			if(!StrEqual(newValue, gS_ForcedCvars[i][1]))
			{
				convar.SetString(gS_ForcedCvars[i][1]);
			}

			break;
		}
	}
}

public void OnMapStart()
{
	if(!DirExists(gS_ReplayFolder))
	{
		CreateDirectory(gS_ReplayFolder, 511);
	}

	ClearBotFrames();
	GetCurrentMap(gS_Map, 160);
}

public void OnClientPutInServer(int client)
{
	if(!IsFakeClient(client))
	{
		ClearFrames(client);
	}
}

public void OnClientDisconnect(int client)
{
	delete gA_PlayerFrames[client];
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrContains(classname, "trigger_") != -1)
	{
		SDKHook(entity, SDKHook_StartTouch, HookTriggers);
		SDKHook(entity, SDKHook_EndTouch, HookTriggers);
		SDKHook(entity, SDKHook_Touch, HookTriggers);
		SDKHook(entity, SDKHook_Use, HookTriggers);
	}
}

public Action HookTriggers(int entity, int other)
{
	if(1 <= other <= MaxClients && IsFakeClient(other))
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Command_Replay(int client, int args)
{
	if(!LoadReplay())
	{
		PrintToChat(client, "Load Replay failed");
	}

	return Plugin_Handled;
}

// you can load cksurf, gokz, shavit, btimes, influx and some other replays by different headers, and some meta stuff
// if your replay dont have a header, just load it by using 'if else'
// if there are two different plugins' replay and both dont have header, you screwed
bool LoadReplay()
{
	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%s.replay", gS_ReplayFolder, gS_Map);
	
	if(!FileExists(sPath))
	{
		return false;
	}

	File fFile = OpenFile(sPath, "rb");

	char sHeader[64];
	if(!fFile.ReadLine(sHeader, 64))
	{
		return false;
	}

	int iFrameCount;
	fFile.ReadInt32(iFrameCount);

	any aReplayData[sizeof(frame_t)];

	delete gA_ReplayFrames;
	gA_ReplayFrames = new ArrayList(sizeof(frame_t), iFrameCount);

	for(int i = 0; i < iFrameCount; i++)
	{
		if(fFile.Read(aReplayData, sizeof(frame_t), 4) >= 0)
		{
			gA_ReplayFrames.SetArray(i, aReplayData, sizeof(frame_t));
		}
	}

	delete fFile;

	return true;
}

public void fuckZones_OnStartTouchZone_Post(int client, int entity, const char[] zone_name, int type)
{
	if(IsFakeClient(client))
	{
		return;
	}

	if(type == ZONE_TYPE_BOX)// set type box as startzone LUL
	{
		gI_PlayerFrames[client] = 0;
	}

	else if(type == ZONE_TYPE_CIRCLE)// set type circle as endzone LUL
	{
		if(SaveReplay(client))
		{
			PrintToChat(client, "save replay success.");
		}

		ClearFrames(client);
	}
}

// remember to save replay by headers first!!!
bool SaveReplay(int client)
{
	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%s.replay", gS_ReplayFolder, gS_Map);
	
	if(FileExists(sPath))
	{
		DeleteFile(sPath);
	}

	File fFile = OpenFile(sPath, "wb");
	// write meta here
	fFile.WriteLine(REPLAY_HEADER);
	fFile.WriteInt32(gA_PlayerFrames[client].Length);

	// use 'any' type to store origin[3], angles[2], buttons, flags, movetype
	any aFrameData[sizeof(frame_t)];

	for(int i = 0; i < gA_PlayerFrames[client].Length; i++)
	{
		gA_PlayerFrames[client].GetArray(i, aFrameData, sizeof(frame_t));
		fFile.Write(aFrameData, sizeof(frame_t), 4);
	}

	gA_ReplayFrames = gA_PlayerFrames[client].Clone();
	gI_ReplayFrame = 0;

	delete fFile;

	return true;
}

void ClearFrames(int client)
{
	delete gA_PlayerFrames[client];
	gA_PlayerFrames[client] = new ArrayList(sizeof(frame_t));
	gI_PlayerFrames[client] = 0;
}

void ClearBotFrames()
{
	delete gA_ReplayFrames;
	gA_ReplayFrames = new ArrayList(sizeof(frame_t));
	gI_ReplayFrame = 0;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3])
{
	if(!IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	if(IsFakeClient(client))
	{
		return OnReplayCmd(client, buttons, vel);
	}

	else if(!IsFakeClient(client) && IsValidClient(client))
	{
		gA_PlayerFrames[client].Resize(gI_PlayerFrames[client] + 1);

		//origin[3], angles[2], buttons, flags, movetype
		frame_t aFrame;
		
		GetClientAbsOrigin(client, aFrame.pos);
		float vecEyes[3];
		GetClientEyeAngles(client, vecEyes);
		aFrame.ang[0] = vecEyes[0];
		aFrame.ang[1] = vecEyes[1];
		aFrame.buttons = buttons;
		aFrame.flags = GetEntityFlags(client);
		aFrame.mt = GetEntityMoveType(client);

		gA_PlayerFrames[client].SetArray(gI_PlayerFrames[client], aFrame, sizeof(aFrame));

		gI_PlayerFrames[client]++;
	}

	return Plugin_Continue;
}

Action OnReplayCmd(int bot, int &buttons, float vel[3])
{
	buttons = 0;

	vel[0] = 0.0;
	vel[1] = 0.0;

	SetEntProp(bot, Prop_Data, "m_CollisionGroup", 2);// noblock
	SetEntityMoveType(bot, MOVETYPE_NOCLIP);// make bot smooth

	int iFrameCount = gA_ReplayFrames.Length;

	if(gA_ReplayFrames == null || iFrameCount <= 0) // if no replay is loaded
	{
		return Plugin_Changed;
	}

	if(iFrameCount >= 1)
	{
		if(++gI_ReplayFrame >= iFrameCount)
		{
			gI_ReplayFrame = 0;

			return Plugin_Changed;
		}

		// origin[3], angles[2], buttons, flags, movetype
		frame_t aFrame;
		gA_ReplayFrames.GetArray(gI_ReplayFrame, aFrame, sizeof(aFrame));

		buttons = aFrame.buttons;

		bool bWalk = false;
		MoveType mt = MOVETYPE_NOCLIP;

		int iReplayFlags = aFrame.flags;
		int iEntityFlags = GetEntityFlags(bot);
		ApplyFlags(iEntityFlags, iReplayFlags, FL_ONGROUND);
		ApplyFlags(iEntityFlags, iReplayFlags, FL_PARTIALGROUND);
		ApplyFlags(iEntityFlags, iReplayFlags, FL_INWATER);
		ApplyFlags(iEntityFlags, iReplayFlags, FL_SWIM);
		SetEntityFlags(bot, iEntityFlags);

		if(aFrame.mt == MOVETYPE_LADDER)
		{
			mt = aFrame.mt;
		}
		
		else if(aFrame.mt == MOVETYPE_WALK && (iReplayFlags & FL_ONGROUND) > 0)
		{
			bWalk = true;
		}

		SetEntityMoveType(bot, mt);
		
		float vecCurrentPosition[3];
		GetEntPropVector(bot, Prop_Send, "m_vecOrigin", vecCurrentPosition);

		float vecVelocity[3];
		MakeVectorFromPoints(vecCurrentPosition, aFrame.pos, vecVelocity);
		ScaleVector(vecVelocity, gF_Tickrate);

		float ang[3];
		ang[0] = aFrame.ang[0];
		ang[1] = aFrame.ang[1];

		// shavit idea
		// replay is going above 50k speed, just teleport at this point
		// bot is on ground.. if the distance between the previous position is much bigger (1.5x) than the expected according
		// to the bot's velocity, teleport to avoid sync issues
		if((GetVectorLength(vecVelocity) > 50000.0 ||
			(bWalk && GetVectorDistance(vecCurrentPosition, aFrame.pos) > GetVectorLength(vecVelocity) / gF_Tickrate * 1.5)))
		{
			TeleportEntity(bot, aFrame.pos, ang, NULL_VECTOR);
		}

		else
		{
			TeleportEntity(bot, NULL_VECTOR, ang, vecVelocity);
		}
	}

	return Plugin_Changed;
}

void ApplyFlags(int &flags1, int flags2, int flag)
{
	if((flags2 & flag) != 0)
	{
		flags1 |= flag;
	}
	else
	{
		flags1 &= ~flag;
	}
}

bool IsValidClient(int client)
{
	return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client));
}

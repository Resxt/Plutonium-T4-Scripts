/*
======================================================================
|                         Game: Plutonium T4                          |
|                   Description : Let players vote                    |
|              for a map and mode at the end of each game             |
|                            Author: Resxt                            |
======================================================================
|   Port of https://github.com/Resxt/Plutonium-T6-Scripts/mapvote/    |
======================================================================
*/

/*
maps\mp\gametypes\_hud_util (MP) and maps\_hud_util (ZM) both define the hud helpers
(createFontString, setPoint) under different paths,
and a single script cannot conditionally include per mode.
So the hud helpers are called through level function pointers
assigned by mp\mapvote_mp_extend.gsc and sp\mapvote_zm_extend.gsc (each includes its own version)
*/
#include common_scripts\utility;

/* Entry point */

Main()
{
    SetDvarIfNotInitialized("mapvote_enable", true);
}

Init()
{
    if (GetDvarInt("mapvote_enable"))
    {
        level.mapvote_rotate_function = ::StartRotation;

        InitMapvote();
    }
}

/* Init section */

InitMapvote()
{

    InitDvars();
    InitVariables();

    if (GetDvarInt("mapvote_debug"))
    {
        level thread DebugWaitThenStartVote();
    }

    // Starting the mapvote normally (non debug) is handled in mp\mapvote_mp_extend.gsc and sp\mapvote_zm_extend.gsc
}

/*
In debug mode the script initializes before any player is connected and before clients are done loading.
Client hud elements created too early never reach the client (one-shot create, no resend like server elements),
so we wait until a human is connected and fully spawned before showing anything
*/
DebugWaitThenStartVote()
{
    while (GetHumanPlayers().size == 0)
    {
        wait 1;
    }

    player = GetHumanPlayers()[0];

    // wait for the player to be spawned and their client to be ready
    player thread DebugPlayerSpawnWait();
    player waittill("mapvote_player_spawned");
    wait 2;

    level thread StartVote();
    level thread ListenForEndVote();
}

DebugPlayerSpawnWait()
{
    self endon("disconnect");

    if (IsMultiplayerMode())
    {
        if (!IsDefined(self.hasSpawned) || !self.hasSpawned)
        {
            // WaW notifies "spawned" in spawnPlayer (maps\mp\gametypes\_globallogic)
            self waittill("spawned");
        }
    }
    else
    {
        // the zombies (singleplayer tree) flow has no "spawned" notify, just wait for the client to be ready
        wait 5;
    }

    self notify("mapvote_player_spawned");
}

InitDvars()
{

    SetDvarIfNotInitialized("mapvote_debug", false);

    if (IsMultiplayerMode())
    {
        SetDvarIfNotInitialized("mapvote_maps", "Airfield:Asylum:Banzai:Battery:Breach:Castle:Cliffside:Corrosion:Courtyard:Dome:Downfall:Hangar:Knee Deep:Makin:Makin Day:Nightfire:Outskirts:Revolution:Roundhouse:Seelow:Station:Sub Pens:Upheaval");
        SetDvarIfNotInitialized("mapvote_modes", "Team Deathmatch,tdm:Free-for-All,dm:Domination,dom");
        SetDvarIfNotInitialized("mapvote_limits_maps", 0);
        SetDvarIfNotInitialized("mapvote_limits_modes", 0);
        SetDvarIfNotInitialized("mapvote_sounds_menu_enabled", 1);
        SetDvarIfNotInitialized("mapvote_sounds_timer_enabled", 1);
        SetDvarIfNotInitialized("mapvote_default_rotation_maps", "Airfield:Dome:Castle:Roundhouse:Seelow");
        SetDvarIfNotInitialized("mapvote_default_rotation_modes", "tdm");
    }
    else
    {
        SetDvarIfNotInitialized("mapvote_maps", "Nacht der Untoten,Nacht der Untoten,nazi_zombie_prototype:Verruckt,Verruckt,nazi_zombie_asylum:Shi No Numa,Shi No Numa,nazi_zombie_sumpf:Der Riese,Der Riese,nazi_zombie_factory");
        // custom map entries: "Displayed Name,ModFolderName,MapName"
        SetDvarIfNotInitialized("mapvote_custom_maps", "");
        SetDvarIfNotInitialized("mapvote_default_rotation_maps", "Der Riese,Der Riese,nazi_zombie_factory");
    }

    SetDvarIfNotInitialized("mapvote_limits_max", 12);
    SetDvarIfNotInitialized("mapvote_colors_selected", "blue");
    SetDvarIfNotInitialized("mapvote_colors_unselected", "white");
    SetDvarIfNotInitialized("mapvote_colors_timer", "blue");
    SetDvarIfNotInitialized("mapvote_colors_timer_low", "red");
    SetDvarIfNotInitialized("mapvote_colors_help_text", "white");
    SetDvarIfNotInitialized("mapvote_colors_help_accent", "cyan"); // the WaW chat color ^4 ("blue") renders much darker than the other mapvote blues, ^5 ("cyan") matches them
    SetDvarIfNotInitialized("mapvote_colors_help_accent_mode", "standard");
    SetDvarIfNotInitialized("mapvote_vote_time", 30);
    SetDvarIfNotInitialized("mapvote_blur_level", 2.5);
    SetDvarIfNotInitialized("mapvote_blur_fade_in_time", 2);
    SetDvarIfNotInitialized("mapvote_horizontal_spacing", 75);
    // the stock end-of-game win screen is visible for this duration before the mapvote replaces it (stock post-round window is 7 seconds)
    SetDvarIfNotInitialized("mapvote_display_wait_time", 7);
    SetDvarIfNotInitialized("mapvote_default_rotation_enable", false);
    SetDvarIfNotInitialized("mapvote_default_rotation_min_players", 0);
    SetDvarIfNotInitialized("mapvote_default_rotation_max_players", 0);

    /*
    In WaW the vote runs during the post-round window (see mp\mapvote_mp_extend.gsc),
    which lasts level.postRoundTime seconds (stock value is 7.0 in _globallogic::SetGlobalVariables).
    We raise it so the window covers the display wait + the vote, plus a small buffer.
    It is raised again right after game_ended in mp\mapvote_mp_extend.gsc
    in case the stock code initialises level.postRoundTime after ours runs
    */
    if (IsMultiplayerMode())
    {
        requiredPostRoundTime = (GetDvarInt("mapvote_display_wait_time") + GetDvarInt("mapvote_vote_time") + 10);

        if (!IsDefined(level.postRoundTime))
        {
            level.postRoundTime = 7.0;
        }

        level.postRoundTime = requiredPostRoundTime;

    }

}

InitVariables()
{

    mapsArray = StrTok(GetDvar("mapvote_maps"), ":");
    voteLimits = [];

    if (IsMultiplayerMode())
    {
        modesArray = StrTok(GetDvar("mapvote_modes"), ":");

        if (GetDvarInt("mapvote_limits_maps") == 0 && GetDvarInt("mapvote_limits_modes") == 0)
        {
            voteLimits = GetVoteLimits(mapsArray.size, modesArray.size);
        }
        else if (GetDvarInt("mapvote_limits_maps") > 0 && GetDvarInt("mapvote_limits_modes") == 0)
        {
            voteLimits = GetVoteLimits(GetDvarInt("mapvote_limits_maps"), modesArray.size);
        }
        else if (GetDvarInt("mapvote_limits_maps") == 0 && GetDvarInt("mapvote_limits_modes") > 0)
        {
            voteLimits = GetVoteLimits(mapsArray.size, GetDvarInt("mapvote_limits_modes"));
        }
        else
        {
            voteLimits = GetVoteLimits(GetDvarInt("mapvote_limits_maps"), GetDvarInt("mapvote_limits_modes"));
        }

        level.mapvote["limit"]["maps"] = voteLimits["maps"];
        level.mapvote["limit"]["modes"] = voteLimits["modes"];
    }
    else
    {
        poolAmount = mapsArray.size;

        // custom maps only work on dedicated servers, they are ignored on listen/solo games
        if (IsDedicated() && GetDvar("mapvote_custom_maps") != "")
        {
            customMapsArray = StrTok(GetDvar("mapvote_custom_maps"), ":");
            poolAmount = poolAmount + customMapsArray.size;
        }

        if (GetDvarInt("mapvote_limits_maps") == 0)
        {
            level.mapvote["limit"]["maps"] = GetVoteLimits(poolAmount);
        }
        else
        {
            level.mapvote["limit"]["maps"] = GetVoteLimits(GetDvarInt("mapvote_limits_maps"));
        }
    }

    SetMapvoteData("map");

    if (IsMultiplayerMode())
    {
        SetMapvoteData("mode");
    }

    level.mapvote["vote"]["maps"] = [];
    level.mapvote["vote"]["modes"] = [];

}

/* Player section */

/*
This is used instead of notifyonplayercommand("mapvote_up", "speed_throw")
to fix an issue where players using toggle ads would have to press right click twice for it to register one right click.
With this instead it keeps scrolling every 0.25s until they right click again which is a better user experience
*/
ListenForRightClick()
{
    self endon("disconnect");

    while (true)
    {
        if (self AdsButtonPressed())
        {
            self notify("mapvote_up");
            wait 0.25;
        }

        wait 0.05;
    }
}

ListenForVoteInputs()
{

    self endon("disconnect");

    self thread ListenForRightClick();

    self notifyonplayercommand("mapvote_down", "+attack");
    self notifyonplayercommand("mapvote_select", "+gostand");
    self notifyonplayercommand("mapvote_unselect", "+usereload");
    self notifyonplayercommand("mapvote_unselect", "+activate");

    while(true)
    {
        input = self waittill_any_return("mapvote_down", "mapvote_up", "mapvote_select", "mapvote_unselect");

        section = self.mapvote["vote_section"];

        if (section == "end" && input != "mapvote_unselect")
        {
            continue; // stop/skip execution
        }
        else if (IsMultiplayerMode() && section == "mode" && level.mapvote["modes"]["by_index"].size <= 1 && input != "mapvote_unselect")
        {
            continue; // stop/skip execution
        }
        else if (section == "mode" && level.mapvote["maps"]["by_index"].size <= 1 && input == "mapvote_unselect")
        {
            continue; // stop/skip execution
        }

        if (input == "mapvote_down")
        {
            if (self.mapvote[section]["hovered_index"] < (level.mapvote[section + "s"]["by_index"].size - 1))
            {
                if (GetDvarInt("mapvote_sounds_menu_enabled"))
                {
                    self playLocalSound("ui_mp_timer_countdown");
                }

                self UpdateSelection(section, (self.mapvote[section]["hovered_index"] + 1));
            }
        }
        else if (input == "mapvote_up")
        {
            if (self.mapvote[section]["hovered_index"] > 0)
            {
                if (GetDvarInt("mapvote_sounds_menu_enabled"))
                {
                    self playLocalSound("ui_mp_timer_countdown");
                }

                self UpdateSelection(section, (self.mapvote[section]["hovered_index"] - 1));
            }
        }
        else if (input == "mapvote_select")
        {
            if (GetDvarInt("mapvote_sounds_menu_enabled"))
            {
                self playLocalSound("mp_bomb_plant");
            }

            self ConfirmSelection(section);
        }
        else if (input == "mapvote_unselect")
        {
            if (section != "map")
            {
                if (GetDvarInt("mapvote_sounds_menu_enabled"))
                {
                    self playLocalSound("mp_bomb_defuse");
                }

                self CancelSelection(section);
            }
        }

        wait 0.05;
    }
}

OnPlayerDisconnect()
{
    self waittill("disconnect");

    if (self.mapvote["map"]["selected_index"] != -1)
    {
        level.mapvote["vote"]["maps"][self.mapvote["map"]["selected_index"]] = (level.mapvote["vote"]["maps"][self.mapvote["map"]["selected_index"]] - 1);
        UpdateVotesHudText("map", self.mapvote["map"]["selected_index"]);
    }

    if (self.mapvote["mode"]["selected_index"] != -1)
    {
        level.mapvote["vote"]["modes"][self.mapvote["mode"]["selected_index"]] = (level.mapvote["vote"]["modes"][self.mapvote["mode"]["selected_index"]] - 1);
        UpdateVotesHudText("mode", self.mapvote["mode"]["selected_index"]);
    }
}

/* Vote section */

CreateVoteMenu()
{
    // ZM only: hide the stock stats scoreboard (the client "lsm" state) while the vote is up.
    // The GAME OVER texts themselves are only removable through the per map hook scripts (see README)
    if (!IsMultiplayerMode())
    {
        [[level.mapvote_hide_stats_monitor]]();
    }

    spacing = 20;
    hudLastPosY = 0;

    if (IsMultiplayerMode())
    {
        sectionsSeparation = 0;

        if (level.mapvote["modes"]["by_index"].size > 1 && level.mapvote["maps"]["by_index"].size > 1)
        {
            sectionsSeparation = 1;
        }

        // WaW GSC does not support a unary minus before expressions so we use 0 - ... instead
        hudLastPosY = 0 - (((level.mapvote["maps"]["by_index"].size + level.mapvote["modes"]["by_index"].size + sectionsSeparation) * spacing / 2) - (spacing / 2));
    }
    else
    {
        hudLastPosY = 0 - (((level.mapvote["maps"]["by_index"].size * spacing) / 2) - (spacing / 2));
    }

    if (level.mapvote["maps"]["by_index"].size > 1)
    {
        for (mapIndex = 0; mapIndex < level.mapvote["maps"]["by_index"].size; mapIndex++)
        {

            /*
            WaW hud elements have a hardcoded limit of 16 per client
            so the vote counts are merged into the name text instead of using a separate element per count
            */
            mapName = "";

            if (IsMultiplayerMode())
            {
                mapName = level.mapvote["maps"]["by_index"][mapIndex];
            }
            else
            {
                mapName = level.mapvote["maps"]["by_index"][mapIndex][0];
            }

            for (playerIndex = 0; playerIndex < GetHumanPlayers().size; playerIndex++)
            {
                player = GetHumanPlayers()[playerIndex];

                player.mapvote["map"][mapIndex]["hud"] = player CreateHudText(mapName + " (0)", "objective", 1.5, "CENTER", "CENTER", 0, hudLastPosY);

                if (mapIndex == 0)
                {
                    player UpdateSelection("map", 0);
                }
                else
                {
                    SetElementUnselected(player.mapvote["map"][mapIndex]["hud"]);
                }
            }

            hudLastPosY += spacing;
        }
    }

    if (IsMultiplayerMode() && level.mapvote["modes"]["by_index"].size > 1)
    {
        hudLastPosY += spacing; // Space between maps and modes sections

        for (modeIndex = 0; modeIndex < level.mapvote["modes"]["by_index"].size; modeIndex++)
        {
            for (playerIndex = 0; playerIndex < GetHumanPlayers().size; playerIndex++)
            {
                player = GetHumanPlayers()[playerIndex];

                player.mapvote["mode"][modeIndex]["hud"] = player CreateHudText(level.mapvote["modes"]["by_index"][modeIndex] + " (0)", "objective", 1.5, "CENTER", "CENTER", 0, hudLastPosY);

                SetElementUnselected(player.mapvote["mode"][modeIndex]["hud"]);
            }

            hudLastPosY += spacing;
        }

        if (level.mapvote["maps"]["by_index"].size <= 1)
        {
            players = GetHumanPlayers();

            for (playerIndex = 0; playerIndex < players.size; playerIndex++)
            {
                players[playerIndex] UpdateSelection("mode", 0);
            }
        }
    }

    players = GetHumanPlayers();

    for (playerIndex = 0; playerIndex < players.size; playerIndex++)
    {
        player = players[playerIndex];

        player.mapvote["map"]["selected_index"] = -1;
        player.mapvote["mode"]["selected_index"] = -1;

        buttonsHelpMessage = "";
        buttonsHelpMessageSecondLine = "";

        /*
        The two lines below mix keyboard/mouse and controller inputs.
        Very long input names like "Left Mouse or RT" cannot be done through [{...}] tokens
        (the game renders them in an unpredictable order and with their own white color)
        so the inputs are written as plain text and colored with the accent color instead
        */
        if (GetDvar("mapvote_colors_help_accent_mode") == "standard")
        {
            buttonsHelpMessage = GetChatColor(GetDvar("mapvote_colors_help_text")) + "Press " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "Left Mouse " + GetChatColor(GetDvar("mapvote_colors_help_text")) + "or " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "RT " + GetChatColor(GetDvar("mapvote_colors_help_text")) + "to go down - Press " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "Right Click " + GetChatColor(GetDvar("mapvote_colors_help_text")) + "or " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "LT " + GetChatColor(GetDvar("mapvote_colors_help_text")) + "to go up";
            buttonsHelpMessageSecondLine = GetChatColor(GetDvar("mapvote_colors_help_text")) + "Press " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "Space " + GetChatColor(GetDvar("mapvote_colors_help_text")) + "or " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "A " + GetChatColor(GetDvar("mapvote_colors_help_text")) + "to select - Press " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "F " + GetChatColor(GetDvar("mapvote_colors_help_text")) + "or " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "X " + GetChatColor(GetDvar("mapvote_colors_help_text")) + "to undo";
        }
        else if(GetDvar("mapvote_colors_help_accent_mode") == "max")
        {
            buttonsHelpMessage = GetChatColor(GetDvar("mapvote_colors_help_text")) + "Press " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "Left Mouse " + GetChatColor(GetDvar("mapvote_colors_help_text")) + "or " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "RT " + GetChatColor(GetDvar("mapvote_colors_help_text")) + "to go " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "down " + GetChatColor(GetDvar("mapvote_colors_help_text")) + "- Press " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "Right Click " + GetChatColor(GetDvar("mapvote_colors_help_text")) + "or " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "LT " + GetChatColor(GetDvar("mapvote_colors_help_text")) + "to go " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "up";
            buttonsHelpMessageSecondLine = GetChatColor(GetDvar("mapvote_colors_help_text")) + "Press " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "Space " + GetChatColor(GetDvar("mapvote_colors_help_text")) + "or " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "A " + GetChatColor(GetDvar("mapvote_colors_help_text")) + "to " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "select " + GetChatColor(GetDvar("mapvote_colors_help_text")) + "- Press " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "F " + GetChatColor(GetDvar("mapvote_colors_help_text")) + "or " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "X " + GetChatColor(GetDvar("mapvote_colors_help_text")) + "to " + GetChatColor(GetDvar("mapvote_colors_help_accent")) + "undo";
        }

        // two help lines, adapt the Y positions if you change the font scale
        player CreateHudText(buttonsHelpMessage, "objective", 1.5, "CENTER", "CENTER", 0, 200);
        player CreateHudText(buttonsHelpMessageSecondLine, "objective", 1.5, "CENTER", "CENTER", 0, 220);
    }

}

CreateVoteTimer()
{

    soundFX = spawn("script_origin", (0,0,0));
    soundFX hide();

    /*
    In WaW the label property of hud elements only accepts localized (&"...") strings
    so a native timer cannot display our vote countdown text.
    We use one client text element per player, updated every second like the vote counts
    */
    players = GetHumanPlayers();

    for (playerIndex = 0; playerIndex < players.size; playerIndex++)
    {
        players[playerIndex].mapvote["timer_hud"] = players[playerIndex] CreateHudText("Vote ends in: " + GetDvarInt("mapvote_vote_time"), "objective", 1.5, "CENTER", "CENTER", 0, -210);
        players[playerIndex].mapvote["timer_hud"].color = GetGscColor(GetDvar("mapvote_colors_timer"));
    }

    for (i = GetDvarInt("mapvote_vote_time"); i > 0; i--)
    {
        if (i <= 5)
        {
            for (playerIndex = 0; playerIndex < players.size; playerIndex++)
            {
                players[playerIndex].mapvote["timer_hud"].color = GetGscColor(GetDvar("mapvote_colors_timer_low"));
            }

            if (GetDvarInt("mapvote_sounds_timer_enabled"))
            {
                soundFX playSound("ui_mp_timer_countdown");
            }
        }

        for (playerIndex = 0; playerIndex < players.size; playerIndex++)
        {
            players[playerIndex].mapvote["timer_hud"] SetText("Vote ends in: " + i);
        }

        wait(1);
    }

    level notify("mapvote_vote_end");
}

StartVote()
{

    level endon("game_ended");

    for (i = 0; i < level.mapvote["maps"]["by_index"].size; i++)
    {
        level.mapvote["vote"]["maps"][i] = 0;
    }

    if (IsMultiplayerMode())
    {
        for (i = 0; i < level.mapvote["modes"]["by_index"].size; i++)
        {
            level.mapvote["vote"]["modes"][i] = 0;
        }
    }

    level thread CreateVoteMenu();
    level thread CreateVoteTimer();

    for (playerIndex = 0; playerIndex < GetHumanPlayers().size; playerIndex++)
    {
        player = GetHumanPlayers()[playerIndex];

        player freezeControls(1);

        /*
        WaW has no SetBlur builtin in multiplayer and GSC compiles every branch,
        so the two modes blur players differently via an injected pointer
        (see the extend scripts)
        */
        player [[level.mapvote_set_blur]]();

        player thread ListenForVoteInputs();
        player thread OnPlayerDisconnect();
    }

}

ListenForEndVote()
{
    level endon("game_ended");
    level waittill("mapvote_vote_end");

    mostVotedMapIndex = 0;
    mostVotedMapVotes = 0;
    mostVotedModeIndex = 0;
    mostVotedModeVotes = 0;

    for (mapIndex = 0; mapIndex < level.mapvote["maps"]["by_index"].size; mapIndex++)
    {
        if (level.mapvote["vote"]["maps"][mapIndex] > mostVotedMapVotes)
        {
            mostVotedMapIndex = mapIndex;
            mostVotedMapVotes = level.mapvote["vote"]["maps"][mapIndex];
        }
    }

    /*
    ZM has no modes (each ZM entry carries its own cfg) and level.mapvote["modes"] is never seeded there:
    dereferencing it in ZM triggers the undefined-deref endless spin quirk, killing the thread
    */
    if (IsMultiplayerMode())
    {
        for (modeIndex = 0; modeIndex < level.mapvote["modes"]["by_index"].size; modeIndex++)
        {
            if (level.mapvote["vote"]["modes"][modeIndex] > mostVotedModeVotes)
            {
                mostVotedModeIndex = modeIndex;
                mostVotedModeVotes = level.mapvote["vote"]["modes"][modeIndex];
            }
        }
    }

    if (mostVotedMapVotes == 0)
    {
        mostVotedMapIndex = GetRandomElementInArray(GetArrayKeys(level.mapvote["vote"]["maps"]));

    }

    if (IsMultiplayerMode())
    {
        if (mostVotedModeVotes == 0)
        {
            mostVotedModeIndex = GetRandomElementInArray(GetArrayKeys(level.mapvote["vote"]["modes"]));

        }
    }

    modeName = "";
    modeCfg = "";
    mapName = "";
    mapMod = "";

    if (IsMultiplayerMode())
    {
        modeName = level.mapvote["modes"]["by_index"][mostVotedModeIndex];
        modeCfg = level.mapvote["modes"]["by_name"][level.mapvote["modes"]["by_index"][mostVotedModeIndex]];
        mapName = GetMapCodeName(level.mapvote["maps"]["by_index"][mostVotedMapIndex]);
    }
    else
    {
        selectedMapData = level.mapvote["maps"]["by_index"][mostVotedMapIndex];

        modeCfg = selectedMapData[3]; // zombies has no gametypes, this field is unused
        mapName = selectedMapData[1];
        mapMod = selectedMapData[2];
    }

    DoRotation(modeCfg, mapName, mapMod);

    /*
    The stock endGame's scr_intermission_time wait is already in progress (a dvar change cannot affect it)
    so without this the AAR/scoreboard screen would linger for the whole intermission after the vote.
    DoRotation already set the rotation to the voted result, so exitLevel just ends the level as stock would
    */
    if (IsDedicated())
    {

        wait 1;

        exitLevel( false );
    }
}

SetMapvoteData(type)
{
    limit = level.mapvote["limit"][type + "s"];

    availableElements = StrTok(GetDvar("mapvote_" + type + "s"), ":");

    /*
    Zombies maps: the pool combines the base maps (mapvote_maps) and, on dedicated servers only,
    the custom maps (mapvote_custom_maps). Custom maps are ignored on listen/solo games because
    Plutonium cannot load a mod while in-game.
    Each stored entry has 4 fields:
    [0] display name (what the menu shows)
    [1] map name used by the rotation command
    [2] mod folder name, empty for base maps
    [3] unused cfg field, kept for compatibility with the mapvote_maps format
    */
    if (!IsMultiplayerMode() && type == "map")
    {
        baseMaps = availableElements;

        customMaps = [];

        if (IsDedicated() && GetDvar("mapvote_custom_maps") != "")
        {
            customMaps = StrTok(GetDvar("mapvote_custom_maps"), ":");
        }

        poolAmount = baseMaps.size + customMaps.size;

        if (limit > poolAmount)
        {
            limit = poolAmount;
        }

        level.mapvote["maps"]["by_index"] = [];

        randomIndexes = GetRandomUniqueIndexes(limit, poolAmount);

        for (i = 0; i < randomIndexes.size; i++)
        {
            index = randomIndexes[i];

            if (index < baseMaps.size)
            {
                entry = GetZmBaseMapEntry(baseMaps[index]);
            }
            else
            {
                entry = GetZmCustomMapEntry(customMaps[index - baseMaps.size]);
            }

            if (IsDefined(entry))
            {
                level.mapvote["maps"]["by_index"] = AddElementToArray(level.mapvote["maps"]["by_index"], entry);
            }
        }

        return;
    }

    if (availableElements.size < limit)
    {
        limit = availableElements.size;
    }

    if (type == "map")
    {
        if (IsMultiplayerMode())
        {
            level.mapvote["maps"]["by_index"] = GetRandomUniqueElementsInArray(availableElements, limit);
        }
    }
    else if (type == "mode")
    {
        finalElements = [];

        randomElements = GetRandomUniqueElementsInArray(availableElements, limit);

        for (i = 0; i < randomElements.size; i++)
        {
            splittedMode = StrTok(randomElements[i], ",");
            finalElements = AddElementToArray(finalElements, splittedMode[0]);

            level.mapvote["modes"]["by_name"][splittedMode[0]] = splittedMode[1];
        }

        level.mapvote["modes"]["by_index"] = finalElements;
    }

}

/*
Parses a base zombies map entry from the mapvote_maps dvar: "Display Name,Display Name,unused"
The display name is resolved to the map code name with GetMapCodeName.
If it is not a known stock map name the raw value is used as the map name directly
*/
GetZmBaseMapEntry(data)
{
    dataSplitted = StrTok(data, ",");

    if (!IsDefined(dataSplitted) || dataSplitted.size < 3)
    {
        return undefined;
    }

    entry = [];

    // WaW has no "array()" builtin, we build the sub array manually
    entry[0] = dataSplitted[0];

    mapCode = GetMapCodeName(dataSplitted[1]);

    if (!IsDefined(mapCode))
    {
        mapCode = dataSplitted[1];
    }

    entry[1] = mapCode;
    entry[2] = ""; // base game map, no mod to load
    entry[3] = dataSplitted[2];

    return entry;
}

/*
Parses a custom zombies map entry from the mapvote_custom_maps dvar: "Displayed Name,ModName,MapName"
Only used on dedicated servers, which must be launched with the mod loaded (ModName is the mod's folder name)
*/
GetZmCustomMapEntry(data)
{
    dataSplitted = StrTok(data, ",");

    if (!IsDefined(dataSplitted) || dataSplitted.size < 3)
    {
        return undefined;
    }

    entry = [];

    entry[0] = dataSplitted[0];
    entry[1] = dataSplitted[2];
    entry[2] = dataSplitted[1];
    entry[3] = "";

    return entry;
}

/*
Returns "count" unique random indexes between 0 and poolSize - 1
Used instead of GetRandomUniqueElementsInArray over strings so that
the base/custom map pools can be told apart by their index range
*/
GetRandomUniqueIndexes(count, poolSize)
{
    indexes = [];

    while (indexes.size < count)
    {
        randomIndex = randomint(poolSize);

        if (!ArrayContainsValue(indexes, randomIndex))
        {
            indexes = AddElementToArray(indexes, randomIndex);
        }
    }

    return indexes;
}

/*
Gets the amount of maps and modes to display on screen
This is used to get default values if the limits dvars are not set
It will dynamically adjust the amount of maps and modes to show
*/
GetVoteLimits(mapsAmount, modesAmount)
{
    maxLimit = GetDvarInt("mapvote_limits_max");
    limits = [];

    if (!IsDefined(modesAmount))
    {
        if (mapsAmount <= maxLimit)
        {
            return mapsAmount;
        }
        else
        {
            return maxLimit;
        }
    }

    if ((mapsAmount + modesAmount) <= maxLimit)
    {
        limits["maps"] = mapsAmount;
        limits["modes"] = modesAmount;
    }
    else
    {
        if (mapsAmount >= (maxLimit / 2) && modesAmount >= (maxLimit))
        {
            limits["maps"] = (maxLimit / 2);
            limits["modes"] = (maxLimit / 2);
        }
        else
        {
            if (mapsAmount > (maxLimit / 2))
            {
                if (modesAmount <= 1)
                {
                    limits["maps"] = maxLimit;
                }
                else
                {
                    limits["maps"] = (maxLimit - modesAmount);
                }

                limits["modes"] = modesAmount;
            }
            else if (modesAmount > (maxLimit / 2))
            {
                limits["maps"] = mapsAmount;
                limits["modes"] = (maxLimit - mapsAmount);
            }
        }
    }

    return limits;
}

RotateDefault()
{
    mapName = "";
    modeCfg = "";

    if (IsMultiplayerMode())
    {
        modeCfg = GetRandomElementInArray(StrTok(GetDvar("mapvote_default_rotation_modes"), ":"));
        mapName = GetMapCodeName(GetRandomElementInArray(StrTok(GetDvar("mapvote_default_rotation_maps"), ":")));
    }
    else
    {
        entry = GetZmBaseMapEntry(GetRandomElementInArray(StrTok(GetDvar("mapvote_default_rotation_maps"), ":")));

        if (IsDefined(entry))
        {
            modeCfg = entry[3];
            mapName = entry[1];
        }
    }

    // the default rotation only supports base maps for now
    DoRotation(modeCfg, mapName, "");
}

/*
In WaW there is no per-gametype GTS cfg system like BO2's execgts.
modeCfg is simply the gametype dvar value (tdm, dom, dm, ctf, sd, koth, sab, twar)
mapMod is the mod folder name of a custom zombies map, or "" for base maps
*/
DoRotation(modeCfg, mapName, mapMod)
{

    if (IsMultiplayerMode())
    {
        if (IsDedicated())
        {
            SetDvar("sv_maprotationcurrent", "gametype " + modeCfg + " map " + mapName);
            SetDvar("sv_maprotation", "gametype " + modeCfg + " map " + mapName);
        }
        else
        {
            cmdexec("g_gametype " + modeCfg + "; map " + mapName);
        }
    }
    else
    {
        // zombies: there is no gametype to switch, only the map itself
        if (IsDedicated())
        {
            if (mapMod != "")
            {
                /*
                The mod must be loaded at server startup (fs_game pointing to it).
                Rotating to a custom map without it would leave the server with an unloadable map
                so we refuse and let the level end on an empty rotation (the engine falls back to map_restart)
                */
                fsGame = GetDvar("fs_game");

                if (!IsDefined(fsGame) || (fsGame != "mods/" + mapMod && fsGame != mapMod))
                {
                    Printf("[MAPVOTE] Cannot rotate to the custom map " + mapName + ": the server is not running the mod " + mapMod + " (it must be loaded at server startup). The current map will restart instead");

                    SetDvar("sv_maprotationcurrent", "");
                    SetDvar("sv_maprotation", "");

                    return;
                }
            }

            SetDvar("sv_maprotationcurrent", "map " + mapName);
            SetDvar("sv_maprotation", "map " + mapName);
        }
        else
        {
            /*
            Custom maps never reach this branch: mapvote_custom_maps is only read on dedicated servers
            because Plutonium cannot load a mod while in-game ("Cannot load a mod while in-game")
            */
            cmdexec("map " + mapName);
        }
    }
}

StartRotation()
{

    humanPlayersCount = GetHumanPlayers().size;

    if (GetDvarInt("mapvote_default_rotation_enable") && humanPlayersCount >= GetDvarInt("mapvote_default_rotation_min_players") && humanPlayersCount <= GetDvarInt("mapvote_default_rotation_max_players"))
    {
        RotateDefault();
    }
    else
    {
        StartVote();
        ListenForEndVote();
    }
}

/* HUD section */

UpdateSelection(type, index)
{
    if (type == "map" || type == "mode")
    {
        if (!IsDefined(self.mapvote[type]["hovered_index"]))
        {
            self.mapvote[type]["hovered_index"] = 0;
        }

        self.mapvote["vote_section"] = type;

        SetElementUnselected(self.mapvote[type][self.mapvote[type]["hovered_index"]]["hud"]); // Unselect previous element
        SetElementSelected(self.mapvote[type][index]["hud"]); // Select new element

        self.mapvote[type]["hovered_index"] = index; // Update the index

    }
    else if (type == "end")
    {
        self.mapvote["vote_section"] = "end";
    }
}

ConfirmSelection(type)
{

    self.mapvote[type]["selected_index"] = self.mapvote[type]["hovered_index"];
    level.mapvote["vote"][type + "s"][self.mapvote[type]["selected_index"]] = (level.mapvote["vote"][type + "s"][self.mapvote[type]["selected_index"]] + 1);
    UpdateVotesHudText(type, self.mapvote[type]["selected_index"]);

    if (type == "map")
    {
        // ZM has no mode section: confirming the map is the last step there
        if (IsMultiplayerMode())
        {
            modeIndex = 0;

            if (IsDefined(self.mapvote["mode"]["hovered_index"]))
            {
                modeIndex = self.mapvote["mode"]["hovered_index"];
            }

            self UpdateSelection("mode", modeIndex);
        }
        else
        {
            self UpdateSelection("end");
        }
    }
    else if (type == "mode")
    {
        self UpdateSelection("end");
    }
}

CancelSelection(type)
{

    typeToCancel = "";

    if (type == "mode")
    {
        typeToCancel = "map";
    }
    else if (type == "end")
    {
        // ZM has no mode section: from "end" the vote to cancel is the map itself
        if (IsMultiplayerMode())
        {
            typeToCancel = "mode";
        }
        else
        {
            typeToCancel = "map";
        }
    }

    level.mapvote["vote"][typeToCancel + "s"][self.mapvote[typeToCancel]["selected_index"]] = (level.mapvote["vote"][typeToCancel + "s"][self.mapvote[typeToCancel]["selected_index"]] - 1);
    UpdateVotesHudText(typeToCancel, self.mapvote[typeToCancel]["selected_index"]);

    self.mapvote[typeToCancel]["selected_index"] = -1;

    if (type == "mode")
    {
        SetElementUnselected(self.mapvote["mode"][self.mapvote["mode"]["hovered_index"]]["hud"]);
        self.mapvote["vote_section"] = "map";
    }
    else if (type == "end")
    {
        if (IsMultiplayerMode())
        {
            self.mapvote["vote_section"] = "mode";
        }
        else
        {
            // ZM has no mode section: go back to the map section and re-highlight the map
            self.mapvote["vote_section"] = "map";
            self UpdateSelection("map", self.mapvote["map"]["hovered_index"]);
        }
    }
}

SetElementSelected(element)
{
    element.color = GetGscColor(GetDvar("mapvote_colors_selected"));
}

SetElementUnselected(element)
{
    element.color = GetGscColor(GetDvar("mapvote_colors_unselected"));
}

/*
Because the vote counts are merged into the name elements (16 hud elements limit),
the text of every human player's element must be refreshed whenever the votes change
*/
UpdateVotesHudText(type, index)
{
    if (!IsDefined(level.mapvote["vote"][type + "s"][index]))
    {
        return;
    }

    entryName = "";

    if (IsMultiplayerMode())
    {
        entryName = level.mapvote[type + "s"]["by_index"][index];
    }
    else
    {
        entryName = level.mapvote["maps"]["by_index"][index][0];
    }

    players = GetHumanPlayers();

    for (i = 0; i < players.size; i++)
    {
        players[i].mapvote[type][index]["hud"] SetText(entryName + " (" + level.mapvote["vote"][type + "s"][index] + ")");
    }
}

CreateHudText(text, font, fontScale, relativeToX, relativeToY, relativeX, relativeY)
{
    hudText = self [[level.mapvote_create_font_string]](font, fontScale);

    // WaW/CoD4-era hud elems are created archived (they only render during killcam playback) so we disable it
    hudText.archived = false;

    hudText SetText(text);

    hudText [[level.mapvote_set_point]](relativeToX, relativeToY, relativeX, relativeY);

    // In WaW the end of game scoreboard is a real client menu so the mapvote must stay visible while a menu is open
    hudText.hideWhenInMenu = 0;
    hudText.glowAlpha = 0;

    return hudText;
}

/* Utils section */

SetDvarIfNotInitialized(dvar, value)
{
    if (!IsInitialized(dvar))
    {
        SetDvar(dvar, value);
    }
}

IsInitialized(dvar)
{
    result = GetDvar(dvar);
    return result != "";
}

IsDedicated()
{
    /*
    Pu T4 turned the vanilla dedicated int dvar into a string dvar holding
    "listen server", "dedicated LAN server" or "dedicated internet server"
    so GetDvarInt("dedicated") always returns 0 on every setup
    */
    dedicatedDvar = GetDvar("dedicated");

    if (!IsDefined(dedicatedDvar))
    {
        return false;
    }

    return IsSubStr(dedicatedDvar, "dedicated");
}

IsMultiplayerMode()
{
    return !IsDefined(level.zombiemode) || !level.zombiemode;
}

GetHumanPlayers()
{
    humanPlayers = [];

    /*
    WaW multiplayer and zombies use different player arrays (level.players vs the GetPlayers builtin),
    so the accessor is injected as a pointer by the extend scripts
    */

    players = [[level.mapvote_get_players]]();

    /*
    Reading .size of something that is not a clean array inside the loop condition
    triggers the endless spin quirk instead of failing cleanly,
    so anything reaching that loop must be verified first
    */
    if (!IsDefined(players))
    {
        return humanPlayers;
    }

    size = players.size;

    if (!IsDefined(size))
    {
        return humanPlayers;
    }

    for (i = 0; i < size; i++)
    {
        // IsBot is a WaW builtin, it returns true on bots added with the bot commands
        if (!IsDefined(players[i]))
        {
            continue;
        }

        if (!players[i] IsBot())
        {
            humanPlayers = AddElementToArray(humanPlayers, players[i]);
        }
    }

    return humanPlayers;
}

/*
MP players expose their name as .name.
In the SP/ZM trees .name is the AI character script_noteworthy and co-op players use .playername instead
*/
GetPlayerDisplayName(player)
{
    if (IsDefined(player.playername))
    {
        return player.playername;
    }

    if (IsDefined(player.name))
    {
        return player.name;
    }

    return "unknown";
}

GetRandomElementInArray(arr)
{
    return arr[GetArrayKeys(arr)[randomint(arr.size)]];
}

GetRandomUniqueElementsInArray(arr, limit)
{
    finalElements = [];

    for (i = 0; i < limit; i++)
    {
        findElement = true;

        while (findElement)
        {
            randomElement = GetRandomElementInArray(arr);

            if (!ArrayContainsValue(finalElements, randomElement))
            {
                finalElements = AddElementToArray(finalElements, randomElement);

                findElement = false;
            }
        }
    }

    return finalElements;
}

ArrayContainsValue(arr, valueToFind)
{
    if (arr.size == 0)
    {
        return false;
    }

    for (i = 0; i < arr.size; i++)
    {
        if (arr[i] == valueToFind)
        {
            return true;
        }
    }

    return false;
}

AddElementToArray(arr, element)
{
    arr[arr.size] = element;
    return arr;
}

/*
WaW GSC has no ToUpper and no case-insensitive string comparison,
so the map names below must be written exactly like they are in the mapvote_maps dvar
(default values above use the in-game names).
*/
GetMapCodeName(mapName)
{
    if (IsMultiplayerMode())
    {
        switch(mapName)
        {
            case "Airfield":
            return "mp_airfield";

            case "Asylum":
            return "mp_asylum";

            case "Banzai":
            return "mp_kwai";

            case "Battery":
            return "mp_drum";

            case "Breach":
            return "mp_bgate";

            case "Castle":
            return "mp_castle";

            case "Cliffside":
            return "mp_shrine";

            case "Corrosion":
            return "mp_stalingrad";

            case "Courtyard":
            return "mp_courtyard";

            case "Dome":
            return "mp_dome";

            case "Downfall":
            return "mp_downfall";

            case "Hangar":
            case "Hanger":
            return "mp_hangar";

            case "Knee Deep":
            return "mp_kneedeep";

            case "Makin":
            return "mp_makin";

            case "Makin Day":
            return "mp_makin_day";

            case "Nightfire":
            return "mp_nachtfeuer";

            case "Outskirts":
            return "mp_outskirts";

            case "Revolution":
            return "mp_vodka";

            case "Roundhouse":
            return "mp_roundhouse";

            case "Seelow":
            return "mp_seelow";

            case "Station":
            return "mp_subway";

            case "Sub Pens":
            return "mp_docks";

            case "Upheaval":
            return "mp_suburban";
        }
    }
    else
    {
        switch(mapName)
        {
            case "Nacht der Untoten":
            return "nazi_zombie_prototype";

            case "Verruckt":
            case "Verrückt":
            return "nazi_zombie_asylum";

            case "Shi No Numa":
            return "nazi_zombie_sumpf";

            case "Der Riese":
            return "nazi_zombie_factory";
        }
    }
}

GetGscColor(colorName)
{
    switch (colorName)
    {
        case "red":
        return (1, 0, 0.059);

        case "green":
        return (0.549, 0.882, 0.043);

        case "yellow":
        return (1, 0.725, 0);

        case "blue":
        return (0, 0.553, 0.973);

        case "cyan":
        return (0, 0.847, 0.922);

        case "purple":
        return (0.427, 0.263, 0.651);

        case "white":
        return (1, 1, 1);

        case "grey":
        case "gray":
        return (0.137, 0.137, 0.137);

        case "black":
        return (0, 0, 0);
    }
}

GetChatColor(colorName)
{
    switch(colorName)
    {
        case "red":
        return "^1";

        case "green":
        return "^2";

        case "yellow":
        return "^3";

        case "blue":
        return "^4";

        case "cyan":
        return "^5";

        case "purple":
        return "^6";

        case "white":
        return "^7";

        case "grey":
        return "^0";

        case "black":
        return "^0";
    }
}

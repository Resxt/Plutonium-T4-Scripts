/*
======================================================================
|                         Game: Plutonium T4                          |
|            Description : Starts the mapvote at the end              |
|                      of each zombies game                           |
|                            Author: Resxt                            |
======================================================================
*/

/*
The zombies game over is triggered by the map's own player_damage_override
(stock zombiemode registers it in level.overridePlayerDamage during map init,
which runs before custom init callbacks). That function, on the last hit of the
last player, calls maps\_zombiemode::end_game, which creates the GAME OVER and
"survived N rounds" hud elements and starts the intermission that pops the
end of game stats scoreboard.

Custom scripts cannot include or getFunction map scripts on Pu T4 (both fail),
but rebinding a level function pointer needs no reference at all: init() swaps
level.overridePlayerDamage for a wrapper that detects the same game ending
condition and runs the mapvote flow instead of end_game. The stock function
is delegated to in every other case.
*/

#include common_scripts\utility;
#include maps\_hud_util;
// the setMusicState call uses this common script function (maps\_laststand's functions are
// also used but that script defines init(), which would collide with this file's init(), so
// it is referenced through getFunction pointers instead, resolved in init())
#include maps\_utility;
#include maps\_music;

/*
Pu T4 calls main() on custom zombies/singleplayer scripts at game start,
then their init() later during the same level init
*/
main()
{
    if (GetDvarInt("mapvote_enable"))
    {
        // guard in case the loader calls this more than once
        if (IsDefined(level.mapvote_zm_extend_started))
        {
            return;
        }

        level.mapvote_zm_extend_started = true;

        /*
        mapvote.gsc compiles in both the MP and ZM script trees and cannot include
        maps\_hud_util (mode exclusive), so the mode specific builtins are injected as pointers
        */
        level.mapvote_create_font_string = ::MapvoteCreateFontString;
        level.mapvote_set_point = ::MapvoteSetPoint;
        level.mapvote_get_players = ::MapvoteGetPlayers;
        level.mapvote_set_blur = ::MapvoteSetBlur;
        level.mapvote_hide_stats_monitor = ::MapvoteHideStatsMonitor;
    }
}

init()
{
    if (!GetDvarInt("mapvote_enable"))
    {
        return;
    }

    /*
    maps\_laststand functions (common scripts resolve through getFunction, unlike map scripts);
    they are optional: if they never resolve the wrapper only loses the last stand
    detection part of the game over check
    */
    level.mapvote_last_stand = getFunction("maps/_laststand", "PlayerLastStand");
    level.mapvote_is_in_laststand = getFunction("maps/_laststand", "player_is_in_laststand");

    if (!IsDefined(level.overridePlayerDamage))
    {
        return;
    }

    level.mapvote_stock_zm_damage_override = level.overridePlayerDamage;
    level.overridePlayerDamage = ::MapvoteZmDamageOverride;

    /*
    Backup game end listener for cases where the wrapper cannot own the flow
    (unchanged stock end_game). Guards against double starting the vote with
    level.mapvote_zm_vote_started
    */
    level thread ListenForZmGameEnd();
}

MapvoteCreateFontString(font, fontScale)
{
    // the zombies version takes the player as optional third argument
    return createFontString(font, fontScale, self);
}

MapvoteSetPoint(point, relativePoint, xOffset, yOffset, moveTime)
{
    self setPoint(point, relativePoint, xOffset, yOffset, moveTime);
}

MapvoteSetBlur()
{
    // SetBlur(magnitude, transition time) is the zombies/singleplayer builtin
    self SetBlur(GetDvarFloat("mapvote_blur_level"), GetDvarFloat("mapvote_blur_fade_in_time"));
}

MapvoteGetPlayers()
{
    // GetPlayers is the zombies (singleplayer tree) builtin, equivalent of MP's level.players
    return GetPlayers();
}

/*
Hides the stock end of game stats scoreboard (Points/Kills/Headshots panel).
The scoreboard is a client only menu shown once the player sessionstate becomes
"intermission"; the mapvote flow never sets it, so this only matters when the
stock flow (fallback listener) handled the game over instead
*/
MapvoteHideStatsMonitor()
{
    players = GetPlayers();

    for (i = 0; i < players.size; i++)
    {
        setclientsysstate("lsm", "0", players[i]);
    }
}

/*
Wrapper now bound to level.overridePlayerDamage (see init()).
Replicates the game over detection of the stock player_damage_override
(the count of players that are down/dying), delegates everything else to the
saved stock function, and on the game ending hit replicates the stock tail
without end_game so the stock game over huds are never created
*/
MapvoteZmDamageOverride(eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, modelIndex, psOffsetTime)
{
    /*
    The stock override caps projectile damage at 75 and only applies it when the
    health is above 75, meaning such a hit can never be lethal (same branches as stock)
    */
    if ((sMeansOfDeath == "MOD_PROJECTILE" || sMeansOfDeath == "MOD_PROJECTILE_SPLASH" || sMeansOfDeath == "MOD_GRENADE" || sMeansOfDeath == "MOD_GRENADE_SPLASH") && self.health > 75)
    {
        [[level.mapvote_stock_zm_damage_override]](eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, modelIndex, psOffsetTime);
        return;
    }

    // non lethal damage, same check as stock
    if (iDamage < self.health)
    {
        [[level.mapvote_stock_zm_damage_override]](eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, modelIndex, psOffsetTime);
        return;
    }

    /*
    The game is already over: the stock override blocks forever in this state.
    If the stock end_game slipped (edge cases, see the wrapper remark) the
    fallback listener below owns the vote, this hit changes nothing
    */
    if (IsDefined(level.intermission) && level.intermission)
    {
        [[level.mapvote_stock_zm_damage_override]](eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, modelIndex, psOffsetTime);
        return;
    }

    // lethal damage: same count as the stock override, down or dying players
    players = GetPlayers();

    count = 0;

    for (i = 0; i < players.size; i++)
    {
        isPlayerDown = false;

        // maps\_laststand::player_is_in_laststand through its getFunction pointer (see init())
        if (IsDefined(level.mapvote_is_in_laststand))
        {
            isPlayerDown = players[i] [[level.mapvote_is_in_laststand]]();
        }

        if (players[i] == self
            || players[i].is_zombie
            || isPlayerDown
            || players[i].sessionstate == "spectator")
        {
            count++;
        }
    }

    if (count < players.size)
    {
        // the game goes on, fully stock behavior
        [[level.mapvote_stock_zm_damage_override]](eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, modelIndex, psOffsetTime);
        return;
    }

    // safety net, the fallback listener already owns the vote: stock path instead
    if (IsDefined(level.mapvote_zm_vote_started))
    {
        [[level.mapvote_stock_zm_damage_override]](eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, modelIndex, psOffsetTime);
        return;
    }

    /*
    This hit ends the game. Replicate the stock player_damage_override tail
    (self.intermission flag, last stand and fake death) without end_game and
    claim the vote flow. Set first so the 0.5s polling fallback never races it
    */
    level.mapvote_zm_vote_started = true;

    self.intermission = true;

    // same as stock, maps\_laststand::PlayerLastStand through its getFunction pointer (see init())
    if (IsDefined(level.mapvote_last_stand))
    {
        self thread [[level.mapvote_last_stand]](eInflictor, eAttacker, iDamage, sMeansOfDeath, sWeapon, vDir, sHitLoc, psOffsetTime);
    }

    // replica of the stock zombiemode player_fake_death (map script, not reachable)
    self TakeAllWeapons();
    self AllowStand(false);
    self AllowCrouch(false);
    self.ignoreme = true;
    self EnableInvulnerability();

    wait 1;
    self FreezeControls(true);

    /*
    Replica of the stock end_game from here, minus the GAME OVER and
    "survived N rounds" hud elements it creates, minus update_leaderboards
    (a function of the map's own _zombiemode, unreachable from custom scripts:
    in exchange the match is not reported to the leaderboards) and minus the
    stock intermission() call (it sets the players sessionstate to "intermission",
    which is what pops the end of game stats scoreboard, and the mapvote
    replaces that window entirely)
    */
    level.intermission = true;

    setMusicState("end_of_game");

    // in debug mode the vote is started by mapvote.gsc's DebugWaitThenStartVote instead
    if (GetDvarInt("mapvote_debug"))
    {
        return;
    }

    wait GetDvarInt("mapvote_display_wait_time");

    [[level.mapvote_rotate_function]]();

    /*
    Replica of the stock end_game tail. The stock waits zombie_intermission_time
    here, which the vote already spent. player_exit_level is a map script function,
    its body (posture reset, fading of the game_over_bg it would have created)
    is inlined, minus the game_over_bg part which the mapvote never creates
    */
    level notify("stop_intermission");

    players = GetPlayers();

    for (i = 0; i < players.size; i++)
    {
        players[i] AllowStand(true);
        players[i] AllowCrouch(false);
        players[i] AllowProne(false);
    }

    wait 1.5;

    ExitLevel(false);

    // like the stock end_game, keep this thread alive so its caller never resumes
    wait 666;
}

/*
Backup game end listener: polls level.intermission, which the stock end_game of
every stock map sets when the game over slipped through the damage wrapper.
Raises the intermission time (else the level would switch before the vote ends),
waits for the game over screen to be read, then starts the mapvote
*/
ListenForZmGameEnd()
{
    for (;;)
    {
        wait 0.5;

        if (IsDefined(level.intermission) && level.intermission)
        {
            break;
        }
    }

    // in debug mode the vote is started by mapvote.gsc's DebugWaitThenStartVote instead
    if (GetDvarInt("mapvote_debug"))
    {
        return;
    }

    // the damage wrapper owns the vote
    if (IsDefined(level.mapvote_zm_vote_started))
    {
        return;
    }

    level.mapvote_zm_vote_started = true;

    /*
    The stock end_game reads level.zombie_vars["zombie_intermission_time"] ~3 seconds
    after setting level.intermission (game over fades + its intermission() call),
    so raising it here wins the race against the stock window
    */
    requiredIntermissionTime = (GetDvarInt("mapvote_display_wait_time") + GetDvarInt("mapvote_vote_time") + 10);

    level.zombie_vars["zombie_intermission_time"] = requiredIntermissionTime;

    wait GetDvarInt("mapvote_display_wait_time");

    [[level.mapvote_rotate_function]]();

    // The stock flow then keeps going on its own: stop_intermission, player_exit_level, ExitLevel
}

/*
======================================================================
|                         Game: Plutonium T4                          |
|            Description : Starts the mapvote at the end              |
|                      of each multiplayer game                       |
|                            Author: Resxt                            |
======================================================================
*/

#include common_scripts\utility;
#include maps\mp\gametypes\_hud_util;
#include maps\mp\_utility;

Init()
{
    if (GetDvarInt("mapvote_enable"))
    {
        /*
        mapvote.gsc compiles in both the MP and ZM script trees and cannot include
        maps\mp\gametypes\_hud_util (MP only), so the hud helpers are injected as pointers
        */
        level.mapvote_create_font_string = ::MapvoteCreateFontString;
        level.mapvote_set_point = ::MapvoteSetPoint;
        level.mapvote_get_players = ::MapvoteGetPlayers;
        level.mapvote_set_blur = ::MapvoteSetBlur;

        level thread ListenForGameEnd();
    }
}

MapvoteCreateFontString(font, fontScale)
{
    return self createFontString(font, fontScale);
}

MapvoteSetPoint(point, relativePoint, xOffset, yOffset, moveTime)
{
    self setPoint(point, relativePoint, xOffset, yOffset, moveTime);
}

MapvoteGetPlayers()
{
    return level.players;
}

MapvoteSetBlur()
{
    /*
    WaW has no SetBlur builtin in multiplayer.
    The WaW equivalent of the end of game blur is a depth of field effect,
    these are the exact values the stock end-of-game roundEndDOF function uses
    (maps\mp\gametypes\_globallogic::roundEndDOF)
    */
    self setDepthOfField(0, 128, 512, 4000, 6, 1.8);
}

/*
In WaW endGame (maps\mp\gametypes\_globallogic) does:
- notify game_ended
- freeze players, depth of field blur, winner announcements (post-round window)
- roundEndWait( level.postRoundTime, true )
- level.intermission = true, spawn the AAR/scoreboard for every player
- wait scr_intermission_time, closeMenus, exitLevel (engine builtin, rotates the server)

Once intermission starts every hud element becomes hidden (both server and client ones)
which is why the mapvote is invisible if it runs there.
So the mapvote runs during the post-round window instead:
- level.postRoundTime is raised in mapvote.gsc (InitDvars) and again right here,
    right after game_ended, hoping to win the race against endGame's roundEndWait read
- this listener filters out halftime/round switches and then starts the vote
- DoRotation sets the rotation to the voted result and exits the level (dedicated),
    so the stock exitLevel would rotate to the voted map too anyway
*/
ListenForGameEnd()
{
    for (;;)
    {
        level waittill("game_ended");

        // in debug mode the vote is started by mapvote.gsc's DebugWaitThenStartVote instead
        if (GetDvarInt("mapvote_debug"))
        {
            continue;
        }

        // values are copied first because GSC1 crashes when concatenating undefined values into strings
        roundsplayedValue = 0;
        roundLimitValue = "undefined";
        scoreLimitValue = "undefined";
        forcedEndValue = "undefined";

        if (IsDefined(game["roundsplayed"]))
        {
            roundsplayedValue = game["roundsplayed"];
        }

        if (IsDefined(level.roundLimit))
        {
            roundLimitValue = level.roundLimit;
        }

        if (IsDefined(level.scoreLimit))
        {
            scoreLimitValue = level.scoreLimit;
        }

        if (IsDefined(level.forcedEnd))
        {
            forcedEndValue = level.forcedEnd;
        }

        /*
        Belt and braces: endGame reads level.postRoundTime when calling roundEndWait
        right before this notify resolves, so our InitDvars override might be clobbered.
        Setting it again here only helps if this thread resumes before endGame reaches roundEndWait
        */
        level.postRoundTime = (GetDvarInt("mapvote_display_wait_time") + GetDvarInt("mapvote_vote_time") + 10);

        if (IsFinalRoundEnd())
        {
            break;
        }

    }

    wait GetDvarInt("mapvote_display_wait_time");

    /*
    The stock win screen (victory/defeat, end reason, best players) is hud elements
    created by maps\mp\gametypes\_hud_message::teamOutcomeNotify / ::outcomeNotify.
    It only gets destroyed when the player receives the reset_outcome notify,
    which the stock flow sends when intermission starts (right before the scoreboard).
    The mapvote runs before intermission, so we send reset_outcome ourselves
    to remove the win screen and make room for the mapvote menu
    */
    for (i = 0; i < level.players.size; i++)
    {
        level.players[i] notify("reset_outcome");
    }

    [[level.mapvote_rotate_function]]();
}

/*
Replication of the endGame conditions deciding whether the game really ends
or whether it is only a halftime/round switch (which does not start the mapvote).
This copies maps\mp\gametypes\_globallogic::hitRoundLimit and ::hitScoreLimit
(endGame skips round switches when neither limit is hit)
*/
IsFinalRoundEnd()
{
    forcedEnd = IsDefined(level.forcedEnd) && level.forcedEnd;
    isRoundBased = false;

    roundsplayed = 0;
    if (IsDefined(game["roundsplayed"]))
    {
        roundsplayed = game["roundsplayed"];
    }

    roundLimit = 0;
    if (IsDefined(level.roundLimit))
    {
        roundLimit = level.roundLimit;
    }

    scoreLimit = 0;
    if (IsDefined(level.scoreLimit))
    {
        scoreLimit = level.scoreLimit;
    }

    scoreLimitIsPerRound = IsDefined(level.scoreLimitIsPerRound) && level.scoreLimitIsPerRound;
    teamBased = IsDefined(level.teamBased) && level.teamBased;

    // this replicates endGame's round-based block condition
    isRoundBased = (roundLimit > 1) || (roundLimit == 0 && scoreLimit != 1);

    if (forcedEnd || !isRoundBased)
    {
        return true;
    }

    // hitsRoundLimit (stock hitRoundLimit)
    hitRound = (roundLimit > 0 && roundsplayed >= roundLimit);

    // hitsScoreLimit (stock hitScoreLimit)
    hitScore = false;

    if (!scoreLimitIsPerRound && scoreLimit > 0)
    {
        if (teamBased)
        {
            hitScore = (game["teamScores"]["allies"] >= scoreLimit || game["teamScores"]["axis"] >= scoreLimit);
        }
        else
        {
            for (i = 0; i < level.players.size; i++)
            {
                player = level.players[i];

                if (IsDefined(player.score) && player.score >= scoreLimit)
                {
                    hitScore = true;
                }
            }
        }
    }

    return hitRound || hitScore;
}

BoolToString(value)
{
    if (value)
    {
        return "true";
    }

    return "false";
}

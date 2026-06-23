"""
Applet: FPS Games
Summary: Showcase of famous FPS games
Description: Shows various classic First Person Shooter games, like Duke Nukem 3D, Quake, Doom, Wolfenstein 3D, Unreal, Blake Stone: Aliens of Gold, and many more.
Author: PMK (@pmk)
"""

load("render.star", "render")
load("random.star", "random")
load("schema.star", "schema")
load("src/blakestone.webp", BLAKESTONE_ASSET = "file")
load("src/doom-2.webp", DOOM_2_ASSET = "file")
load("src/doom.webp", DOOM_ASSET = "file")
load("src/dukenukem3d.webp", DUKE_NUKEM_3D_ASSET = "file")
load("src/quake.webp", QUAKE_ASSET = "file")
load("src/wolfenstein3d.webp", WOLFENSTEIN_3D_ASSET = "file")

RANDOM_GAME = "RANDOM"
ROOT_DELAY_MS = 67
GAME_LIST = [
    schema.Option(display = "Blake Stone: Aliens of Gold", value = "blakestone"),
    schema.Option(display = "Doom", value = "doom"),
    schema.Option(display = "Duke Nukem 3D", value = "dukenukem3d"),
    schema.Option(display = "Quake", value = "quake"),
    schema.Option(display = "Wolfenstein 3D", value = "wolfenstein3d"),
]

def get_random_game():
    rand = random.number(0, len(GAME_LIST) - 1)
    return GAME_LIST[rand].value

def get_game_asset(game):
    if game == "blakestone":
        return BLAKESTONE_ASSET.readall()
    if game == "doom":
        if random.number(0, 1) == 0:
            return DOOM_ASSET.readall()
        return DOOM_2_ASSET.readall()
    if game == "doom-2":
        return DOOM_2_ASSET.readall()
    if game == "dukenukem3d":
        return DUKE_NUKEM_3D_ASSET.readall()
    if game == "quake":
        return QUAKE_ASSET.readall()
    if game == "wolfenstein3d":
        return WOLFENSTEIN_3D_ASSET.readall()
    fail("Unknown game: %s" % game)

def main(config):
    game = config.str("game", RANDOM_GAME)
    if game == RANDOM_GAME:
        game = get_random_game()

    return render.Root(
        delay = ROOT_DELAY_MS,
        child = render.Image(
            src = get_game_asset(game),
            width = 64,
            height = 32,
        ),
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Dropdown(
                id = "game",
                name = "Game",
                desc = "Show this selected FPS game.",
                default = RANDOM_GAME,
                options = [schema.Option(display = "RANDOM", value = RANDOM_GAME)] + GAME_LIST,
                icon = "gamepad",
            ),
        ],
    )

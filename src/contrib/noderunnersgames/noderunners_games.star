"""
Applet: Noderunners Games
Summary: Leaderboard and jackpot of games
Description: Shows the leaderboard and jackpot per game at Noderunners Games. The jackpot is the amount in sats.
Author: PMK (@pmk)
"""

load("http.star", "http")
load("logos/badger.png", BADGER_LOGO_ASSET = "file")
load("logos/bitcoinblitz.png", BITCOINBLITZ_LOGO_ASSET = "file")
load("logos/bubblebreaker.png", BUBBLEBREAKER_LOGO_ASSET = "file")
load("logos/chainduel.png", CHAINDUEL_LOGO_ASSET = "file")
load("logos/memory.png", MEMORY_LOGO_ASSET = "file")
load("logos/mempoolbreaker.png", MEMPOOLBREAKER_LOGO_ASSET = "file")
load("logos/pong.png", PONG_LOGO_ASSET = "file")
load("logos/roadrush.png", ROADRUSH_LOGO_ASSET = "file")
load("logos/spaceinvaders.png", SPACEINVADERS_LOGO_ASSET = "file")
load("random.star", "random")
load("render.star", "render")
load("schema.star", "schema")

API_GAMES = "https://lightning.druts.nl/api/games/overview?leaderboard_limit=9"
ROOT_DELAY_MS = 50
LEADERBOARD_HOLD_MS = 1500
LOGO_HOLD_MS = 3000
JACKPOT_HOLD_MS = 3000
TRANSITION_STEP_PX = 2
RETRO_STRIPE_COLORS = [
    "#ff004d",
    "#ffa300",
    "#ffec27",
    "#00e436",
]

GAME_LIST = [
    schema.Option(display = "Bitcoin Blitz", value = "bitcoinblitz"),
    schema.Option(display = "The Rabbit Hole", value = "spaceinvaders"),
    schema.Option(display = "Chain Duel", value = "chainduel"),
    schema.Option(display = "Noderunners Memory", value = "memory"),
    schema.Option(display = "Noderunners Eppo.ng", value = "pong"),
    schema.Option(display = "Noderunners Road Rush", value = "roadrush"),
    schema.Option(display = "Badger Arcade", value = "badger"),
    schema.Option(display = "Mempool Breaker", value = "mempoolbreaker"),
    schema.Option(display = "The Bubble Is Real", value = "bubblebreaker"),
]
DEFAULT_GAME = GAME_LIST[0].value

def do_request(ttl_seconds = 60 * 5):
    response = http.get(url = API_GAMES, ttl_seconds = ttl_seconds)
    if response.status_code != 200:
        fail("Request failed with status %d @ %s", response.status_code, API_GAMES)
    return response.json()

def get_game_stats(game = DEFAULT_GAME):
    result = do_request()
    games = result["games"]
    filtered = [item for item in games if item["slug"] == game][0]

    return {
        "game_slug": game,
        "game_title": filtered["name"],
        "enabled": filtered["enabled"],
        "jackpot_enabled": filtered["jackpot"]["enabled"],
        "jackpot_amount": filtered["jackpot"]["visible"],
        "leaderboard": filtered["leaderboard"],
    }

def get_random_game():
    rand = random.number(0, len(GAME_LIST) - 1)
    return GAME_LIST[rand].value

def get_logo(game = DEFAULT_GAME):
    if game == "bitcoinblitz":
        return BITCOINBLITZ_LOGO_ASSET.readall()
    if game == "spaceinvaders":
        return SPACEINVADERS_LOGO_ASSET.readall()
    if game == "chainduel":
        return CHAINDUEL_LOGO_ASSET.readall()
    if game == "memory":
        return MEMORY_LOGO_ASSET.readall()
    if game == "pong":
        return PONG_LOGO_ASSET.readall()
    if game == "roadrush":
        return ROADRUSH_LOGO_ASSET.readall()
    if game == "badger":
        return BADGER_LOGO_ASSET.readall()
    if game == "mempoolbreaker":
        return MEMPOOLBREAKER_LOGO_ASSET.readall()
    if game == "bubblebreaker":
        return BUBBLEBREAKER_LOGO_ASSET.readall()
    fail("Unknown game: %s" % game)

def render_logo(stats):
    return render.Image(
        src = get_logo(stats["game_slug"]),
        width = 64,
        height = 32,
    )

def render_leaderboard(stats):
    leaderboard_stats = stats["leaderboard"]
    if len(leaderboard_stats) == 0:
        return render.Text("")

    rows = [
        render.Padding(
            pad = (0, 1, 0, 1),
            child = render.Row(
                expanded = True,
                main_align = "start",
                children = [
                    render.Text(
                        content = str(int(row["rank"])),
                        font = "tom-thumb",
                        color = "#f2a900" if int(row["rank"]) == 1 else "#fff",
                    ),
                    render.Padding(
                        pad = (2, 0, 0, 0),
                        child = render.WrappedText(
                            align = "left",
                            color = "#f2a900" if int(row["rank"]) == 1 else "#fff",
                            content = row["player_name"],
                            font = "tom-thumb",
                            height = 6,
                            width = 32,
                        ),
                    ),
                    render.Padding(
                        pad = (3, 0, 0, 0),
                        child = render.WrappedText(
                            align = "right",
                            color = "#f2a900" if int(row["rank"]) == 1 else "#fff",
                            content = str(int(row["score"])),
                            font = "tom-thumb",
                            height = 6,
                            width = 24,
                        ),
                    ),
                ],
            ),
        )
        for row in leaderboard_stats
    ]
    leaderboard_body = render.Column(children = rows)
    static_leaderboard = render.Box(
        width = 64,
        height = 25,
        child = leaderboard_body,
    )
    scrolling_leaderboard = render.Marquee(
        width = 64,
        height = 25,
        scroll_direction = "vertical",
        child = leaderboard_body,
    )

    return render.Stack(
        children = [
            render_logo(stats),
            render.Box(
                width = 64,
                height = 32,
                color = "#000a",
            ),
            render.Column(
                cross_align = "start",
                children = [
                    render.Row(
                        main_align = "start",
                        expanded = True,
                        children = [
                            render.Text(
                                content = " ",
                                font = "tom-thumb",
                            ),
                            render.Padding(
                                pad = (2, 0, 0, 0),
                                child = render.WrappedText(
                                    align = "left",
                                    content = "PLAYER",
                                    font = "tom-thumb",
                                    height = 6,
                                    width = 32,
                                ),
                            ),
                            render.Padding(
                                pad = (3, 0, 0, 0),
                                child = render.WrappedText(
                                    align = "right",
                                    content = "SCORE",
                                    font = "tom-thumb",
                                    height = 6,
                                    width = 24,
                                ),
                            ),
                        ],
                    ),
                    render.Box(
                        color = "#a00",
                        width = 64,
                        height = 1,
                    ),
                    render.Sequence(
                        children = [
                            render.Animation(children = [static_leaderboard] * (LEADERBOARD_HOLD_MS // ROOT_DELAY_MS)),
                            scrolling_leaderboard,
                        ],
                    ),
                ],
            ),
        ],
    )

def render_jackpot(stats):
    jackpot_enabled = stats["jackpot_enabled"]
    if not jackpot_enabled:
        return render.Text("")

    jackpot_string = "JACKPOT: " + str(int(stats["jackpot_amount"])) + " sats"
    return render.Stack(
        children = [
            render.Box(width = 64, height = 32, color = "#000"),
            render.Column(
                expanded = True,
                main_align = "center",
                cross_align = "center",
                children = [
                    render.WrappedText(
                        content = jackpot_string,
                        font = "5x8",
                        color = "#f2a900",
                    ),
                ],
            ),
        ],
    )

def render_top_clip(target, height):
    if height <= 0:
        return render.Box(width = 64, height = 32)
    if height >= 32:
        return target
    return render.Box(width = 64, height = height, child = target)

def render_bottom_clip(target, start):
    if start <= 0:
        return target
    if start >= 32:
        return render.Box(width = 64, height = 32)
    return render.Padding(
        pad = (0, start, 0, 0),
        child = render.Box(
            width = 64,
            height = 32 - start,
            child = render.Padding(
                pad = (0, -start, 0, 0),
                child = target,
            ),
        ),
    )

def render_transition_line(y):
    return render.Padding(
        pad = (0, y, 0, 0),
        child = render.Column(
            children = [
                render.Box(width = 64, height = 1, color = color)
                for color in RETRO_STRIPE_COLORS
            ],
        ),
    )

def render_transition(from_screen, to_screen, reverse = False, dim_from = False):
    offsets = range(32, -5, -TRANSITION_STEP_PX) if reverse else range(-4, 33, TRANSITION_STEP_PX)
    return render.Animation(
        children = [
            render.Stack(
                children = [
                    from_screen,
                    render_top_clip(render.Box(width = 64, height = 32, color = "#000a"), y) if dim_from else render.Box(width = 64, height = 32),
                    render_bottom_clip(to_screen, y + 4),
                    render_transition_line(y),
                ] if reverse else [
                    from_screen,
                    render_bottom_clip(render.Box(width = 64, height = 32, color = "#000a"), y + 4) if dim_from else render.Box(width = 64, height = 32),
                    render_top_clip(to_screen, y),
                    render_transition_line(y),
                ],
            )
            for y in offsets
        ],
    )

def render_main(stats):
    logo_frame = render_logo(stats)
    leaderboard_frame = render_leaderboard(stats)
    jackpot_frame = render_jackpot(stats)

    return render.Sequence(
        children = [
            render.Animation(children = [logo_frame] * (LOGO_HOLD_MS // ROOT_DELAY_MS)),
            render_transition(logo_frame, leaderboard_frame, dim_from = True),
            leaderboard_frame,
            render_transition(leaderboard_frame, jackpot_frame, reverse = True),
            render.Animation(children = [jackpot_frame] * (JACKPOT_HOLD_MS // ROOT_DELAY_MS)),
        ],
    )

def main(config):
    game = config.str("game", DEFAULT_GAME)

    if game == "RANDOM":
        game = get_random_game()

    stats = get_game_stats(game)

    if not stats["enabled"]:
        return main(config)

    return render.Root(
        delay = ROOT_DELAY_MS,
        child = render_main(stats),
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Dropdown(
                id = "game",
                name = "Game",
                desc = "Show the stats of this selected game",
                default = DEFAULT_GAME,
                options = [schema.Option(display = "RANDOM GAME", value = "RANDOM")] + GAME_LIST,
                icon = "gamepad",
            ),
        ],
    )

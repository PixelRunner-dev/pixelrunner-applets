load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

COLOR = "#fff2"

def main(config):
    timezone = config.get("timezone") or "Europe/Amsterdam"
    now = time.now().in_location(timezone)

    clock24h = config.bool("clock24h")
    clock_format = "15:04" if clock24h else "3:04 PM"

    return render.Root(
        child = render.Box(
            child = render.Text(
                color = COLOR,
                content = now.format(clock_format),
                font = "6x13",
            ),
        ),
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Toggle(
                id = "clock24h",
                name = "Show as 24h clock",
                desc = "A toggle to display the clock as 24 hours.",
                icon = "clock",
                default = False,
            ),
        ],
    )

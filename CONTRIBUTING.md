# Contributing to Falak

Thanks for helping. Reports of wrong times and fixes of any size are welcome.

## Reporting

Use the issue forms: "A prayer time looks wrong" for times, "Something else is broken" for anything else. Give a city, not your address. I go through issues and pull requests most mornings.

## Fixing

You need Omarchy 4, `node` and `jq`.

    git clone https://github.com/adnanbwp/omarchy-falak
    cd omarchy-falak
    tests/run                      # the astronomy, every method, alerts and focus mode
    omarchy plugin validate .

Two scripts let you see the panel without restarting your bar:

    dev/render out.png '{"opts":{"method":"ISNA"}}'   # draw the panel to a PNG
    dev/check-panel                                  # drive it with real key presses

To try your branch in the bar, copy it over your install and restart the shell:

    rsync -a --exclude .git ./ ~/.config/omarchy/plugins/adnanbwp.falak/ && omarchy restart shell

## What a good pull request looks like

- One change, with a test that fails without it. `tests/model.test.mjs` is where the astronomy and the methods are checked.
- A prayer-time change comes with its reference: an official timetable, a mosque's published times or Aladhan's API, saved under `tests/fixtures/` with where and when you got it.
- Falak makes no network calls and keeps everything on the user's machine. I won't merge changes that break that.
- Keep the style of the file you're in. `Model.js` is plain JavaScript with no dependencies, so the tests can run it in Node.

## How changes reach people

`omarchy plugin update` pulls whatever is on `main`, so `main` has to work at all times. CI runs `omarchy plugin validate` and `tests/run` on every pull request, and I merge only when it's green.

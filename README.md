# [> Download](https://github.com/Zyke-Resources/zyke_dyno/releases/latest)

# Zyke's Dyno

A chassis dyno with an open formula. Drive a car onto the rollers, make a pull and watch the power and torque curves draw on the screen beside it. Free, and built for tuning and mechanic resources to read from and hook into.

- A pull you drive yourself in a fixed gear, with the rollers spinning up about as fast as the car would on the road.
- A live power and torque graph on the screen beside the dyno, over the car's last and first runs.
- A result sheet to print as an item at the dyno's screen, and history by plate.
- Dynos placed in game, from a config file or from another resource, with runs everyone sees in sync.
- A motorcycle dyno beside the car one: the front wheel stands in a chock and the rear wheel spins a drum.
- Exports, events and run checks for tuning and mechanic resources, and a Dyno app on [zyke_laptop](https://zykeresources.com/package/laptop).

## Installation

1. Install `zyke_lib` and `oxmysql`, and start this resource after them.
2. Add the `dyno_sheet` item and image from `extras/items` to your inventory.
3. Optional: set the Discord log URLs in `zyke_lib/webhooks/dyno.lua`.
4. Run `/dynos` in game to place your dynos.

Setup, usage, configuration, exports and events are covered in the [documentation](https://docs.zykeresources.com/free-resources/dyno).

## Pairs well with

[zyke_realisticvehicles](https://zykeresources.com/package/realistic-vehicles) takes power off a damaged engine, and the dyno shows it: put a worn car on the rollers, repair it and run it again for the gain.

## License

Free to use and modify on your own server, including servers that make money. See [LICENSE](LICENSE) for the full terms.

- **Open releases:** a project whose full source anyone can download for free from a public host such as GitHub, with no store checkout or free basket, may include this resource. Credit Zyke Resources, link to this repository and keep the license file with it.
- **Closed releases:** paid releases and free releases that are escrowed or otherwise locked may not ship any of it. Use it through its exports and tell your users to download it from here.
- **Videos and showcases:** anyone may show it, as long as Zyke Resources is named as the source.
- Selling it on its own, or claiming it as your own, is not allowed.

## Links

- [Documentation](https://docs.zykeresources.com/free-resources/dyno)
- [Discord Community](https://discord.zykeresources.com)
- [Store](https://zykeresources.com/)

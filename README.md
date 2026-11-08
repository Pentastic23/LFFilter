# LFFilter

A World of Warcraft: **Forever** addon that adds class and role filters to the Group Finder's **Browse** tab.

Already have a group and need a healer? Tick Healer, and the Browse list only shows players who listed as a healer. Use Blizzard's normal **Invite** and **Send Message** buttons on whoever is left.

## Features

- Filter by **role**: Tank, Healer or DPS (based on the roles players picked when they listed themselves).
- Filter by **class**: all nine classes, with class icons.
- **Solo players only**: hides groups so you only see people you can invite.
- **Shift-click** a role or class to pick only that one.
- Filters work on Blizzard's own list, with no separate window to manage.
- Shows how many listings match ("Showing 8 of 42").
- The panel docks next to the Group Finder, can be dragged anywhere, and collapses to a small **Filters** button.
- Your filters and panel position are saved between sessions.

## Install

1. Download `LFFilter.zip` from the [Releases](../../releases/latest) page.
2. Unzip it into your Forever addons folder, so you end up with:
   ```
   World of Warcraft\_forever_\Interface\AddOns\LFFilter\LFFilter.toc
   ```
3. Restart the game (or `/reload`) and make sure **LFFilter** is enabled on the AddOns screen.

> If you use GitHub's green **Code → Download ZIP** button instead, the folder will be named `LFFilter-main`. Rename it to `LFFilter` or WoW won't load it.

## Usage

Open the Group Finder and go to the **Browse** tab. The filter panel appears on the right side.

| Command      | What it does                         |
|--------------|--------------------------------------|
| `/lff`       | Show or hide the filter panel        |
| `/lff reset` | Move the panel back to its default spot |

## Notes

- Blizzard doesn't let addons run searches, so you still click **Search** yourself. The filters apply to the results as soon as they arrive.
- Your own listing is never hidden.

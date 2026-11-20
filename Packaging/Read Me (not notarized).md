# Lookdown

Lookdown makes Finder's Quick Look show Markdown files (.md) as formatted documents, with headings, tables, colored code, callouts and math, instead of plain text.

It needs macOS 14 (Sonoma) or later, on Apple silicon or Intel.

## Install

1. Drag **Lookdown** onto the **Applications** folder in this window.
2. Open Lookdown from your Applications folder.
3. macOS says it can't verify the app, because it isn't from the App Store or a registered developer. Close that message. Don't move the app to the Trash.
4. Open **System Settings → Privacy & Security**, scroll down to **Security**, and click **Open Anyway** next to the message about Lookdown. Confirm with your password or Touch ID.
5. Lookdown opens, and its window should say **Quick Look extension is on**. You can close it.

Now select any .md file in Finder and press Space. Try it on this file.

## Settings

Open Lookdown any time to choose a theme (Warm, Clean or GitHub), light or dark, text size, page width and a few Markdown options. Changes apply to the next preview.

## If previews still show plain text

- Make sure Lookdown is switched on under **System Settings → General → Login Items & Extensions → Quick Look**. On macOS 14 it's under **Privacy & Security → Extensions → Quick Look**.
- If **Open Anyway** didn't appear, you can clear the download warning in Terminal instead, then open Lookdown once:

      xattr -dr com.apple.quarantine /Applications/Lookdown.app

- To reset Quick Look, run `qlmanage -r` in Terminal.

## Uninstall

Drag Lookdown from Applications to the Trash.

## License

Lookdown is free software under the GNU General Public License, version 3 or later. The source code is at https://github.com/rgbwavesdev/Lookdown.

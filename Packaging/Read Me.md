# Lookdown

Lookdown makes Finder's Quick Look show Markdown files (.md) as formatted documents, with headings, tables, colored code, callouts and math, instead of plain text.

It needs macOS 14 (Sonoma) or later, on Apple silicon or Intel.

## Install

1. Drag **Lookdown** onto the **Applications** folder in this window.
2. Open Lookdown from your Applications folder. macOS asks whether you want to open an app downloaded from the internet: click **Open**.
3. Lookdown's window should say **Quick Look extension is on**. You can close it.

Now select any .md file in Finder and press Space. Try it on this file.

## Settings

Open Lookdown any time to choose a theme (Warm, Clean or GitHub), light or dark, text size, page width and a few Markdown options. Changes apply to the next preview.

## If previews still show plain text

- Make sure Lookdown is switched on under **System Settings → General → Login Items & Extensions → Quick Look**. On macOS 14 it's under **Privacy & Security → Extensions → Quick Look**.
- To reset Quick Look, run `qlmanage -r` in Terminal.

## Uninstall

Drag Lookdown from Applications to the Trash.

## License

Lookdown is free software under the GNU General Public License, version 3 or later. The source code is at https://github.com/rgbwavesdev/Lookdown.

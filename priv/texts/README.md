# Bundled texts

Both files are public domain and were produced by `scripts/fetch_texts.exs`
(see its header for the shape). Each holds one JSON object keyed by cantica,
then by canto number as a string, with the canto's lines in order.

| File | Text | Origin |
| --- | --- | --- |
| `petrocchi.json` | *La Commedia secondo l'antica vulgata*, Giorgio Petrocchi's text, Italian | it.wikisource.org via github.com/gio-derosa/divine-comedy |
| `longfellow.json` | Henry Wadsworth Longfellow's English translation (1867) | Project Gutenberg #1004 via github.com/gio-derosa/divine-comedy |

Line counts: Inferno 4,720 (34 cantos), Purgatorio 4,755 (33), Paradiso
4,758 (33); 14,233 lines in each file, aligned line for line.

Allen Mandelbaum's translation is in copyright and is **not** bundled. A
later `mix dante.import` task will fetch it into the user's data folder for
personal use.

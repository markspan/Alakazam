# Data

`Data/` (gitignored, not tracked in the repo) holds example and working
datasets for Alakazam.

## Luck example data

`downloadLuckData.m` (repo root) downloads and extracts the Luck-textbook
example data into `Data/Luck`. It needs no Google account, API key, or
Google Cloud project — see the function's own header comment
(`help downloadLuckData`) for how it works and how to re-share the data if
the source files ever move.

## Location

Alakazam's `.wksp` workspace files assume this data lives at a fixed path:
`~/Documents/GitHub/Alakazam/Data`. Keep datasets under this folder (not a
copy elsewhere) so saved workspaces resolve correctly.

`.wksp` files are plain JSON (`RawDirectory`, `CacheDirectory`,
`ExportsDirectory`, ...), so if you need a different layout you can either
open one in a normal text editor and change the paths by hand, or load it
into Alakazam, change the directories there, and save it again.

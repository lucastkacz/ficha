# A website for sharing cards

Cards are shared as files, in the format the app imports (#86): whoever has such a file passes it on however they like, such as in a message, by AirDrop or in a shared folder, and each person imports it into their own Ficha. Ficha keeps no website where people upload their cards for others to import, like Anki's shared decks.

## Why this is out of scope

Ficha has no server or accounts of its own (ADR 0001, `CLAUDE.md`): a person's cards live on their own devices, and syncing them goes through their own iCloud (#161). A website of shared cards would be a server of Ficha's own, for something files do without one.

## Prior requests

- #153: "Share cards with other people through a website, like Anki's shared decks"

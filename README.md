*[Leer en español](README.es.md)*

# ♟ Chess for WoW — WotLK 3.3.5a addon

Play a full game of chess inside World of Warcraft, against the AI or against another real player on the same realm.

**Version:** 5.0 · **Author:** Nidhaus

---

## 📦 Installation

1. Copy the whole `Chess` folder into:
   ```
   World of Warcraft/Interface/AddOns/Chess/
   ```
2. Enable the addon on the character selection screen.

---

## 🎮 Commands

| Command | Description |
|---|---|
| `/chess` or `/ajedrez` | Open or close the board |
| `/chess accept` | Accept an incoming challenge |
| `/chess decline` | Decline a challenge |
| `/chess resign` | Resign the current game |
| `/chess help` | Show help |

---

## 🕹 How to play

### Against the AI

1. Open the board with `/chess`.
2. Press **"New (White) vs AI"** or **"New (Black) vs AI"**.
3. Click one of your pieces to select it — it highlights in green.
4. Legal moves appear in blue (empty square) or red (capture).
5. Click the destination square to move.

### Against another player

1. Target the other player (`/target PlayerName`).
2. Open the board and press **"Challenge target"**.
3. They get a notification in chat.
4. They type `/chess accept`.
5. Whoever challenged plays **White**, whoever accepted plays **Black**.
6. Moves sync automatically between both clients.

---

## ♟ Piece letters

The board uses Spanish piece abbreviations:

| Letter | Piece |
|---|---|
| R | Rey — King |
| D | Dama — Queen |
| T | Torre — Rook |
| A | Alfil — Bishop |
| C | Caballo — Knight |
| P | Peón — Pawn |

- **Gold** = White pieces
- **Red** = Black pieces

---

## 🟩 Board colours

| Colour | Meaning |
|---|---|
| 🟩 Green | Selected piece |
| 🟦 Blue | Legal move available |
| 🟥 Red | Capture available / king in check |
| 🟨 Yellow | Last move played |

---

## ⚙️ Features

- ✅ Complete chess ruleset
- ✅ Castling, kingside and queenside
- ✅ En passant
- ✅ Automatic promotion to queen
- ✅ Check and checkmate detection
- ✅ Stalemate detection
- ✅ AI with a greedy strategy plus randomised variety
- ✅ Multiplayer over addon messages (same realm)
- ✅ Board movable by left-click dragging
- ✅ English and Spanish locales included

---

## 🐛 Notes

- Both players need the addon installed and enabled for multiplayer.
- Addon messages use the WHISPER channel — nothing is spammed to public chat.
- Compatible with WotLK 3.3.5a realms.

## Compatibility

Interface 30300 — WotLK 3.3.5a. Tested on Warmane.

## License

Free to use. If you redistribute it or build on it, keep the credit to the author.

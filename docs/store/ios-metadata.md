# App Store Submission Kit — Age of Amazon

Everything App Store Connect asks for, ready to paste. Screenshots live in
`docs/store/screenshots/` (iPhone 6.7" 2796×1290, iPad 12.9" 2732×2048).

## App information

| Field | Value |
|---|---|
| Name | Age of Amazon |
| Subtitle (30 ch) | Rainforest real-time strategy |
| Bundle ID | com.iagocavalcante.ageofamazon |
| SKU | age-of-amazon-ios |
| Primary category | Games → Strategy |
| Secondary category | Games → Simulation |
| Age rating answers | Cartoon/fantasy violence: **Infrequent/Mild** — everything else **No/None**. Result: 9+ |
| Price | Free |

## Description (EN)

Command your tribe deep in an endless procedural rainforest. Gather food,
wood and jade, raise villages, train warriors and archers, and outplay
rival tribes — human or AI.

- CLASSIC RTS, POCKET SIZE — build, scout, raid, and win by razing the
  enemy Town Center or standing a sacred Monument for 90 seconds.
- AN ENDLESS AMAZON — every match generates a new rainforest: rivers,
  fish schools, fruit trees, capybaras, jaguars, and hidden jade.
- PLAY WITH FRIENDS — create a room, share a code, and battle up to 4
  players online with ranked Elo and a public leaderboard.
- DAILY CHALLENGE — one shared map per day; race the world's best time.
- FOG OF WAR — the AI scouts under the same fog rules you do. No cheating
  opponents.

No ads. No purchases. No account — pick a name and play.

## Descrição (PT-BR)

Comande sua tribo nas profundezas de uma floresta amazônica infinita.
Colete comida, madeira e jade, erga vilas, treine guerreiros e arqueiros
e vença tribos rivais — humanas ou IA.

- RTS CLÁSSICO NO BOLSO — construa, explore, ataque e vença destruindo o
  Centro da Tribo inimigo ou erguendo um Monumento sagrado por 90 segundos.
- AMAZÔNIA SEM FIM — cada partida gera uma nova floresta: rios, cardumes,
  árvores frutíferas, capivaras, onças e jade escondido.
- JOGUE COM AMIGOS — crie uma sala, compartilhe o código e batalhe com
  até 4 jogadores online, com ranking Elo e placar público.
- DESAFIO DIÁRIO — um mapa compartilhado por dia; dispute o melhor tempo.
- NÉVOA DE GUERRA — a IA explora sob as mesmas regras de névoa que você.
  Nada de oponente trapaceiro.

Sem anúncios. Sem compras. Sem cadastro — escolha um nome e jogue.

## Keywords (100 ch)

`rts,strategy,amazon,rainforest,tribe,multiplayer,pixel art,age,empire,war,estratégia,tribo`

## URLs

- Support URL: https://github.com/iagocavalcante/age-of-amazon/issues
- Marketing URL: https://aoa.iagocavalcante.com

## App Privacy questionnaire

- **Data collection: "Data Not Collected" does NOT apply** — the optional
  multiplayer name counts as "Other User Content".
  - Collected: **User Content → Other User Content** (self-chosen player
    name). Linked to user: **No** (no account, no email, no device ID).
    Used for tracking: **No**. Purpose: **App Functionality**.
- No third-party SDKs, no analytics, no ads, no tracking.
- Privacy policy URL (required): host `docs/store/privacy-policy.md`
  contents anywhere public, e.g. the GitHub repo's raw URL.

## App Review notes (paste into "Notes")

Multiplayer test instructions: open Play with Friends, keep the default
generated name, press Create a Room — a second device/simulator can join
with the 4-letter code. The game server is operated by us at
game.iagocavalcante.com (WebSocket). Single player and the Daily Challenge
work fully offline after load. No login exists; the "name" is a
self-chosen public alias with no personal data attached.

## Build & upload (the human 10 minutes)

1. `bash tools/deploy_ios.sh` (already run — project is in `build/ios/`)
2. `open build/ios/AgeOfAmazon.xcodeproj` → select your team
   (NR8DLKJ7E6 pre-filled) → Product → Archive
3. Organizer → Distribute App → App Store Connect → Upload
4. appstoreconnect.apple.com → create the app record with the fields
   above, attach the build, paste metadata + screenshots → Submit.

Known review risk: first Godot submissions sometimes get a metadata ask
about the multiplayer server; the note above answers it preemptively.

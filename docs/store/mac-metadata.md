# Mac App Store Submission Kit — Age of Amazon

Everything App Store Connect asks for, ready to paste. Screenshots live in
`docs/store/screenshots/` (2880×1800, the Mac requirement). The game ships
**macOS only** — an RTS built for mouse edge-scrolling and hotkeys.

## App information

| Field | Value |
|---|---|
| Name | Age of Amazon |
| Subtitle (30 ch) | Rainforest real-time strategy |
| Bundle ID | com.iagocavalcante.ageofamazon |
| SKU | age-of-amazon-mac |
| Platform | **macOS only** |
| Primary category | Games → Strategy |
| Secondary category | Games → Simulation |
| Age rating answers | Cartoon/fantasy violence: **Infrequent/Mild** — everything else **No/None**. Result: 9+ |
| Price | Free |

## Description (EN)

Command your tribe deep in an endless procedural rainforest. Gather food,
wood and jade, raise villages, train warriors and archers, and outplay
rival tribes — human or AI.

- CLASSIC RTS — edge-scroll, box-select, hotkeys, build orders. Win by
  razing the enemy Town Center or standing a sacred Monument for 90 seconds.
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

- RTS CLÁSSICO — rolagem de tela, seleção em caixa, atalhos de teclado.
  Vença destruindo o Centro da Tribo inimigo ou erguendo um Monumento
  sagrado por 90 segundos.
- AMAZÔNIA SEM FIM — cada partida gera uma nova floresta: rios, cardumes,
  árvores frutíferas, capivaras, onças e jade escondido.
- JOGUE COM AMIGOS — crie uma sala, compartilhe o código e batalhe com
  até 4 jogadores online, com ranking Elo e placar público.
- DESAFIO DIÁRIO — um mapa compartilhado por dia; dispute o melhor tempo.
- NÉVOA DE GUERRA — a IA explora sob as mesmas regras de névoa que você.

Sem anúncios. Sem compras. Sem cadastro — escolha um nome e jogue.

## Keywords (100 ch)

`rts,strategy,amazon,rainforest,tribe,multiplayer,pixel art,age,empire,war,estratégia,tribo`

## URLs

- Support URL: https://github.com/iagocavalcante/age-of-amazon/issues
- Marketing URL: https://aoa.iagocavalcante.com
- Privacy policy URL: raw GitHub link to `docs/store/privacy-policy.md`

## App Privacy questionnaire

- Collected: **User Content → Other User Content** (self-chosen player
  name). Linked to user: **No**. Tracking: **No**. Purpose: **App
  Functionality**. Everything else: not collected.
- No third-party SDKs, no analytics, no ads.

## App Review notes (paste into "Notes")

Multiplayer test instructions: open Play with Friends, keep the default
generated name, press Create a Room — a second Mac can join with the
4-letter code. The game server is operated by us at
game.iagocavalcante.com (WebSocket over TLS; the app is sandboxed with
the network-client entitlement only). Single player and the Daily
Challenge work fully offline after launch. No login exists; the "name"
is a self-chosen public alias with no personal data attached.

## Build & upload (the human 10 minutes)

The `macOS App Store` export preset is fully configured: App Store
distribution, App Sandbox with network-client, team NR8DLKJ7E6, signing
identity names pre-filled.

1. One-time, in Xcode → Settings → Accounts → Manage Certificates:
   create **Apple Distribution** and **Mac Installer Distribution**
   certificates if they don't exist yet (the preset's identity strings
   must match the certificate names — adjust if Xcode names them
   "Apple Distribution: …" instead of "3rd Party Mac Developer …").
2. `bash tools/deploy_mas.sh` → produces signed `build/mas/AgeOfAmazon.pkg`.
3. Upload: `xcrun altool --upload-app -f build/mas/AgeOfAmazon.pkg -t macos`
   (or drag the pkg into the Transporter app) — signs in with YOUR
   Apple ID / app-specific password.
4. appstoreconnect.apple.com → create the macOS app record with the
   fields above, attach the build, paste metadata + screenshots →
   Submit for Review.

Known review risk: sandboxed Godot games occasionally get asked about
the WebSocket server; the review note answers it preemptively.

# Twilio Voice — Flutter wrapper demo (outbound calls)

A minimal but real example of wrapping the native Twilio Voice SDKs in Flutter and
placing **outbound** calls. Doubles as the app-size probe (see
`designs/nubank-flutter/twilio-voice-flutter-sdk-size.md`).

## Layout

```
packages/twilio_voice/     # the sample wrapper (Flutter plugin)
  lib/twilio_voice.dart     #   Dart API: connect/disconnect/mute/speaker/sendDigits + event stream
  android/...TwilioVoicePlugin.kt      #   Kotlin: com.twilio:voice-android
  ios/Classes/TwilioVoicePlugin.swift  #   Swift: TwilioVoice xcframework
lib/main.dart              # demo dialer UI (calls the token server, then the wrapper)
server/                    # TypeScript token server: Access Token + TwiML <Dial>
```

The wrapper is **outbound-only**, but the native call delegates and the
`incomingAllow` grant are already in place so an inbound (push + CallKit /
ConnectionService) phase can be added without changing the Dart API.

## How a call flows

1. App calls `GET /token` → server mints a Twilio **Access Token** (Voice grant → TwiML App).
2. App calls `TwilioVoice.connect(accessToken, to)` → native SDK connects to Twilio.
3. Twilio invokes the TwiML App's Voice URL → `POST /voice` returns `<Dial><Number>To</Number></Dial>`.
4. Twilio bridges to the PSTN number using `TWILIO_CALLER_ID`. Two-way audio over WebRTC.

## Run it

### 1. Token server
```bash
cd server
cp .env.example .env     # fill in the 5 Twilio values
npm install
npm run dev              # http://localhost:3000
```
Expose `POST /voice` publicly (e.g. `ngrok http 3000`) and set that URL as the
**Voice Request URL** of your TwiML App.

### 2. App (physical iOS device)
The device can't reach `localhost`; point it at your Mac's LAN IP:
```bash
flutter run --dart-define=TOKEN_SERVER=http://<mac-lan-ip>:3000
```
Enter a destination number in E.164 (e.g. `+15551234567`) and tap **Call**.
(Trial accounts: the destination must be a **verified** number.)

## Twilio resources needed
- An **API Key** (SID + Secret) — for signing Access Tokens.
- A **TwiML App** — its Voice URL points at `POST /voice`.
- A **Voice-capable phone number** — caller ID for outbound PSTN.

## Resuming the live test (after iOS device registration clears)

Everything below is already provisioned; `server/.env` is filled in, and the
TwiML App points at the reserved ngrok domain `https://goliveira.ngrok.app`.
The only thing that was blocking the device install is Apple's device
registration on the dev team (≈2 business days). Once Maelle is registered:

```bash
# 1. token server (env already populated)
cd server && npm run start            # http://localhost:3000

# 2. tunnel (reserved domain → TwiML App URL already matches)
ngrok http 3000                       # https://goliveira.ngrok.app

# 3. deploy to the device + point it at the public token server
cd .. && flutter run \
  -d 00008150-001065601187801C \
  --dart-define=TOKEN_SERVER=https://goliveira.ngrok.app
```

Then in the app: enter a destination number in E.164 → **Call** → grant the mic
prompt → two-way audio. Caller ID is `+551132304091`.

If the ngrok domain ever differs from `goliveira.ngrok.app`, update the TwiML
App's Voice URL:
```bash
twilio api:core:applications:update --sid AP0f4b7e884f935857f5ed1f5596028215 \
  --voice-url "https://<new-domain>/voice" --voice-method POST
```

Signing note: the project is set to org team `L5QDY54VAL`. If you switch to a
personal team instead, it must be done in the **Xcode GUI** (Settings → Accounts
+ Signing tab) — free teams can't provision from the CLI.

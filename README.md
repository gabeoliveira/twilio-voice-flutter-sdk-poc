# Twilio Voice — Flutter Wrapper POC (Outbound Calls)

A minimal but **real, working** example of wrapping the native Twilio Voice SDKs in a
Flutter app to place **outbound** voice calls. It includes:

- a reusable **wrapper plugin** (`packages/twilio_voice`) bridging Dart to the native
  Twilio Voice SDKs on Android and iOS,
- a **demo dialer app** (`lib/main.dart`) that uses it, and
- a **token server** (`server/`) that mints the Access Tokens the SDK requires.

The wrapper is **outbound-only**, but the native call delegates and the `incomingAllow`
grant are already in place so an inbound (push + CallKit / ConnectionService) phase can be
added without changing the Dart API.

## Layout

```
packages/twilio_voice/                 # the sample wrapper (Flutter plugin)
  lib/twilio_voice.dart                #   Dart API: connect/disconnect/mute/speaker/sendDigits + event stream
  android/.../TwilioVoicePlugin.kt     #   Kotlin: com.twilio:voice-android
  ios/Classes/TwilioVoicePlugin.swift  #   Swift: TwilioVoice SDK
lib/main.dart                          # demo dialer UI (calls the token server, then the wrapper)
server/                                # TypeScript token server: Access Token + TwiML <Dial>
```

## How a call flows

1. The app calls the token server `GET /token` → it mints a Twilio **Access Token**
   (Voice grant pointing at your TwiML App).
2. The app calls `TwilioVoice.connect(accessToken, to)` → the native SDK connects to Twilio.
3. Twilio invokes the TwiML App's Voice URL → `POST /voice` returns
   `<Dial><Number>{to}</Number></Dial>`.
4. Twilio bridges the call to the destination number using your caller ID. Two-way audio
   flows over WebRTC.

## Prerequisites

- **Flutter** 3.44+ (this POC was built on 3.44.4).
- **Android:** Android SDK (API 36), JDK 17.
- **iOS:** full **Xcode** + CocoaPods, and a **physical device** — the Twilio Voice SDK
  does not run on the iOS Simulator. iOS device builds require a signing team (see
  [iOS signing](#ios-signing-notes)).
- **Node.js** 18+ for the token server.
- A **Twilio account** and the resources below.
- A way to expose the local token server publicly (e.g. **ngrok** or any HTTP tunnel).

## Twilio resources needed

| Resource | Purpose |
|---|---|
| **API Key** (SID + Secret) | Signs the Access Tokens minted by the server |
| **TwiML App** | Its Voice Request URL points at your server's `POST /voice` |
| **Voice-capable phone number** | Caller ID for the outbound PSTN leg |

## Setup

### 1. Token server

```bash
cd server
cp .env.example .env      # then fill in the values (see below)
npm install
npm run dev               # starts on http://localhost:3000
```

Fill `server/.env` with your own values:

```bash
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_API_KEY_SID=SKxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_API_KEY_SECRET=your_api_key_secret
TWILIO_TWIML_APP_SID=APxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_CALLER_ID=+1XXXXXXXXXX          # a Voice-capable Twilio number you own
PORT=3000
```

> `server/.env` is git-ignored — never commit real credentials. Only `.env.example` is tracked.

### 2. Expose the server and point your TwiML App at it

Twilio must be able to reach `POST /voice` over the public internet:

```bash
ngrok http 3000           # gives you a public https URL
```

Set that public URL as the **Voice Request URL** of your TwiML App (method `POST`):

```bash
twilio api:core:applications:update \
  --sid <YOUR_TWIML_APP_SID> \
  --voice-url "https://<your-public-url>/voice" \
  --voice-method POST
```

### 3. Run the app on a device

The phone can't reach your Mac's `localhost`, so point it at the public URL (or your Mac's
LAN IP if the server and device are on the same network):

```bash
flutter run \
  -d <YOUR_DEVICE_ID> \
  --dart-define=TOKEN_SERVER=https://<your-public-url>
```

`flutter devices` lists connected devices and their IDs. In the app: enter a destination
number in **E.164** (e.g. `+1XXXXXXXXXX`) → tap **Call** → grant the microphone prompt →
two-way audio.

> **Trial accounts:** the destination number must be a **verified** number.

## iOS signing notes

- iOS device builds need a **signing team** on the `Runner` target (Xcode → *Signing &
  Capabilities*), plus a **unique bundle identifier**.
- Development teams are capped at **100 registered devices per membership year**. If you hit
  "maximum number of registered devices," free a slot in the Apple Developer portal
  (*Devices*) or sign with a different team.
- **Free / personal teams can only provision from the Xcode GUI**, not the command line —
  add your Apple ID under *Xcode → Settings → Accounts*, select the team on the `Runner`
  target, then Run once from Xcode to register the device and generate the profile.

## iOS dependency manager

This POC packages the plugin using **CocoaPods** for expediency, but **CocoaPods is being
sunset** (its registry goes read-only in December 2026) and **Flutter 3.44+ defaults to
Swift Package Manager (SPM)**. TwilioVoice is distributed via SPM as well. **For a
production build, prefer SPM** — package the plugin as a Swift Package and consume
TwilioVoice via SPM.

## Wrapper API

`TwilioVoice.instance` exposes:

| Member | Description |
|---|---|
| `Stream<CallEvent> onCallEvent` | Call lifecycle events (`connecting`/`ringing`/`connected`/`reconnecting`/`disconnected`/`error`) |
| `Future<bool> requestMicrophonePermission()` | Prompts for microphone access |
| `Future<void> connect({accessToken, to})` | Places an outbound call |
| `Future<void> disconnect()` | Ends the active call |
| `Future<void> setMuted(bool)` | Mutes/unmutes the mic |
| `Future<void> setSpeaker(bool)` | Routes audio to speaker/earpiece |
| `Future<void> sendDigits(String)` | Sends DTMF tones |

Request the microphone permission **before** calling `connect()`, or the call will have no
audio.

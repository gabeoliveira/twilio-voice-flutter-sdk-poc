import 'dotenv/config';
import express, { type Request, type Response } from 'express';
import twilio from 'twilio';

const {
  TWILIO_ACCOUNT_SID,
  TWILIO_API_KEY_SID,
  TWILIO_API_KEY_SECRET,
  TWILIO_TWIML_APP_SID,
  TWILIO_CALLER_ID,
  PORT = '3000',
} = process.env;

function requireEnv(name: string, value: string | undefined): string {
  if (!value) {
    console.error(`Missing required env var: ${name}`);
    process.exit(1);
  }
  return value;
}

const accountSid = requireEnv('TWILIO_ACCOUNT_SID', TWILIO_ACCOUNT_SID);
const apiKeySid = requireEnv('TWILIO_API_KEY_SID', TWILIO_API_KEY_SID);
const apiKeySecret = requireEnv('TWILIO_API_KEY_SECRET', TWILIO_API_KEY_SECRET);
const twimlAppSid = requireEnv('TWILIO_TWIML_APP_SID', TWILIO_TWIML_APP_SID);
const callerId = requireEnv('TWILIO_CALLER_ID', TWILIO_CALLER_ID);

const { AccessToken } = twilio.jwt;
const { VoiceGrant } = AccessToken;
const { VoiceResponse } = twilio.twiml;

const app = express();
app.use(express.urlencoded({ extended: false }));

// Dev-only: the WebView/JS-SDK timing harness fetches /token from a file:// origin,
// so the browser applies CORS. Allow it for local measurement. (Not for production —
// scope this to your app's origin, or keep token minting same-origin.)
app.use((_req: Request, res: Response, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  next();
});

/**
 * GET /token?identity=<id>
 * Mints a Twilio Access Token with a Voice grant for outbound calling.
 * The grant points at the TwiML App, whose Voice URL is POST /voice below.
 */
app.get('/token', (req: Request, res: Response) => {
  const identity = (req.query.identity as string) || 'flutter-demo-user';

  const token = new AccessToken(accountSid, apiKeySid, apiKeySecret, {
    identity,
    ttl: 3600,
  });
  token.addGrant(
    new VoiceGrant({
      outgoingApplicationSid: twimlAppSid,
      incomingAllow: true, // harmless for outbound; ready for the inbound phase
    }),
  );

  res.json({ identity, token: token.toJwt() });
});

/**
 * POST /voice
 * The TwiML App's Voice Request URL. Twilio calls this when the SDK connects.
 * It dials the `To` parameter the app passed (a PSTN number), using the
 * verified Twilio number as caller ID.
 */
app.post('/voice', (req: Request, res: Response) => {
  const to = ((req.body.To as string) || '').trim();
  const response = new VoiceResponse();

  if (to) {
    const dial = response.dial({ callerId });
    dial.number(to);
  } else {
    response.say('No destination number was provided.');
  }

  res.type('text/xml').send(response.toString());
});

app.get('/health', (_req: Request, res: Response) => res.json({ ok: true }));

app.listen(Number(PORT), () => {
  console.log(`Token server listening on http://0.0.0.0:${PORT}`);
  console.log(`  GET  /token?identity=...   -> Access Token`);
  console.log(`  POST /voice                -> TwiML <Dial> (set as TwiML App Voice URL)`);
});

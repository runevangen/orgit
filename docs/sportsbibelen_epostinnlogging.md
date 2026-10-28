# Bruksanvisning: e-postinnlogging (engangskode) i sportsbibelen

Lim hele denne filen inn i Claude Code-chatten for sportsbibelen og be om å få det gjort. Den er skrevet av økten som bygde samme innlogging i orgit (Oppgavetavle), og beskriver det som er verifisert der.

## Mål

Sportsbibelen logger inn med PIN i dag. Legg til innlogging med e-post og engangskode, og flytt eksisterende PIN-kontoer over til ekte e-postadresser uten å miste data. Fjern PIN-veien til slutt.

## Viktig om Supabase-prosjektet (delt med flere apper)

- Supabase-prosjekt: `xhvbblbyyyejgyybikme` (region eu-west-1). Prosjektet deles av orgit, quiz, pub og sportsbibelen.
- **E-postmaler og avsendernavn gjelder hele prosjektet.** Ikke gjør malen sportsbibelen-spesifikk. Malene er satt nøytrale:
  - Avsendernavn (Authentication → SMTP Settings): `Innloggingskode`
  - Emne: `Din engangskode: {{ .Token }}`
  - Innhold: viser `{{ .Token }}` (6 sifre). Dette gjelder både malen «Magic Link» og «Confirm signup». Begge må vise `{{ .Token }}`, ellers får brukeren en lenke i stedet for kode.
- Ikke endre tabeller, funksjoner eller RLS som tilhører andre apper (`oppg_*`, `quiz_*`, `rom_*`, `gaate_*`, `bilde_*`, `pub_*`, `visning*`).
- Supabase-advarselen «RLS enabled, no policy» på noen tabeller er bevisst (tabellene nås bare via funksjoner). Ikke «fiks» den uten å vite hva tabellen brukes til.
- Av 7 rader i `pin_kontoer(slug, bruker uuid, laget)` er `bruker` en id i `auth.users`. PIN-kontoene er altså ekte Auth-brukere. **Les først hvordan sportsbibelen logger inn med PIN i dag** (PIN som passord med syntetisk e-post, eller en egen funksjon), og bygg videre på det. Ikke gjett.

## Slik fungerer koden i orgit (kopier mønsteret)

```js
// 1) Send kode
const { error } = await sb.auth.signInWithOtp({ email, options: { shouldCreateUser: true } });
// 2) Bekreft kode (6 sifre, fjern mellomrom)
const { data, error } = await sb.auth.verifyOtp({ email, token, type: 'email' });
if (error || !data || !data.session) { /* feil eller utløpt kode */ }
// 3) Hent økt ved oppstart
const { data: sd } = await sb.auth.getSession();
```

UI-krav som er verifisert i orgit:
- E-postfelt: `type="email" inputmode="email" autocomplete="email" autocapitalize="off"`. E-post gjøres om til små bokstaver.
- Kodefelt: `inputmode="numeric" autocomplete="one-time-code" maxlength="10"`. Fjern mellomrom før `verifyOtp`.
- «Send ny kode»-knapp deaktivert i 45 sekunder, «Bruk en annen e-post»-knapp.
- Meld tydelig fra ved feil eller utløpt kode, og ved for mange forsøk (`rate|limit|seconds` i feilmeldingen).
- Pass på at Content-Security-Policy (hvis den er satt) tillater `connect-src` mot Supabase (`https://xhvbblbyyyejgyybikme.supabase.co` og `wss://`).

## Foreslått plan

### Trinn 1: Legg til e-post ved siden av PIN
- Ny skjerm «Logg inn med e-post» med kodeflyt som over. PIN-innloggingen beholdes inntil videre.
- Test at en ny e-postbruker kommer inn og at eksisterende PIN-brukere fortsatt kommer inn.

### Trinn 2: Koble eksisterende PIN-kontoer til e-post (uten å miste data)
- Mens en PIN-bruker er innlogget: be om e-post, kall `sb.auth.updateUser({ email })`. Supabase sender en bekreftelseskode (malen «Change Email Address» må også vise `{{ .Token }}`). Bekreft med `verifyOtp({ email, token, type: 'email_change' })`.
- Brukeren beholder samme bruker-id, så `pin_kontoer.bruker` og alle data som peker på brukeren følger med.
- Hvis en e-postadresse allerede er i bruk av en annen Auth-bruker, må du slå sammen manuelt. Ikke slett noen bruker uten å ha sjekket hva som peker på den. **Spør meg før du sletter eller slår sammen brukere.**
- Sjekk først hvilke av de 7 PIN-kontoene som er ekte personer og hvilke som er testkontoer (uten å skrive personopplysninger i chatten).

### Trinn 3: Fjern PIN-veien
- Når alle har e-post: fjern PIN-skjermene, og trekk tilbake rettigheter på PIN-funksjonene med `revoke execute ... from public, anon, authenticated` (kun funksjoner sportsbibelen eier).
- Behold en tilbakestillings-SQL-fil i repoet i tilfelle noe må angres.

## Arbeidsmåte (samme som i orgit)

1. Les eksisterende innloggingskode først. Lag en liten endring om gangen.
2. Test lokalt (Playwright/nettleser) med falsk Supabase-stub der nettverket er blokkert, eller mot en testbruker.
3. Legg endringer i en egen gren. Be meg godkjenne før noe merges til `main`.
4. SQL som endrer databasen: lag en `.sql`-fil jeg kjører i Supabase SQL Editor. Verifiser etterpå med leseforespørsler. Ikke kjør DDL via MCP uten at jeg har bedt om det (godkjenningene har tidligere tidsavbrutt).
5. Svar på norsk og avslutt gjerne med et klikkbart valg når det er naturlig.

## Før du begynner, spør meg

- Skal PIN fjernes helt til slutt, eller beholdes som alternativ?
- Hvilke e-postadresser tilhører de 7 PIN-kontoene?
- Skal nye brukere kunne opprette seg selv med e-post (`shouldCreateUser: true`), eller kun inviterte?

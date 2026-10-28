-- Steg 1 sikkerhet for Oppgavetavle. Kjør hele filen i Supabase → SQL Editor.
-- Trygt å kjøre flere ganger. Ingenting slettes og ingen rettigheter trekkes tilbake.
-- Hjelpetabeller og -funksjoner ligger i skjemaet oppg_privat, som ikke er eksponert via API-et.

create schema if not exists oppg_privat;

create table if not exists oppg_privat.innstillinger (nokkel text primary key, verdi text not null);
insert into oppg_privat.innstillinger(nokkel, verdi)
  values ('invitasjonskode', upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8)))
  on conflict (nokkel) do nothing;

create table if not exists oppg_privat.forsok (
  id bigserial primary key,
  noekkel text not null,
  tid timestamptz not null default now()
);
create index if not exists forsok_idx on oppg_privat.forsok (noekkel, tid);

create or replace function oppg_privat.sjekk_grense(p_noekkel text, p_maks integer, p_minutter integer)
returns void language plpgsql
as $f$
begin
  if (select count(*) from oppg_privat.forsok where noekkel = p_noekkel and tid > now() - make_interval(mins => p_minutter)) >= p_maks then
    raise exception 'For mange forsøk. Prøv igjen om noen minutter.';
  end if;
end $f$;

create or replace function oppg_privat.logg_feil(p_noekkel text)
returns void language plpgsql
as $f$
begin
  insert into oppg_privat.forsok(noekkel) values (p_noekkel);
  delete from oppg_privat.forsok where tid < now() - interval '1 day';
end $f$;

create or replace function public.oppg_logg_inn(p_navn text, p_pin text)
returns table(id uuid, navn text, farge text)
language plpgsql security definer set search_path to 'public','extensions'
as $f$
#variable_conflict use_column
declare k text := 'inn:' || lower(coalesce(p_navn,''));
begin
  perform oppg_privat.sjekk_grense(k, 5, 15);
  perform oppg_privat.sjekk_grense('inn:*', 80, 15);
  return query select b.id, b.navn, b.farge from public.oppg_brukere b
    where lower(b.navn) = lower(p_navn) and b.pin_hash = crypt(p_pin, b.pin_hash);
  if not found then
    perform oppg_privat.logg_feil(k); perform oppg_privat.logg_feil('inn:*');
  else
    delete from oppg_privat.forsok where noekkel = k;
  end if;
end $f$;

create or replace function public.oppg_rsvp_lenker(p_navn text, p_pin text, p_tavle uuid)
returns table(gjest_id uuid, token text)
language plpgsql security definer set search_path to 'public','extensions'
as $f$
#variable_conflict use_column
declare ok boolean; k text := 'pin:' || lower(coalesce(p_navn,''));
begin
  perform oppg_privat.sjekk_grense(k, 5, 15);
  select exists(select 1 from public.oppg_brukere b where lower(b.navn)=lower(coalesce(p_navn,'')) and b.pin_hash = crypt(coalesce(p_pin,''), b.pin_hash)) into ok;
  if not ok then perform oppg_privat.logg_feil(k); return; end if;
  delete from oppg_privat.forsok where noekkel = k;
  insert into public.oppg_rsvp(gjest_id)
    select g.id from public.oppg_gjester g where g.tavle_id = p_tavle and not exists (select 1 from public.oppg_rsvp r where r.gjest_id = g.id);
  return query select r.gjest_id, r.token from public.oppg_rsvp r join public.oppg_gjester g on g.id = r.gjest_id where g.tavle_id = p_tavle;
end $f$;

create or replace function public.oppg_invitasjonskode(p_navn text, p_pin text, p_ny text default null)
returns text
language plpgsql security definer set search_path to 'public','extensions'
as $f$
declare ok boolean; k text := 'pin:' || lower(coalesce(p_navn,'')); kode text;
begin
  perform oppg_privat.sjekk_grense(k, 5, 15);
  select exists(select 1 from public.oppg_brukere b where lower(b.navn)=lower(coalesce(p_navn,'')) and b.pin_hash = crypt(coalesce(p_pin,''), b.pin_hash)) into ok;
  if not ok then perform oppg_privat.logg_feil(k); return null; end if;
  delete from oppg_privat.forsok where noekkel = k;
  if p_ny is not null then
    if length(trim(p_ny)) < 6 or length(trim(p_ny)) > 30 then raise exception 'Koden må være 6–30 tegn'; end if;
    update oppg_privat.innstillinger set verdi = upper(trim(p_ny)) where nokkel = 'invitasjonskode';
  end if;
  select verdi into kode from oppg_privat.innstillinger where nokkel = 'invitasjonskode';
  return kode;
end $f$;

create or replace function public.oppg_ny_bruker2(p_navn text, p_pin text, p_farge text, p_kode text default null)
returns table(id uuid, navn text, farge text)
language plpgsql security definer set search_path to 'public','extensions'
as $f$
#variable_conflict use_column
declare antall integer; riktig text;
begin
  perform oppg_privat.sjekk_grense('reg:*', 10, 60);
  select count(*) into antall from public.oppg_brukere;
  select verdi into riktig from oppg_privat.innstillinger where nokkel = 'invitasjonskode';
  if antall > 0 and upper(trim(coalesce(p_kode,''))) <> coalesce(riktig, '#') then
    perform oppg_privat.logg_feil('reg:*'); return;
  end if;
  if length(trim(coalesce(p_navn,''))) < 1 or length(trim(p_navn)) > 30 then raise exception 'Navn må være 1–30 tegn'; end if;
  if length(coalesce(p_pin,'')) < 6 then raise exception 'PIN må ha minst 6 tegn'; end if;
  return query
    insert into public.oppg_brukere(navn, pin_hash, farge)
    values (trim(p_navn), crypt(p_pin, gen_salt('bf')), coalesce(p_farge,'#4f7cff'))
    returning oppg_brukere.id, oppg_brukere.navn, oppg_brukere.farge;
end $f$;

grant execute on function public.oppg_invitasjonskode(text,text,text) to anon, authenticated;
grant execute on function public.oppg_ny_bruker2(text,text,text,text) to anon, authenticated;

-- Gjør de gamle, åpne funksjonene harmløse (samme signatur, ingen rettigheter endres):
create or replace function public.oppg_ny_bruker(p_navn text, p_pin text, p_farge text, p_admin_navn text default null, p_admin_pin text default null)
returns table(id uuid, navn text, farge text)
language plpgsql security definer set search_path to 'public'
as $f$
begin
  raise exception 'Utgått: bruk invitasjonskode i appen.';
end $f$;

create or replace function public.oppg_rsvp_hent(p_token text)
returns table(navn text, antall integer, status text, melding text, tavle_navn text)
language sql security definer set search_path to 'public'
as $f$
  select null::text, null::integer, null::text, null::text, null::text where false;
$f$;

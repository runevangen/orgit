-- Steg 2, trinn 1: ekte innlogging med e-post (medlemskap per tavle).
-- Kjør hele filen i Supabase → SQL Editor. Trygt å kjøre flere ganger.
-- Dette trinnet er additivt: de eksisterende åpne reglene står urørt, så ingenting låses.

-- 1) Hvem er eier som kan ta over de eksisterende tavlene (settes én gang)
insert into oppg_privat.innstillinger(nokkel, verdi)
  values ('eier_epost', 'runevangen@gmail.com')
  on conflict (nokkel) do update set verdi = excluded.verdi;

-- 2) Personer kobles til innloggede brukere (e-post). PIN er valgfri for nye personer.
alter table public.oppg_brukere add column if not exists user_id uuid references auth.users(id) on delete set null;
create unique index if not exists oppg_brukere_user_idx on public.oppg_brukere (user_id) where user_id is not null;
alter table public.oppg_brukere alter column pin_hash drop not null;

-- 3) Medlemmer og invitasjoner (kun tilgang via funksjoner; ingen åpne regler)
create table if not exists public.oppg_medlemmer (
  tavle_id uuid not null references public.oppg_tavler(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rolle text not null check (rolle in ('eier','redaktor')),
  opprettet timestamptz not null default now(),
  primary key (tavle_id, user_id)
);
create table if not exists public.oppg_invitasjoner (
  tavle_id uuid not null references public.oppg_tavler(id) on delete cascade,
  epost text not null check (epost = lower(epost)),
  rolle text not null default 'redaktor' check (rolle in ('eier','redaktor')),
  invitert_av uuid references auth.users(id) on delete set null,
  opprettet timestamptz not null default now(),
  primary key (tavle_id, epost)
);
alter table public.oppg_medlemmer enable row level security;
alter table public.oppg_invitasjoner enable row level security;

-- 4) Hjelpefunksjoner (brukes av reglene i trinn 2)
create or replace function public.oppg_er_medlem(p_tavle uuid)
returns boolean language sql stable security definer set search_path to 'public'
as $f$
  select exists(select 1 from public.oppg_medlemmer m where m.tavle_id = p_tavle and m.user_id = auth.uid());
$f$;

create or replace function public.oppg_rolle(p_tavle uuid)
returns text language sql stable security definer set search_path to 'public'
as $f$
  select m.rolle from public.oppg_medlemmer m where m.tavle_id = p_tavle and m.user_id = auth.uid() limit 1;
$f$;

-- 5) Min person
create or replace function public.oppg_meg()
returns table(id uuid, navn text, farge text, epost text)
language sql stable security definer set search_path to 'public'
as $f$
  select b.id, b.navn, b.farge, lower(auth.jwt()->>'email')
  from public.oppg_brukere b where auth.uid() is not null and b.user_id = auth.uid();
$f$;

create or replace function public.oppg_lag_meg(p_navn text, p_farge text)
returns table(id uuid, navn text, farge text)
language plpgsql security definer set search_path to 'public'
as $f$
#variable_conflict use_column
begin
  if auth.uid() is null then raise exception 'Ikke innlogget'; end if;
  if length(trim(coalesce(p_navn,''))) < 1 or length(trim(p_navn)) > 30 then raise exception 'Navn må være 1–30 tegn'; end if;
  if exists (select 1 from public.oppg_brukere b where b.user_id = auth.uid()) then
    return query update public.oppg_brukere b set navn = trim(p_navn), farge = coalesce(p_farge, b.farge)
      where b.user_id = auth.uid() returning b.id, b.navn, b.farge;
  else
    return query insert into public.oppg_brukere(navn, pin_hash, farge, user_id)
      values (trim(p_navn), null, coalesce(p_farge, '#4f7cff'), auth.uid())
      returning oppg_brukere.id, oppg_brukere.navn, oppg_brukere.farge;
  end if;
end $f$;

-- Koble en eksisterende PIN-person til den innloggede brukeren (bevarer ansvarlig og aktivitet)
create or replace function public.oppg_koble_meg(p_navn text, p_pin text)
returns table(id uuid, navn text, farge text)
language plpgsql security definer set search_path to 'public','extensions'
as $f$
#variable_conflict use_column
declare k text := 'koble:' || coalesce(auth.uid()::text, '');
begin
  if auth.uid() is null then raise exception 'Ikke innlogget'; end if;
  if exists (select 1 from public.oppg_brukere b where b.user_id = auth.uid()) then raise exception 'Du har allerede en person'; end if;
  perform oppg_privat.sjekk_grense(k, 5, 15);
  return query update public.oppg_brukere b set user_id = auth.uid()
    where b.user_id is null and lower(b.navn) = lower(coalesce(p_navn,'')) and b.pin_hash is not null
      and b.pin_hash = crypt(coalesce(p_pin,''), b.pin_hash)
    returning b.id, b.navn, b.farge;
  if not found then perform oppg_privat.logg_feil(k); end if;
end $f$;

-- 6) Ta over eksisterende tavler uten medlemmer (bare for eier-e-posten)
create or replace function public.oppg_ta_over()
returns integer language plpgsql security definer set search_path to 'public'
as $f$
declare n integer; eier text;
begin
  if auth.uid() is null then return 0; end if;
  select verdi into eier from oppg_privat.innstillinger where nokkel = 'eier_epost';
  if eier is null or lower(coalesce(auth.jwt()->>'email','')) <> lower(eier) then return 0; end if;
  insert into public.oppg_medlemmer(tavle_id, user_id, rolle)
    select t.id, auth.uid(), 'eier' from public.oppg_tavler t
    where not exists (select 1 from public.oppg_medlemmer m where m.tavle_id = t.id)
    on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $f$;

-- 7) Den som lager en tavle blir eier
create or replace function public.oppg_tavle_eier()
returns trigger language plpgsql security definer set search_path to 'public'
as $f$
begin
  if auth.uid() is not null then
    insert into public.oppg_medlemmer(tavle_id, user_id, rolle) values (new.id, auth.uid(), 'eier') on conflict do nothing;
  end if;
  return new;
end $f$;
drop trigger if exists oppg_tavle_eier_trg on public.oppg_tavler;
create trigger oppg_tavle_eier_trg after insert on public.oppg_tavler
  for each row execute function public.oppg_tavle_eier();

-- 8) Invitasjoner (ingen e-post sendes: personen logger inn med adressen og får tilgang)
create or replace function public.oppg_godta_invitasjoner()
returns integer language plpgsql security definer set search_path to 'public'
as $f$
declare n integer; e text := lower(coalesce(auth.jwt()->>'email',''));
begin
  if auth.uid() is null or e = '' then return 0; end if;
  insert into public.oppg_medlemmer(tavle_id, user_id, rolle)
    select i.tavle_id, auth.uid(), i.rolle from public.oppg_invitasjoner i where i.epost = e
    on conflict do nothing;
  get diagnostics n = row_count;
  delete from public.oppg_invitasjoner where epost = e;
  return n;
end $f$;

create or replace function public.oppg_inviter(p_tavle uuid, p_epost text, p_rolle text default 'redaktor')
returns void language plpgsql security definer set search_path to 'public'
as $f$
declare e text := lower(trim(coalesce(p_epost,''))); k text := 'inv:' || coalesce(auth.uid()::text,'');
begin
  if public.oppg_rolle(p_tavle) is distinct from 'eier' then raise exception 'Bare eier kan invitere'; end if;
  if e !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'Ugyldig e-postadresse'; end if;
  if p_rolle not in ('eier','redaktor') then raise exception 'Ugyldig rolle'; end if;
  perform oppg_privat.sjekk_grense(k, 20, 60);
  perform oppg_privat.logg_feil(k);
  insert into public.oppg_medlemmer(tavle_id, user_id, rolle)
    select p_tavle, u.id, p_rolle from auth.users u where lower(u.email) = e
    on conflict (tavle_id, user_id) do update set rolle = excluded.rolle;
  if not found then
    insert into public.oppg_invitasjoner(tavle_id, epost, rolle, invitert_av) values (p_tavle, e, p_rolle, auth.uid())
      on conflict (tavle_id, epost) do update set rolle = excluded.rolle;
  end if;
end $f$;

create or replace function public.oppg_medlemmer_liste(p_tavle uuid)
returns table(user_id uuid, epost text, person_id uuid, navn text, farge text, rolle text, ventende boolean)
language plpgsql stable security definer set search_path to 'public'
as $f$
begin
  if not public.oppg_er_medlem(p_tavle) then raise exception 'Ikke tilgang'; end if;
  return query
    select m.user_id, lower(u.email::text), b.id, b.navn, b.farge, m.rolle, false
      from public.oppg_medlemmer m join auth.users u on u.id = m.user_id
      left join public.oppg_brukere b on b.user_id = m.user_id
      where m.tavle_id = p_tavle
    union all
    select null::uuid, i.epost, null::uuid, null::text, null::text, i.rolle, true
      from public.oppg_invitasjoner i where i.tavle_id = p_tavle;
end $f$;

create or replace function public.oppg_endre_rolle(p_tavle uuid, p_user uuid, p_rolle text)
returns void language plpgsql security definer set search_path to 'public'
as $f$
begin
  if public.oppg_rolle(p_tavle) is distinct from 'eier' then raise exception 'Bare eier kan endre roller'; end if;
  if p_rolle not in ('eier','redaktor') then raise exception 'Ugyldig rolle'; end if;
  if p_rolle <> 'eier' and (select count(*) from public.oppg_medlemmer m where m.tavle_id = p_tavle and m.rolle = 'eier' and m.user_id <> p_user) = 0 then
    raise exception 'Tavlen må ha minst én eier';
  end if;
  update public.oppg_medlemmer set rolle = p_rolle where tavle_id = p_tavle and user_id = p_user;
end $f$;

create or replace function public.oppg_fjern_medlem(p_tavle uuid, p_user uuid)
returns void language plpgsql security definer set search_path to 'public'
as $f$
begin
  if p_user is distinct from auth.uid() and public.oppg_rolle(p_tavle) is distinct from 'eier' then raise exception 'Bare eier kan fjerne andre'; end if;
  if not public.oppg_er_medlem(p_tavle) then raise exception 'Ikke tilgang'; end if;
  if (select m.rolle from public.oppg_medlemmer m where m.tavle_id = p_tavle and m.user_id = p_user) = 'eier'
     and (select count(*) from public.oppg_medlemmer m where m.tavle_id = p_tavle and m.rolle = 'eier') <= 1 then
    raise exception 'Tavlen må ha minst én eier';
  end if;
  delete from public.oppg_medlemmer where tavle_id = p_tavle and user_id = p_user;
end $f$;

create or replace function public.oppg_fjern_invitasjon(p_tavle uuid, p_epost text)
returns void language plpgsql security definer set search_path to 'public'
as $f$
begin
  if public.oppg_rolle(p_tavle) is distinct from 'eier' then raise exception 'Bare eier kan fjerne invitasjoner'; end if;
  delete from public.oppg_invitasjoner where tavle_id = p_tavle and epost = lower(coalesce(p_epost,''));
end $f$;

-- 9) Personer som vises på tavlen (medlemmer + de som står som ansvarlig/aktive)
create or replace function public.oppg_personer(p_tavle uuid)
returns table(id uuid, navn text, farge text)
language plpgsql stable security definer set search_path to 'public'
as $f$
#variable_conflict use_column
begin
  if not public.oppg_er_medlem(p_tavle) then return; end if;
  return query
    select distinct b.id, b.navn, b.farge from public.oppg_brukere b
    where b.user_id in (select m.user_id from public.oppg_medlemmer m where m.tavle_id = p_tavle)
       or b.id in (select k.ansvarlig from public.oppg_kort k where k.tavle_id = p_tavle and k.ansvarlig is not null)
       or b.id in (select a.bruker_id from public.oppg_aktivitet a where a.tavle_id = p_tavle and a.bruker_id is not null)
    order by 2;
end $f$;

-- 10) Svarlenker for medlemmer (uten PIN)
create or replace function public.oppg_rsvp_lenker2(p_tavle uuid)
returns table(gjest_id uuid, token text)
language plpgsql security definer set search_path to 'public'
as $f$
#variable_conflict use_column
begin
  if not public.oppg_er_medlem(p_tavle) then raise exception 'Ikke tilgang'; end if;
  insert into public.oppg_rsvp(gjest_id)
    select g.id from public.oppg_gjester g where g.tavle_id = p_tavle and not exists (select 1 from public.oppg_rsvp r where r.gjest_id = g.id);
  return query select r.gjest_id, r.token from public.oppg_rsvp r join public.oppg_gjester g on g.id = r.gjest_id where g.tavle_id = p_tavle;
end $f$;

-- Kobling av felles-lenke-svar til registrerte gjester: godkjenning, gruppe i treff og sammenslåing.
-- Legger til kolonner, én tabell og funksjoner. Kjør i Supabase → SQL Editor før appen merges.

alter table public.oppg_gjester add column if not exists godkjent boolean not null default true;

-- Gamle svarlenker som skal fortsette å virke etter en sammenslåing
create table if not exists public.oppg_rsvp_alias (
  token text primary key,
  gjest_id uuid not null references public.oppg_gjester(id) on delete cascade
);
alter table public.oppg_rsvp_alias enable row level security;

-- Finn gjesten bak en svarlenke (egen lenke eller gammel lenke fra en sammenslåing)
create or replace function public.oppg_rsvp_gjest(p_token text)
returns uuid language sql security definer stable set search_path to 'public'
as $f$
  select coalesce((select gjest_id from public.oppg_rsvp where token = p_token),
                  (select gjest_id from public.oppg_rsvp_alias where token = p_token));
$f$;

create or replace function public.oppg_rsvp_hent3(p_token text)
returns table(navn text, antall integer, status text, melding text, tavle_navn text, arr_navn text, arr_dato date, arr_tid text, arr_sted text, arr_tekst text, arr_frist date, matvalg text, allergier text, arr_meny text)
language sql security definer set search_path to 'public'
as $f$
  select g.navn, g.antall, g.status, g.svar_melding, t.navn, t.arr_navn, t.arr_dato, t.arr_tid, t.arr_sted, t.arr_tekst, t.arr_frist, g.matvalg, g.allergier, t.arr_meny
  from public.oppg_gjester g join public.oppg_tavler t on t.id = g.tavle_id
  where g.id = public.oppg_rsvp_gjest(p_token);
$f$;

create or replace function public.oppg_rsvp_svar2(p_token text, p_status text, p_antall integer, p_melding text, p_matvalg text, p_allergier text)
returns boolean
language plpgsql security definer set search_path to 'public'
as $f$
declare n integer;
begin
  if p_status not in ('kommer','kommer_ikke','kanskje') then return false; end if;
  update public.oppg_gjester g
     set status = p_status,
         antall = coalesce(least(greatest(p_antall,1),20), g.antall),
         svar_melding = left(coalesce(p_melding,''),300),
         matvalg = nullif(left(trim(coalesce(p_matvalg,'')),60),''),
         allergier = nullif(left(trim(coalesce(p_allergier,'')),300),''),
         svar_tid = now(),
         bord_id = case when p_status = 'kommer_ikke' then null else g.bord_id end
   where g.id = public.oppg_rsvp_gjest(p_token);
  get diagnostics n = row_count;
  return n > 0;
end $f$;

-- Søk med gruppe i treffet. Nye, ikke godkjente navn dukker ikke opp for andre.
create or replace function public.oppg_felles_sok2(p_token text, p_q text)
returns table(navn text, token text, gruppe text)
language plpgsql security definer set search_path to 'public', 'extensions'
as $f$
#variable_conflict use_column
declare t uuid; k text; q text := trim(coalesce(p_q, ''));
begin
  select id into t from public.oppg_tavler where p_token is not null and felles_token = p_token;
  if t is null or length(q) < 3 then return; end if;
  k := 'felles:' || left(p_token, 16);
  perform oppg_privat.sjekk_grense(k, 300, 15);
  perform oppg_privat.logg_feil(k);
  insert into public.oppg_rsvp(gjest_id)
    select g.id from public.oppg_gjester g where g.tavle_id = t and not exists (select 1 from public.oppg_rsvp r where r.gjest_id = g.id);
  return query
    select g.navn, r.token, gr.navn from public.oppg_gjester g
    join public.oppg_rsvp r on r.gjest_id = g.id
    left join public.oppg_grupper gr on gr.id = g.gruppe_id
    where g.tavle_id = t and g.godkjent
      and g.navn ilike '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%'
    order by g.navn limit 5;
end $f$;

-- Nye navn fra felles lenke venter på godkjenning
create or replace function public.oppg_felles_ny(p_token text, p_navn text)
returns text
language plpgsql security definer set search_path to 'public', 'extensions'
as $f$
declare t uuid; k text; n text := left(trim(coalesce(p_navn, '')), 100); gid uuid; tok text;
begin
  select id into t from public.oppg_tavler where p_token is not null and felles_token = p_token;
  if t is null or length(n) < 2 then return null; end if;
  k := 'fellesny:' || left(p_token, 16);
  perform oppg_privat.sjekk_grense(k, 30, 15);
  perform oppg_privat.logg_feil(k);
  select id into gid from public.oppg_gjester where tavle_id = t and lower(navn) = lower(n) limit 1;
  if gid is null then
    insert into public.oppg_gjester(tavle_id, navn, notat, godkjent) values (t, n, 'Lagt til via felles lenke', false) returning id into gid;
  end if;
  insert into public.oppg_rsvp(gjest_id) select gid where not exists (select 1 from public.oppg_rsvp where gjest_id = gid);
  select r.token into tok from public.oppg_rsvp r where r.gjest_id = gid;
  return tok;
end $f$;

-- Slå sammen en ny gjest (fra) inn i en registrert gjest (til). Svaret flyttes, og lenken til «fra» fortsetter å virke.
create or replace function public.oppg_slaa_sammen(p_fra uuid, p_til uuid)
returns void
language plpgsql security definer set search_path to 'public'
as $f$
declare a public.oppg_gjester; b public.oppg_gjester;
begin
  select * into a from public.oppg_gjester where id = p_fra;
  select * into b from public.oppg_gjester where id = p_til;
  if a.id is null or b.id is null or a.id = b.id or a.tavle_id <> b.tavle_id then raise exception 'Ugyldig sammenslåing'; end if;
  if not public.oppg_er_medlem(a.tavle_id) then raise exception 'Ikke tilgang'; end if;
  update public.oppg_gjester set
    status = case when a.status <> 'venter' then a.status else b.status end,
    antall = case when a.svar_tid is not null then a.antall else b.antall end,
    svar_melding = case when a.svar_tid is not null then a.svar_melding else b.svar_melding end,
    svar_tid = coalesce(a.svar_tid, b.svar_tid),
    matvalg = coalesce(a.matvalg, b.matvalg),
    allergier = coalesce(a.allergier, b.allergier)
  where id = p_til;
  insert into public.oppg_rsvp_alias(token, gjest_id) select token, p_til from public.oppg_rsvp where gjest_id = p_fra on conflict do nothing;
  update public.oppg_rsvp_alias set gjest_id = p_til where gjest_id = p_fra;
  delete from public.oppg_gjester where id = p_fra;
end $f$;

revoke execute on function public.oppg_rsvp_gjest(text) from public, anon, authenticated;
revoke execute on function public.oppg_felles_sok2(text, text) from public;
revoke execute on function public.oppg_slaa_sammen(uuid, uuid) from public, anon;
grant execute on function public.oppg_felles_sok2(text, text) to anon, authenticated;
grant execute on function public.oppg_slaa_sammen(uuid, uuid) to authenticated;
revoke execute on function public.oppg_rsvp_hent3(text) from public;
revoke execute on function public.oppg_rsvp_svar2(text,text,integer,text,text,text) from public;
grant execute on function public.oppg_rsvp_hent3(text) to anon, authenticated;
grant execute on function public.oppg_rsvp_svar2(text,text,integer,text,text,text) to anon, authenticated;

-- Felles lenke til gruppechat: én lenke, gjesten skriver navnet sitt og velger seg selv.
-- Legger bare til én kolonne og tre funksjoner. Kjør i Supabase → SQL Editor før appen merges.

alter table public.oppg_tavler add column if not exists felles_token text;
create unique index if not exists oppg_tavler_felles_token on public.oppg_tavler(felles_token) where felles_token is not null;

-- Arrangementsinfo for den som åpner den felles lenken
create or replace function public.oppg_felles_hent(p_token text)
returns table(tavle_navn text, arr_navn text, arr_dato date, arr_tid text, arr_sted text, arr_tekst text, arr_frist date)
language sql security definer set search_path to 'public'
as $f$
  select t.navn, t.arr_navn, t.arr_dato, t.arr_tid, t.arr_sted, t.arr_tekst, t.arr_frist
  from public.oppg_tavler t where p_token is not null and t.felles_token = p_token;
$f$;

-- Søk på navn (minst 3 tegn, maks 5 treff) som gir gjestens egen svarlenke
create or replace function public.oppg_felles_sok(p_token text, p_q text)
returns table(navn text, token text)
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
    select g.navn, r.token from public.oppg_gjester g join public.oppg_rsvp r on r.gjest_id = g.id
    where g.tavle_id = t and g.navn ilike '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%'
    order by g.navn limit 5;
end $f$;

-- Legg til en gjest som ikke står på listen (returnerer gjestens svarlenke-token)
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
    insert into public.oppg_gjester(tavle_id, navn, notat) values (t, n, 'Lagt til via felles lenke') returning id into gid;
  end if;
  insert into public.oppg_rsvp(gjest_id) select gid where not exists (select 1 from public.oppg_rsvp where gjest_id = gid);
  select r.token into tok from public.oppg_rsvp r where r.gjest_id = gid;
  return tok;
end $f$;

revoke execute on function public.oppg_felles_hent(text) from public;
revoke execute on function public.oppg_felles_sok(text, text) from public;
revoke execute on function public.oppg_felles_ny(text, text) from public;
grant execute on function public.oppg_felles_hent(text) to anon, authenticated;
grant execute on function public.oppg_felles_sok(text, text) to anon, authenticated;
grant execute on function public.oppg_felles_ny(text, text) to anon, authenticated;

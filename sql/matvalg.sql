-- Matvalg og allergier på svarsiden. Kjør i Supabase → SQL Editor FØR den nye appen merges.
-- Legger bare til kolonner og nye funksjoner. Eksisterende funksjoner og regler endres ikke.

alter table public.oppg_gjester add column if not exists matvalg text;
alter table public.oppg_gjester add column if not exists allergier text;
alter table public.oppg_tavler add column if not exists arr_meny text;

create or replace function public.oppg_rsvp_hent3(p_token text)
returns table(navn text, antall integer, status text, melding text, tavle_navn text, arr_navn text, arr_dato date, arr_tid text, arr_sted text, arr_tekst text, arr_frist date, matvalg text, allergier text, arr_meny text)
language sql security definer set search_path to 'public'
as $f$
  select g.navn, g.antall, g.status, g.svar_melding, t.navn, t.arr_navn, t.arr_dato, t.arr_tid, t.arr_sted, t.arr_tekst, t.arr_frist, g.matvalg, g.allergier, t.arr_meny
  from public.oppg_rsvp r join public.oppg_gjester g on g.id = r.gjest_id join public.oppg_tavler t on t.id = g.tavle_id
  where r.token = p_token;
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
    from public.oppg_rsvp r
   where r.gjest_id = g.id and r.token = p_token;
  get diagnostics n = row_count;
  return n > 0;
end $f$;

revoke execute on function public.oppg_rsvp_hent3(text) from public;
revoke execute on function public.oppg_rsvp_svar2(text,text,integer,text,text,text) from public;
grant execute on function public.oppg_rsvp_hent3(text) to anon, authenticated;
grant execute on function public.oppg_rsvp_svar2(text,text,integer,text,text,text) to anon, authenticated;

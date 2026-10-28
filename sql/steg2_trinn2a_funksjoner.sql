-- Steg 2, trinn 2 del A: nye funksjoner. Endrer ingen eksisterende regler. Kjør i Supabase → SQL Editor.

-- Finner tavle-id fra en lagringssti som «<tavle-id>/<fil>.jpg» (null hvis stien ikke er på det formatet)
create or replace function public.oppg_sti_tavle(p_sti text)
returns uuid language plpgsql immutable set search_path to 'public'
as $f$
begin
  return (string_to_array(p_sti, '/'))[1]::uuid;
exception when others then
  return null;
end $f$;

-- Lag en tavle med standardkolonner. Den som lager den blir eier.
create or replace function public.oppg_lag_tavle(p_navn text)
returns setof public.oppg_tavler
language plpgsql security definer set search_path to 'public'
as $f$
declare t public.oppg_tavler; n integer;
begin
  if auth.uid() is null then raise exception 'Ikke innlogget'; end if;
  if length(trim(coalesce(p_navn,''))) < 1 or length(trim(p_navn)) > 60 then raise exception 'Navn må være 1–60 tegn'; end if;
  select count(*) into n from public.oppg_tavler x where public.oppg_er_medlem(x.id);
  insert into public.oppg_tavler(navn, posisjon) values (trim(p_navn), n) returning * into t;
  insert into public.oppg_medlemmer(tavle_id, user_id, rolle) values (t.id, auth.uid(), 'eier') on conflict do nothing;
  insert into public.oppg_kolonner(tavle_id, tittel, posisjon) values (t.id, 'Å gjøre', 1000), (t.id, 'Pågår', 2000), (t.id, 'Ferdig', 3000);
  return next t;
end $f$;

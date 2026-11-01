-- Faste plasser ved bord. Kjør i Supabase → SQL Editor FØR den nye appen merges.
-- Legger bare til én kolonne. Tom verdi betyr «automatisk plass», slik som før.
alter table public.oppg_gjester add column if not exists plass integer;

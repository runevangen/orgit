-- Merking av sendte invitasjoner og påminnelser. Legger bare til to kolonner.
alter table public.oppg_gjester add column if not exists invitert_tid timestamptz;
alter table public.oppg_gjester add column if not exists paminnet_tid timestamptz;

-- Program / tidslinje for dagen. Kjøres én gang.
create table if not exists public.oppg_program (
  id uuid primary key default gen_random_uuid(),
  tavle_id uuid not null references public.oppg_tavler(id) on delete cascade,
  tid text not null default '12:00',
  varighet integer,
  tittel text not null,
  ansvarlig text,
  notat text,
  opprettet timestamptz not null default now()
);
create index if not exists oppg_program_tavle on public.oppg_program(tavle_id);
alter table public.oppg_program enable row level security;
drop policy if exists oppg_medlem_alt on public.oppg_program;
create policy oppg_medlem_alt on public.oppg_program for all to authenticated
  using (public.oppg_er_medlem(tavle_id)) with check (public.oppg_er_medlem(tavle_id));

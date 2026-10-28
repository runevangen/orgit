-- Steg 2, trinn 2 del B: BRYTEREN. Fra nå krever alle data at du er innlogget og medlem av tavlen.
-- Kjør først etter at del A er kjørt og den nye appen er oppdatert og testet. Kan angres med steg2_tilbakestill.sql.

-- 1) Fjern de åpne reglene
drop policy if exists oppg_tavler_alle on public.oppg_tavler;
drop policy if exists oppg_kolonner_alle on public.oppg_kolonner;
drop policy if exists oppg_kort_alle on public.oppg_kort;
drop policy if exists oppg_aktivitet_alle on public.oppg_aktivitet;
drop policy if exists oppg_vedlegg_alle on public.oppg_vedlegg;
drop policy if exists oppg_gjester_alle on public.oppg_gjester;
drop policy if exists oppg_bord_alle on public.oppg_bord;
drop policy if exists oppg_grupper_alle on public.oppg_grupper;
drop policy if exists oppg_bordtyper_alle on public.oppg_bordtyper;
drop policy if exists oppg_relasjoner_alle on public.oppg_relasjoner;
drop policy if exists oppg_elementer_alle on public.oppg_elementer;

-- 2) Medlemsregler: tavler
drop policy if exists oppg_medlem_les on public.oppg_tavler;
drop policy if exists oppg_medlem_endre on public.oppg_tavler;
drop policy if exists oppg_eier_slett on public.oppg_tavler;
create policy oppg_medlem_les on public.oppg_tavler for select to authenticated using (public.oppg_er_medlem(id));
create policy oppg_medlem_endre on public.oppg_tavler for update to authenticated using (public.oppg_er_medlem(id)) with check (public.oppg_er_medlem(id));
create policy oppg_eier_slett on public.oppg_tavler for delete to authenticated using (public.oppg_rolle(id) = 'eier');

-- 3) Medlemsregler: alt som hører til en tavle
drop policy if exists oppg_medlem_alt on public.oppg_kolonner;
create policy oppg_medlem_alt on public.oppg_kolonner for all to authenticated using (public.oppg_er_medlem(tavle_id)) with check (public.oppg_er_medlem(tavle_id));
drop policy if exists oppg_medlem_alt on public.oppg_kort;
create policy oppg_medlem_alt on public.oppg_kort for all to authenticated using (public.oppg_er_medlem(tavle_id)) with check (public.oppg_er_medlem(tavle_id));
drop policy if exists oppg_medlem_alt on public.oppg_aktivitet;
create policy oppg_medlem_alt on public.oppg_aktivitet for all to authenticated using (public.oppg_er_medlem(tavle_id)) with check (public.oppg_er_medlem(tavle_id));
drop policy if exists oppg_medlem_alt on public.oppg_vedlegg;
create policy oppg_medlem_alt on public.oppg_vedlegg for all to authenticated using (public.oppg_er_medlem(tavle_id)) with check (public.oppg_er_medlem(tavle_id));
drop policy if exists oppg_medlem_alt on public.oppg_gjester;
create policy oppg_medlem_alt on public.oppg_gjester for all to authenticated using (public.oppg_er_medlem(tavle_id)) with check (public.oppg_er_medlem(tavle_id));
drop policy if exists oppg_medlem_alt on public.oppg_bord;
create policy oppg_medlem_alt on public.oppg_bord for all to authenticated using (public.oppg_er_medlem(tavle_id)) with check (public.oppg_er_medlem(tavle_id));
drop policy if exists oppg_medlem_alt on public.oppg_grupper;
create policy oppg_medlem_alt on public.oppg_grupper for all to authenticated using (public.oppg_er_medlem(tavle_id)) with check (public.oppg_er_medlem(tavle_id));
drop policy if exists oppg_medlem_alt on public.oppg_bordtyper;
create policy oppg_medlem_alt on public.oppg_bordtyper for all to authenticated using (public.oppg_er_medlem(tavle_id)) with check (public.oppg_er_medlem(tavle_id));
drop policy if exists oppg_medlem_alt on public.oppg_relasjoner;
create policy oppg_medlem_alt on public.oppg_relasjoner for all to authenticated using (public.oppg_er_medlem(tavle_id)) with check (public.oppg_er_medlem(tavle_id));
drop policy if exists oppg_medlem_alt on public.oppg_elementer;
create policy oppg_medlem_alt on public.oppg_elementer for all to authenticated using (public.oppg_er_medlem(tavle_id)) with check (public.oppg_er_medlem(tavle_id));

-- 4) Bildelagring: privat, kun medlemmer av tavlen (første mappe i stien er tavle-id)
update storage.buckets set public = false where id = 'oppg-bilder';
drop policy if exists oppg_bilder_les on storage.objects;
drop policy if exists oppg_bilder_skriv on storage.objects;
drop policy if exists oppg_bilder_slett on storage.objects;
create policy oppg_bilder_les on storage.objects for select to authenticated
  using (bucket_id = 'oppg-bilder' and public.oppg_er_medlem(public.oppg_sti_tavle(name)));
create policy oppg_bilder_skriv on storage.objects for insert to authenticated
  with check (bucket_id = 'oppg-bilder' and public.oppg_er_medlem(public.oppg_sti_tavle(name)));
create policy oppg_bilder_slett on storage.objects for delete to authenticated
  using (bucket_id = 'oppg-bilder' and public.oppg_er_medlem(public.oppg_sti_tavle(name)));

-- 5) Fjern gamle åpne funksjoner (PIN-innlogging m.m.). Svarsiden for gjester bruker oppg_rsvp_hent2/oppg_rsvp_svar og er uberørt.
revoke execute on function public.oppg_brukere_liste() from public, anon, authenticated;
revoke execute on function public.oppg_logg_inn(text,text) from public, anon, authenticated;
revoke execute on function public.oppg_ny_bruker2(text,text,text,text) from public, anon, authenticated;
revoke execute on function public.oppg_ny_bruker(text,text,text,text,text) from public, anon, authenticated;
revoke execute on function public.oppg_invitasjonskode(text,text,text) from public, anon, authenticated;
revoke execute on function public.oppg_rsvp_lenker(text,text,uuid) from public, anon, authenticated;
revoke execute on function public.oppg_rsvp_hent(text) from public, anon, authenticated;

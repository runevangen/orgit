-- Tilbakestill steg 2 trinn 2 del B: gjenoppretter de åpne reglene, offentlig bildelagring og gamle funksjoner.
-- Bruk bare hvis noe går galt etter bryteren.

drop policy if exists oppg_medlem_les on public.oppg_tavler;
drop policy if exists oppg_medlem_endre on public.oppg_tavler;
drop policy if exists oppg_eier_slett on public.oppg_tavler;
drop policy if exists oppg_medlem_alt on public.oppg_kolonner;
drop policy if exists oppg_medlem_alt on public.oppg_kort;
drop policy if exists oppg_medlem_alt on public.oppg_aktivitet;
drop policy if exists oppg_medlem_alt on public.oppg_vedlegg;
drop policy if exists oppg_medlem_alt on public.oppg_gjester;
drop policy if exists oppg_medlem_alt on public.oppg_bord;
drop policy if exists oppg_medlem_alt on public.oppg_grupper;
drop policy if exists oppg_medlem_alt on public.oppg_bordtyper;
drop policy if exists oppg_medlem_alt on public.oppg_relasjoner;
drop policy if exists oppg_medlem_alt on public.oppg_elementer;

drop policy if exists oppg_tavler_alle on public.oppg_tavler;
create policy oppg_tavler_alle on public.oppg_tavler for all to anon, authenticated using (true) with check (true);
drop policy if exists oppg_kolonner_alle on public.oppg_kolonner;
create policy oppg_kolonner_alle on public.oppg_kolonner for all to anon, authenticated using (true) with check (true);
drop policy if exists oppg_kort_alle on public.oppg_kort;
create policy oppg_kort_alle on public.oppg_kort for all to anon, authenticated using (true) with check (true);
drop policy if exists oppg_aktivitet_alle on public.oppg_aktivitet;
create policy oppg_aktivitet_alle on public.oppg_aktivitet for all to anon, authenticated using (true) with check (true);
drop policy if exists oppg_vedlegg_alle on public.oppg_vedlegg;
create policy oppg_vedlegg_alle on public.oppg_vedlegg for all to anon, authenticated using (true) with check (true);
drop policy if exists oppg_gjester_alle on public.oppg_gjester;
create policy oppg_gjester_alle on public.oppg_gjester for all to anon, authenticated using (true) with check (true);
drop policy if exists oppg_bord_alle on public.oppg_bord;
create policy oppg_bord_alle on public.oppg_bord for all to anon, authenticated using (true) with check (true);
drop policy if exists oppg_grupper_alle on public.oppg_grupper;
create policy oppg_grupper_alle on public.oppg_grupper for all to anon, authenticated using (true) with check (true);
drop policy if exists oppg_bordtyper_alle on public.oppg_bordtyper;
create policy oppg_bordtyper_alle on public.oppg_bordtyper for all to anon, authenticated using (true) with check (true);
drop policy if exists oppg_relasjoner_alle on public.oppg_relasjoner;
create policy oppg_relasjoner_alle on public.oppg_relasjoner for all to anon, authenticated using (true) with check (true);
drop policy if exists oppg_elementer_alle on public.oppg_elementer;
create policy oppg_elementer_alle on public.oppg_elementer for all to anon, authenticated using (true) with check (true);

update storage.buckets set public = true where id = 'oppg-bilder';
drop policy if exists oppg_bilder_les on storage.objects;
drop policy if exists oppg_bilder_skriv on storage.objects;
drop policy if exists oppg_bilder_slett on storage.objects;
create policy oppg_bilder_les on storage.objects for select to anon, authenticated using (bucket_id = 'oppg-bilder');
create policy oppg_bilder_skriv on storage.objects for insert to anon, authenticated with check (bucket_id = 'oppg-bilder');
create policy oppg_bilder_slett on storage.objects for delete to anon, authenticated using (bucket_id = 'oppg-bilder');

grant execute on function public.oppg_brukere_liste() to anon, authenticated;
grant execute on function public.oppg_logg_inn(text,text) to anon, authenticated;
grant execute on function public.oppg_ny_bruker2(text,text,text,text) to anon, authenticated;
grant execute on function public.oppg_invitasjonskode(text,text,text) to anon, authenticated;
grant execute on function public.oppg_rsvp_lenker(text,text,uuid) to anon, authenticated;

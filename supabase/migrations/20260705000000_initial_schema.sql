-- Shared book digests: text generated once via the generate-digest edge
-- function, audio synthesized once with a fixed voice. Clients are read-only
-- (SELECT policies only); all writes go through the edge function's service
-- role, which bypasses RLS.

create table public.digests (
  book_id           text primary key check (book_id ~ '^[a-z0-9][a-z0-9-]{0,79}$'),
  title             text not null check (char_length(title) <= 300),
  author            text not null check (char_length(author) <= 200),
  angle             text not null default '' check (char_length(angle) <= 2000),
  status            text not null default 'pending'
                      check (status in ('pending', 'generating', 'ready', 'failed')),
  digest_text       text,
  error             text,
  model             text,
  audio_status      text not null default 'pending'
                      check (audio_status in ('pending', 'generating', 'ready', 'failed')),
  audio_storage_path text,
  audio_error       text,
  audio_claim_expires_at timestamptz,
  created_by        uuid references auth.users (id) on delete set null,
  claim_expires_at  timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create table public.generation_requests (
  id         bigint generated always as identity primary key,
  user_id    uuid not null,
  book_id    text not null,
  kind       text not null check (kind in ('digest', 'audio')),
  created_at timestamptz not null default now()
);

create index generation_requests_user_created_idx
  on public.generation_requests (user_id, created_at);

alter table public.digests enable row level security;
alter table public.generation_requests enable row level security;

-- Signed-in clients (anonymous sessions carry the `authenticated` role) may
-- read digests. No insert/update/delete policies exist on any table, so
-- clients cannot write. generation_requests has no policies at all:
-- service-role only.
create policy "authenticated read digests"
  on public.digests for select
  to authenticated
  using (true);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger digests_set_updated_at
  before update on public.digests
  for each row execute function public.set_updated_at();

-- Atomic claim for digest text generation. Returns exactly one row:
--   outcome = 'claimed'     -> caller must run the generation job
--   outcome = 'ready'       -> digest already exists
--   outcome = 'in_progress' -> someone else holds a live claim
create or replace function public.claim_digest(
  p_book_id text,
  p_title   text,
  p_author  text,
  p_angle   text,
  p_user    uuid
) returns table (outcome text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claimed boolean;
  v_status text;
begin
  insert into public.digests as d (book_id, title, author, angle, status, created_by, claim_expires_at)
  values (p_book_id, p_title, p_author, p_angle, 'generating', p_user, now() + interval '15 minutes')
  on conflict (book_id) do update
    set status = 'generating',
        error = null,
        claim_expires_at = now() + interval '15 minutes',
        created_by = coalesce(d.created_by, excluded.created_by)
    where d.status in ('pending', 'failed')
       or (d.status = 'generating' and d.claim_expires_at < now())
  returning true into v_claimed;

  if v_claimed then
    return query select 'claimed'::text;
    return;
  end if;

  select d.status into v_status from public.digests d where d.book_id = p_book_id;

  if v_status = 'ready' then
    return query select 'ready'::text;
  else
    return query select 'in_progress'::text;
  end if;
end;
$$;

-- Atomic claim for audio generation on an existing ready digest.
-- Outcomes: 'claimed' | 'ready' | 'in_progress' | 'no_digest'.
create or replace function public.claim_audio(
  p_book_id text,
  p_user    uuid
) returns table (outcome text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claimed boolean;
  v_audio_status text;
begin
  update public.digests d
    set audio_status = 'generating',
        audio_error = null,
        audio_claim_expires_at = now() + interval '15 minutes'
    where d.book_id = p_book_id
      and d.status = 'ready'
      and (d.audio_status in ('pending', 'failed')
           or (d.audio_status = 'generating' and d.audio_claim_expires_at < now()))
  returning true into v_claimed;

  if v_claimed then
    return query select 'claimed'::text;
    return;
  end if;

  select d.audio_status into v_audio_status
  from public.digests d
  where d.book_id = p_book_id and d.status = 'ready';

  if v_audio_status is null then
    return query select 'no_digest'::text;
  elsif v_audio_status = 'ready' then
    return query select 'ready'::text;
  else
    return query select 'in_progress'::text;
  end if;
end;
$$;

-- Claim RPCs are for the edge function (service role) only.
revoke execute on function public.claim_digest(text, text, text, text, uuid) from public, anon, authenticated;
revoke execute on function public.claim_audio(text, uuid) from public, anon, authenticated;

-- Private bucket for the shared MP3s; clients read via signed URLs
-- (authenticated SELECT), writes are service-role only.
insert into storage.buckets (id, name, public)
values ('digest-audio', 'digest-audio', false);

create policy "authenticated read digest audio"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'digest-audio');

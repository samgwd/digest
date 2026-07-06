-- Digest generation moves to OpenAI background mode: the edge function starts
-- a background response and stores its id here, then any later `check` call
-- (from any invocation) polls OpenAI and writes the finished text. No isolate
-- has to outlive the generation, so rows can no longer be stranded in
-- 'generating' by a killed function.

alter table public.digests
  add column openai_response_id text;

-- Same claim logic as before, but a re-claim must clear the previous
-- attempt's response id so pollers can't collect a stale response.
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
        openai_response_id = null,
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

revoke execute on function public.claim_digest(text, text, text, text, uuid) from public, anon, authenticated;

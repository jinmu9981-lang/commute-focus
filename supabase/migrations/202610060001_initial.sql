-- Run once using the Supabase SQL editor or `supabase db push`.
begin;

create sequence public.record_revision_seq;
create table public.records (
    owner_id uuid not null references auth.users(id) on delete cascade,
    id uuid not null,
    kind text not null check (kind in ('task', 'step', 'journey', 'focus', 'preferences')),
    payload jsonb not null check (jsonb_typeof(payload) = 'object'),
    deleted boolean not null default false,
    mutation_id uuid not null,
    revision bigint not null default nextval('public.record_revision_seq'),
    updated_at timestamptz not null default clock_timestamp(),
    primary key (owner_id, id),
    check (octet_length(payload::text) <= 65536)
);
create index records_owner_revision on public.records(owner_id, revision);
alter table public.records enable row level security;
create policy records_read_own on public.records for select to authenticated
    using (owner_id = (select auth.uid()));
revoke all on public.records from anon, authenticated;
grant select on public.records to authenticated;
revoke all on public.record_revision_seq from anon, authenticated;

-- Durable receipts make a retried mutation a no-op even if another device has
-- subsequently edited the same row. Receipts stay for the life of the account.
create table public.mutation_receipts (
    owner_id uuid not null references auth.users(id) on delete cascade,
    mutation_id uuid not null,
    record_id uuid not null,
    primary key(owner_id, mutation_id)
);
alter table public.mutation_receipts enable row level security;
revoke all on public.mutation_receipts from anon, authenticated;

create or replace function public.apply_changes(changes jsonb)
returns setof public.records
language plpgsql security definer set search_path = ''
as $$
declare
    uid uuid := auth.uid();
    item jsonb;
    v_record_id uuid;
    mutation uuid;
    existing public.records%rowtype;
    inserted integer;
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    if jsonb_typeof(changes) <> 'array' or jsonb_array_length(changes) > 100 then
        raise exception 'Expected at most 100 changes';
    end if;
    -- Serialize submissions per account; the later submission wins for mutable
    -- records. An offline retry cannot resurrect a tombstone or replay history.
    perform pg_advisory_xact_lock(hashtextextended(uid::text, 0));
    for item in select value from jsonb_array_elements(changes)
    loop
        v_record_id := (item->>'id')::uuid;
        mutation := (item->>'mutation_id')::uuid;
        if v_record_id is null or mutation is null or item->>'kind' is null
           or item->'payload' is null or item->>'deleted' is null then
            raise exception 'Missing record fields';
        end if;
        if item->>'kind' not in ('task','step','journey','focus','preferences') then
            raise exception 'Invalid record kind';
        end if;
        if item->>'kind' <> 'preferences' and (item->'payload'->>'id')::uuid is distinct from v_record_id then
            raise exception 'Payload ID does not match record ID';
        end if;
        insert into public.mutation_receipts(owner_id, mutation_id, record_id)
            values(uid, mutation, v_record_id) on conflict do nothing;
        get diagnostics inserted = row_count;
        if inserted = 0 then
            if exists(select 1 from public.mutation_receipts r
                      where r.owner_id = uid and r.mutation_id = mutation and r.record_id <> v_record_id) then
                raise exception 'Mutation ID already belongs to another record';
            end if;
            return query select r.* from public.records r where r.owner_id = uid and r.id = v_record_id;
            continue;
        end if;

        select r.* into existing from public.records r where r.owner_id = uid and r.id = v_record_id;
        if found then
            if existing.kind <> item->>'kind' then raise exception 'Record kind is immutable'; end if;
            -- Immutable history and permanent tombstones win over later edits.
            if not existing.deleted and existing.kind <> 'focus' then
                update public.records r set
                    payload = item->'payload', deleted = (item->>'deleted')::boolean,
                    mutation_id = mutation, revision = nextval('public.record_revision_seq'),
                    updated_at = clock_timestamp()
                where r.owner_id = uid and r.id = v_record_id;
            end if;
        else
            insert into public.records(owner_id, id, kind, payload, deleted, mutation_id)
                values(uid, v_record_id, item->>'kind', item->'payload', (item->>'deleted')::boolean, mutation);
        end if;
        return query select r.* from public.records r where r.owner_id = uid and r.id = v_record_id;
    end loop;
end;
$$;
revoke all on function public.apply_changes(jsonb) from public, anon;
grant execute on function public.apply_changes(jsonb) to authenticated;

commit;

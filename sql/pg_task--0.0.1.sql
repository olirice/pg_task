-----------------
-- Persistence -- 
-----------------
create type @extschema@.queue_strategy as enum ('FIFO');
create type @extschema@.retry_strategy as enum ('CONSTANT', 'EXPONENTIAL');
create type @extschema@.task_status as enum ('PENDING', 'RUNNING', 'COMPLETED');
create type @extschema@.attempt_status as enum ('SUCCESS', 'FAILURE');

-- Pattern:  Standard
-- Est Rows: < 50
create table @extschema@.queue (
    id smallserial primary key,
    name text not null unique,
    strategy queue_strategy not null default 'FIFO',
    created_at timestamp not null default timezone('utc', now())
);
insert into @extschema@.queue(name) values ('default');


-- Pattern:  Standard
-- Est Rows: < 150
create table @extschema@.task_definition (
    id smallserial primary key,
    name text not null unique,
    default_queue_id smallint not null references @extschema@.queue(id) default 1,
    retries integer not null default 0,
    retry_strategy @extschema@.retry_strategy not null default 'EXPONENTIAL',
    retry_delay interval not null default '1 second',
    created_at timestamp not null default timezone('utc', now())
);


-- Pattern:  Standard (updates once per attempt)
-- Est Rows: > 1M 
create table @extschema@.task (
    id bigserial primary key,
    queue_id smallint not null references @extschema@.queue(id) on delete cascade,
    task_definition_id smallint not null references @extschema@.task_definition(id),
    after timestamp not null default timezone('utc', now()),
    status @extschema@.task_status not null default 'PENDING'
);
create index ix_task_acquire on @extschema@.task (queue_id, after) where (status = 'PENDING');


-- Pattern:  Append Only
-- Est Rows: > 1M
create table @extschema@.task_params (
    id bigserial primary key,
    task_id smallint not null unique references @extschema@.task(id) on delete cascade,
    params jsonb not null default '{}',
    -- Doubles as created_at for task table
    created_at timestamp not null default timezone('utc', now())
);


-- Pattern: Append Only
-- Est Rows: > 1M
create table @extschema@.attempt (
    id bigserial primary key,
    task_id bigint not null references @extschema@.task(id) on delete cascade,
    created_at timestamp not null default timezone('utc', now())
);


-- Pattern: Append Only
-- Est Rows: > 1M
create table @extschema@.attempt_result (
    id bigserial primary key,
    attempt_id smallint not null references @extschema@.attempt(id) on delete cascade,
    result @extschema@.attempt_status not null,
    context jsonb not null default '{}',
    created_at timestamp not null default timezone('utc', now())
);


-- Pattern: Type Only (clients may have difficulty with composite types
-- Est Rows: 0
create table @extschema@.acquired_task (
    task_name text primary key,
    params jsonb not null
);

----------------
-- Operations --
----------------


create function @extschema@.upsert_queue(
    name text,
    strategy @extschema@.queue_strategy default 'FIFO'
)
returns smallint as
$$
    insert into @extschema@.queue(name, strategy)
    values (name, strategy)
    on conflict (name) do update
    set strategy = EXCLUDED.strategy
    returning id
$$ language sql;


create function @extschema@.upsert_task_definition(
    name text,
    default_queue_name text default 'default',
    retries integer default 0,
    retry_strategy @extschema@.retry_strategy default 'EXPONENTIAL',
    retry_delay interval default '10 seconds'
)
returns integer as
$$
    insert into @extschema@.task_definition(
        name,
        default_queue_id,
        retries,
        retry_strategy,
        retry_delay
    )
    values (
        name,
        (select id from @extschema@.queue where name = default_queue_name limit 1),
        retries,
        retry_strategy,
        retry_delay
    )
    on conflict (name) do nothing
    returning id
;
$$ language sql;


-- Idempotent: true
create function @extschema@.enqueue_task(
    task_name text,
    params jsonb default '{}',
    after timestamp default null,
    queue_name text default null
)
returns bigint as
$$
    -- if queue_name is null, lookup from task_definition
    -- if after is null, use timestamp('utc', now())
    select 1;
$$ language sql;

create function @extschema@.acquire_task(queue_name text default 'default')
returns @extschema@.acquired_task as
$$
#variable_conflict use_column
<<decl>>
declare
    task @extschema@.task;
    attempt_id bigint;
begin
    -- Highest priorty is speed of this select
    select
        *
    into
        decl.task
    from
        @extschema@.task t
    where
        t.queue_id = (select q.id from @extschema@.queue q where name = queue_name)
        and t.after < timezone('utc', now())
        and t.status='PENDING'
    limit
        1
    for update skip locked;

    -- Exit early if no work exists
    if decl.task is null -- todo check syntax
        then return null;
    end if;

    -- Some work exists
    attempt_id := insert into @extschema@.attempt(task_id) values (decl.task.id) returning id;

    -- Set attmpt_id in transaction local config for reference in `release_task`
    select set_config('pg_task.attempt_id', attempt_id::text, true);

    -- Populate and return an acquired_task record 
    return select
        (select name from @extschema@.task_definition where id = decl.task.task_definition_id limit 1) task_name,
        tp.params,
    from
        @extschema.task_params tp
    where
        tp.task_id = decl.task.id;
end;
$$ language plpgsql strict;

-- TODO
create function @extschema@.release_task(result @extschema@.attempt_status, context jsonb default '{}')
returns boolean as
$$
#variable_conflict use_column
<<decl>>
declare
    result alias for $1;
    context alias for $2;
    attempt_id bigint := current_setting('pg_task.attempt_id', false);
    task_id bigint;
begin
    insert into @extschema@.attempt_result(attempt_id, result, context)
    values (decl.attempt_id, decl.result, decl.context);

    decl.task_id := select task_id from @extschema@.attempt where id = decl.attempt_id limit 1;

    if decl.result = 'SUCCESS' then
        update @extschema@.task set status = 'COMPLETE' where id = decl.task_id;
    end if;

    if decl.result = 'FAILURE' then
        -- TODO handle retries here
        select 1;
    end if;

end;

$$ language sql;


----------------
-- Monitoring --
----------------


















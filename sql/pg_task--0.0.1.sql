-----------------
-- Persistence -- 
-----------------
create type @extschema@.queue_strategy as enum ('FIFO');
create type @extschema@.retry_strategy as enum ('CONSTANT');
create type @extschema@.task_status as enum ('PENDING', 'RUNNING', 'FINISHED');
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
    retry_strategy @extschema@.retry_strategy not null default 'CONSTANT',
    retry_delay interval not null default '1 second',
    -- TODO retention_policy interval not null default '90 days',
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
    task_id bigint primary key references @extschema@.task(id) on delete cascade,
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
    attempt_id bigint primary key references @extschema@.attempt(id) on delete cascade,
    result @extschema@.attempt_status not null,
    context jsonb not null default '{}',
    created_at timestamp not null default timezone('utc', now())
);


-- Pattern: Type Only (clients may have difficulty with composite types
-- Est Rows: 0
create table @extschema@.acquired_task (
    task_id bigint primary key references @extschema@.task(id),
    task_name text not null,
    attempt_id bigint not null references @extschema@.attempt(id),
    params jsonb not null
);
-- TODO add task_id and attempt_id

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
    retry_strategy @extschema@.retry_strategy default 'CONSTANT',
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
    queue_name text default 'default'
)
returns bigint as
$$
#variable_conflict use_column
<<decl>>
declare
    task_def @extschema@.task_definition;
    queue @extschema@.queue;
    after alias for $3;
    task_id bigint;
begin

    -- Reference to task definition
    select
        *
    into
        decl.task_def
    from
        @extschema@.task_definition td
    where
        td.name = task_name;

    if decl.task_def is null then
        insert into @extschema@.task_definition(name)
        values (task_name)
        returning *
        into decl.task_def;
    end if;

    -- Reference to queue
    select
        *
    into
        decl.queue
    from
        @extschema@.queue q
    where
        q.name = queue_name;

    if decl.queue is null then
        raise exception 'queue %s does not exist', queue_name;
    end if;

    insert into @extschema@.task (queue_id, task_definition_id, after)
    values (queue.id, task_def.id, decl.after)
    returning id
    into decl.task_id;

    insert into @extschema@.task_params(task_id, params)
    values (decl.task_id, params);

    return task_id;
end;
$$ language plpgsql;


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
        and t.after <= timezone('utc', now())
        and t.status='PENDING'
    limit
        1
    for update skip locked;

    -- Exit early if no work exists
    if decl.task is null
        then return null;
    end if;

    -- Some work exists
    insert into @extschema@.attempt(task_id) values (decl.task.id) returning id into decl.attempt_id;

    -- Set attmpt_id in transaction local config for reference in `release_task`
    perform
        set_config('pg_task.task.id', decl.task.id::text, true),
        set_config('pg_task.task.task_definition_id', decl.task.task_definition_id::text, true),
        set_config('pg_task.attempt.id', decl.attempt_id::text, true);

    -- Populate and return an acquired_task record 
    return
        (
            decl.task.id,
            (select name from @extschema@.task_definition where id = decl.task.task_definition_id limit 1),
            decl.attempt_id,
            tp.params
        )::@extschema@.acquired_task
    from
        @extschema@.task_params tp
    where
        tp.task_id = decl.task.id;
end;
$$ language plpgsql strict;


create function @extschema@.next_retry_after(
    current_after timestamp,
    retry_strategy @extschema@.retry_strategy,
    retry_interval interval
)
returns timestamp as
$$
#variable_conflict use_column
<<decl>>
begin
    -- TODO
    if retry_strategy = 'CONSTANT' then
        return timezone('utc', now()) + retry_interval;
    end if;

    raise exception 'Unknown retry strategy %', retry_strategy::text;
end;
$$ language plpgsql;


create function @extschema@.release_task(result @extschema@.attempt_status, context jsonb default '{}')
returns bigint as
$$
#variable_conflict use_column
<<decl>>
declare
    result alias for $1;
    context alias for $2;
    attempt_id bigint := current_setting('pg_task.attempt.id', false);
    task_id bigint := current_setting('pg_task.task.id', false);
    task_def_id bigint := current_setting('pg_task.task.task_definition_id', false);
   -- task @extschema@.task;
    task_def @extschema@.task_definition;
begin
    insert into @extschema@.attempt_result(attempt_id, result, context)
    values (decl.attempt_id, decl.result, decl.context);

    if decl.result = 'SUCCESS' then
        update @extschema@.task
        set status = 'FINISHED'
        where id = decl.task_id;

        return decl.task_id;
    end if;

    if decl.result = 'FAILURE' then
        -- Update `after` timestamp using rules defined on task_definition
        select *
        from @extschema@.task_definition td
        where td.id = decl.task_def_id
        into decl.task_def;

        update @extschema@.task
        set after = @extschema@.next_retry_after(
            timezone('utc', now()),
            decl.task_def.retry_strategy,
            decl.task_def.retry_delay
        )
        where id = decl.task_id;

        return decl.task_id;
    end if;

    raise exception 'Unknown result attempt status %', result::text;
end;

$$ language plpgsql;


----------------
-- Monitoring --
----------------

-- TODO

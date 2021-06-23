-- Create pg_task 
create schema ext;
create extension pg_task with schema ext;


-- default queue exists
select count(1) from ext.queue;

-- upsert_queue
begin;
    select ext.upsert_queue('heavy', 'FIFO') > 0;
rollback;

-- upsert_queue idempotent
begin;
    select ext.upsert_queue('heavy', 'FIFO') > 0;
    select ext.upsert_queue('heavy', 'FIFO') > 0;
    -- We made one queue, and there is one default queue
    select count(1) = 2 from ext.queue;
rollback;


-- upsert_task_definition
begin;
    select ext.upsert_task_definition('resize_image' ) > 0;
    select ext.upsert_task_definition('resize_image', 'default') > 0;
    select ext.upsert_task_definition(
        'resize_image',
        'default',
        3,
        'CONSTANT',
        '1 minute'
    ) > 0;
rollback;


-- enqueue and get task
begin;
    select ext.enqueue_task('resize_image', '{"height": 10}', timezone('utc', now()));
    select ext.acquire_task('default') = ('resize_image', '{"height": 10}')::ext.acquired_task;
rollback;


-- enqueue fail for queue does not exist
begin;
    -- Expected to fail
    select ext.enqueue_task('resize_image', '{}', timezone('utc', now()), 'other-DNE');
rollback;

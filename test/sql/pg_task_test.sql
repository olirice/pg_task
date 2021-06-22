-- Create pg_task 
create schema ext;
create extension pg_task with schema ext;


-- default queue exists
select * from ext.queue;

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

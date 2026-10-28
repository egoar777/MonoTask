\set ON_ERROR_STOP on
CREATE TEMP TABLE shared_test_results(name text);
GRANT INSERT, SELECT ON shared_test_results TO authenticated, anon;
CREATE FUNCTION pg_temp.check_test(ok boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAILED: %', label; END IF; INSERT INTO shared_test_results VALUES(label); END $$;
CREATE FUNCTION pg_temp.expect_failure(statement text, expected text, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN EXECUTE statement; EXCEPTION WHEN OTHERS THEN
        IF position(expected IN SQLERRM) > 0 THEN INSERT INTO shared_test_results VALUES(label); RETURN; END IF;
        RAISE EXCEPTION 'FAILED %: unexpected error %', label, SQLERRM;
    END;
    RAISE EXCEPTION 'FAILED %: statement unexpectedly succeeded', label;
END $$;

SET ROLE authenticated;
SET request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
INSERT INTO public.monotask_tasks(id, title) VALUES ('10000000-0000-0000-0000-000000000000','Private owner task');
SELECT public.monotask_shared_create_list('Shared project') AS list_id \gset
SELECT public.monotask_shared_create_invite(:'list_id')->>'code' AS invite \gset
SELECT pg_temp.check_test(length(:'invite') = 32, 'Invitation has a 128-bit random code');
SELECT pg_temp.check_test((SELECT count(*) FROM public.monotask_shared_lists) = 1, 'Owner can read list');
SELECT pg_temp.expect_failure('SELECT * FROM public.monotask_shared_invites', 'permission denied', 'Raw invitation storage is not readable by owners');
SELECT pg_temp.expect_failure(format('DELETE FROM public.monotask_shared_members WHERE list_id=%L', :'list_id'), 'permission denied', 'Direct owner membership writes are blocked');

SET ROLE anon;
SET request.jwt.claim.sub = '';
SELECT pg_temp.expect_failure('SELECT public.monotask_shared_snapshot()', 'permission denied', 'Anonymous snapshot is denied');
SELECT pg_temp.expect_failure('SELECT * FROM public.monotask_shared_tasks', 'permission denied', 'Anonymous task access is denied');
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_join(%L)', :'invite'), 'permission denied', 'Anonymous joins are denied');

SET ROLE authenticated;
SET request.jwt.claim.sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
SELECT pg_temp.check_test(jsonb_array_length(public.monotask_shared_snapshot()->'lists') = 0, 'Nonmember snapshot hides lists');
SELECT pg_temp.check_test((SELECT count(*) FROM public.monotask_shared_members) = 0, 'Nonmember cannot enumerate participants');
SELECT pg_temp.check_test((SELECT count(*) FROM public.monotask_tasks) = 0, 'Sharing never exposes private owner tasks');
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_create_invite(%L)', :'list_id'), 'SHARED_OWNER_REQUIRED', 'Nonmember cannot create invitations');
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_update_list(%L,%L,false)', :'list_id', 'Stolen'), 'SHARED_OWNER_REQUIRED', 'Nonmember cannot rename list');
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_save_task(%L,%L,0,%L,%L,false,false,null,%L,false)', :'list_id', '20000000-0000-0000-0000-000000000000', 'Hidden', '', '[]'), 'SHARED_FORBIDDEN', 'Nonmember cannot write tasks');
SELECT pg_temp.expect_failure('INSERT INTO public.monotask_shared_members(list_id,user_id,display_name) VALUES(gen_random_uuid(),auth.uid(),''Hack'')', 'permission denied', 'Client cannot grant itself membership');
SELECT pg_temp.check_test(public.monotask_shared_join(:'invite') = :'list_id'::uuid, 'Valid invitation joins list');
SELECT pg_temp.check_test(public.monotask_shared_join(:'invite') = :'list_id'::uuid, 'Join is idempotent for the accepting participant');
SELECT pg_temp.check_test(jsonb_array_length(public.monotask_shared_snapshot()->'members') = 2, 'Participant sees only list membership');
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_create_invite(%L)', :'list_id'), 'SHARED_OWNER_REQUIRED', 'Participant cannot invite others');
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_remove_member(%L,%L)', :'list_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 'SHARED_OWNER_CANNOT_LEAVE', 'Participant cannot remove owner');
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_save_task(%L,%L,0,%L,%L,false,false,%L,%L,false)', :'list_id', '20000000-0000-0000-0000-000000000000', 'Assigned', '', 'cccccccc-cccc-cccc-cccc-cccccccccccc', '[]'), 'SHARED_INVALID_ASSIGNEE', 'Assignee must be a list member');
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_save_task(%L,%L,0,%L,%L,false,false,null,%L,false)', :'list_id', '20000000-0000-0000-0000-000000000000', 'Malformed', '', '[{"id":"------------------------------------","title":1,"is_done":false}]'), 'SHARED_INVALID_SUBTASKS', 'Malformed subtasks are rejected');
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_save_task(%L,%L,null,%L,%L,false,false,null,%L,false)', :'list_id', '20000000-0000-0000-0000-000000000000', 'Bad revision', '', '[]'), 'SHARED_CONFLICT', 'Missing revision cannot bypass optimistic locking');
SELECT public.monotask_shared_save_task(:'list_id', '20000000-0000-0000-0000-000000000000', 0, 'Plan', 'Shared notes', false, true, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '[{"id":"30000000-0000-0000-0000-000000000000","title":"First step","is_done":false}]', false) AS task \gset
SELECT pg_temp.check_test((:'task'::jsonb->>'revision')::int = 1, 'New task starts at revision one');
SELECT pg_temp.check_test((SELECT count(*) FROM public.monotask_shared_tasks) = 1, 'Member can read a shared task');
SELECT pg_temp.expect_failure('UPDATE public.monotask_shared_tasks SET notes=''Bypass''', 'permission denied', 'Direct task writes cannot bypass revision checks');
SELECT public.monotask_shared_create_list('Separate project') AS separate_id \gset
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_save_task(%L,%L,1,%L,%L,false,false,null,%L,false)', :'separate_id', '20000000-0000-0000-0000-000000000000', 'Move', '', '[]'), 'SHARED_FORBIDDEN', 'Task IDs cannot be moved across lists');

SET request.jwt.claim.sub = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_join(%L)', :'invite'), 'SHARED_INVALID_INVITE', 'Consumed code cannot be accepted by another account');
SELECT pg_temp.check_test((SELECT count(*) FROM public.monotask_shared_tasks) = 0, 'Outsider cannot read shared tasks');
SELECT pg_temp.check_test((SELECT count(*) FROM public.monotask_tasks) = 0, 'Outsider cannot read private tasks');

SET request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
SELECT pg_temp.check_test(jsonb_array_length(public.monotask_shared_snapshot()->'tasks') = 1, 'Owner receives participant-created tasks');
SELECT public.monotask_shared_save_task(:'list_id', '20000000-0000-0000-0000-000000000000', 1, 'Plan', 'Owner edit', true, true, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '[{"id":"30000000-0000-0000-0000-000000000000","title":"First step","is_done":true}]', false) AS edited \gset
SELECT pg_temp.check_test((:'edited'::jsonb->>'revision')::int = 2 AND (:'edited'::jsonb->>'is_done')::boolean, 'Completion, notes and subtasks synchronize with a new revision');
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_remove_member(%L,%L)', :'list_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 'SHARED_OWNER_CANNOT_LEAVE', 'Owner cannot orphan a list');
SET request.jwt.claim.sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_save_task(%L,%L,1,%L,%L,false,false,null,%L,false)', :'list_id', '20000000-0000-0000-0000-000000000000', 'Stale title', '', '[]'), 'SHARED_CONFLICT', 'Stale writes cannot overwrite another participant');
SELECT pg_temp.check_test((SELECT notes FROM public.monotask_shared_tasks WHERE id='20000000-0000-0000-0000-000000000000') = 'Owner edit', 'Conflict preserves shared content');
SET request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
SELECT public.monotask_shared_create_invite(:'list_id')->>'code' AS spare_invite \gset
SELECT public.monotask_shared_remove_member(:'list_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
SELECT pg_temp.check_test((SELECT assignee_id IS NULL FROM public.monotask_shared_tasks WHERE id='20000000-0000-0000-0000-000000000000'), 'Removing participant clears task assignment');
SET request.jwt.claim.sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
SELECT pg_temp.check_test((SELECT count(*) FROM public.monotask_shared_tasks) = 0, 'Removed participant immediately loses task access');
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_join(%L)', :'spare_invite'), 'SHARED_INVALID_INVITE', 'Removed participant cannot return through an outstanding unused link');
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_join(%L)', :'invite'), 'SHARED_INVALID_INVITE', 'Removed participant cannot reuse an old invitation');
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_save_task(%L,%L,3,%L,%L,false,false,null,%L,false)', :'list_id', '20000000-0000-0000-0000-000000000000', 'Revoked write', '', '[]'), 'SHARED_FORBIDDEN', 'Removed participant cannot write offline edits back');

SET request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
SELECT public.monotask_shared_create_invite(:'list_id')->>'code' AS expired_invite \gset
RESET ROLE;
UPDATE public.monotask_shared_invites SET expires_at = now()-interval '1 second' WHERE used_at IS NULL;
SET ROLE authenticated;
SET request.jwt.claim.sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_join(%L)', :'expired_invite'), 'SHARED_INVALID_INVITE', 'Expired invitations do not grant access');
SET request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
SELECT public.monotask_shared_create_invite(:'list_id')->>'code' AS old_invite \gset
SELECT public.monotask_shared_create_invite(:'list_id')->>'code' AS new_invite \gset
SET request.jwt.claim.sub = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_join(%L)', :'old_invite'), 'SHARED_INVALID_INVITE', 'Creating a fresh invitation revokes the previous unused code');
SELECT public.monotask_shared_join(:'new_invite');
SELECT public.monotask_shared_remove_member(:'list_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
SELECT pg_temp.check_test(NOT EXISTS(SELECT 1 FROM public.monotask_shared_lists WHERE id=:'list_id'), 'Members can leave voluntarily');
SET request.jwt.claim.sub = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
SELECT public.monotask_shared_save_task(:'list_id','20000000-0000-0000-0000-000000000000',3,'Plan','Owner edit',true,true,null,'[]',true);
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_save_task(%L,%L,4,%L,%L,false,false,null,%L,false)', :'list_id', '20000000-0000-0000-0000-000000000000', 'Resurrect', '', '[]'), 'SHARED_DELETED', 'Deleted shared tasks cannot be silently resurrected');
SELECT public.monotask_shared_save_task(:'list_id','50000000-0000-0000-0000-000000000000',0,'Offline cancelled','',false,false,null,'[]',true);
SELECT pg_temp.expect_failure(format('SELECT public.monotask_shared_save_task(%L,%L,0,%L,%L,false,false,null,%L,false)', :'list_id', '50000000-0000-0000-0000-000000000000', 'Delayed create', '', '[]'), 'SHARED_DELETED', 'Offline deletion before creation prevents a delayed request from resurrecting the task');
SELECT pg_temp.check_test((public.monotask_shared_save_task(:'list_id','50000000-0000-0000-0000-000000000000',0,'Offline cancelled','',false,false,null,'[]',true)->>'revision')::int=1, 'Replayed deletion is idempotent');
SELECT public.monotask_shared_update_list(:'list_id','Shared project',true);
SELECT pg_temp.check_test(NOT EXISTS(SELECT 1 FROM public.monotask_shared_lists WHERE id=:'list_id'), 'Deleted lists disappear from owner reads');
SELECT pg_temp.check_test((SELECT count(*) FROM public.monotask_tasks) = 1, 'Deleting a shared list preserves private tasks');
RESET ROLE;
SELECT count(*) AS passed_shared_security_checks FROM shared_test_results;

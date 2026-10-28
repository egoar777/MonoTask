-- Optional SQL Editor smoke test. All list/task writes are rolled back.
BEGIN;
DO $$ DECLARE v_user uuid; BEGIN
    SELECT id INTO v_user FROM auth.users ORDER BY created_at LIMIT 1;
    IF v_user IS NULL THEN RAISE EXCEPTION 'A registered account is required for this smoke test'; END IF;
    PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user, 'role', 'authenticated')::text, true);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE v_list uuid; v_task uuid := gen_random_uuid(); v_saved jsonb; v_invite jsonb; BEGIN
    v_list := public.monotask_shared_create_list('MonoTask: rollback smoke test');
    v_saved := public.monotask_shared_save_task(v_list, v_task, 0, 'Temporary check', 'Notes', false, true, auth.uid(), '[]', false);
    IF (v_saved->>'revision')::int <> 1 THEN RAISE EXCEPTION 'Unexpected revision'; END IF;
    v_saved := public.monotask_shared_save_task(v_list, v_task, 1, 'Temporary check', 'Updated notes', true, true, auth.uid(), '[]', false);
    IF (v_saved->>'revision')::int <> 2 OR (v_saved->>'is_done')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'Update did not round trip'; END IF;
    BEGIN
        PERFORM public.monotask_shared_save_task(v_list, v_task, 1, 'Stale check', '', false, false, null, '[]', false);
        RAISE EXCEPTION 'Stale update unexpectedly succeeded';
    EXCEPTION WHEN OTHERS THEN
        IF position('SHARED_CONFLICT' IN SQLERRM) = 0 THEN RAISE; END IF;
    END;
    v_invite := public.monotask_shared_create_invite(v_list);
    IF length(v_invite->>'code') <> 32 THEN RAISE EXCEPTION 'Invite not generated'; END IF;
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(public.monotask_shared_snapshot()->'tasks') t WHERE t->>'id' = v_task::text) THEN RAISE EXCEPTION 'Task missing from snapshot'; END IF;
    PERFORM public.monotask_shared_update_list(v_list, 'MonoTask: rollback smoke test', true);
END $$;
ROLLBACK;
SELECT 'MONOTASK_SHARED_LIVE_RPC_OK_ROLLED_BACK' AS verification;

-- Additive migration: private MonoTask tables and their owner_only policies are unchanged.
BEGIN;
CREATE SCHEMA IF NOT EXISTS monotask_private;
REVOKE ALL ON SCHEMA monotask_private FROM PUBLIC;
GRANT USAGE ON SCHEMA monotask_private TO authenticated;

CREATE TABLE IF NOT EXISTS public.monotask_shared_lists (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title text NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 100),
    owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
CREATE TABLE IF NOT EXISTS public.monotask_shared_members (
    list_id uuid NOT NULL REFERENCES public.monotask_shared_lists(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name text NOT NULL,
    joined_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (list_id, user_id)
);
CREATE INDEX IF NOT EXISTS monotask_shared_members_user ON public.monotask_shared_members(user_id, list_id);
CREATE TABLE IF NOT EXISTS public.monotask_shared_tasks (
    id uuid PRIMARY KEY,
    list_id uuid NOT NULL REFERENCES public.monotask_shared_lists(id) ON DELETE CASCADE,
    title text NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 500),
    notes text NOT NULL DEFAULT '' CHECK (length(notes) <= 20000),
    is_done boolean NOT NULL DEFAULT false,
    is_high_priority boolean NOT NULL DEFAULT false,
    assignee_id uuid,
    subtasks jsonb NOT NULL DEFAULT '[]'::jsonb,
    revision bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
CREATE INDEX IF NOT EXISTS monotask_shared_tasks_list ON public.monotask_shared_tasks(list_id);
CREATE TABLE IF NOT EXISTS public.monotask_shared_invites (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    list_id uuid NOT NULL REFERENCES public.monotask_shared_lists(id) ON DELETE CASCADE,
    token_hash text NOT NULL UNIQUE,
    expires_at timestamptz NOT NULL,
    used_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    used_at timestamptz,
    revoked_at timestamptz
);

CREATE OR REPLACE FUNCTION monotask_private.shared_member(p_list_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT auth.uid() IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.monotask_shared_members m
        JOIN public.monotask_shared_lists l ON l.id = m.list_id
        WHERE m.list_id = p_list_id AND m.user_id = auth.uid() AND l.deleted_at IS NULL
    );
$$;
REVOKE ALL ON FUNCTION monotask_private.shared_member(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION monotask_private.shared_member(uuid) TO authenticated;

ALTER TABLE public.monotask_shared_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.monotask_shared_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.monotask_shared_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.monotask_shared_invites ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.monotask_shared_lists, public.monotask_shared_members,
    public.monotask_shared_tasks, public.monotask_shared_invites FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.monotask_shared_lists, public.monotask_shared_members, public.monotask_shared_tasks TO authenticated;
DROP POLICY IF EXISTS shared_read ON public.monotask_shared_lists;
CREATE POLICY shared_read ON public.monotask_shared_lists FOR SELECT TO authenticated USING (monotask_private.shared_member(id));
DROP POLICY IF EXISTS shared_read ON public.monotask_shared_members;
CREATE POLICY shared_read ON public.monotask_shared_members FOR SELECT TO authenticated USING (monotask_private.shared_member(list_id));
DROP POLICY IF EXISTS shared_read ON public.monotask_shared_tasks;
CREATE POLICY shared_read ON public.monotask_shared_tasks FOR SELECT TO authenticated USING (monotask_private.shared_member(list_id));
-- No direct writes, including for owners. Mutations validate membership and revisions in RPCs.

CREATE OR REPLACE FUNCTION public.monotask_shared_create_list(p_title text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id uuid; v_name text;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'SHARED_AUTH_REQUIRED'; END IF;
    IF p_title IS NULL OR length(trim(p_title)) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'SHARED_INVALID_TITLE'; END IF;
    SELECT coalesce(nullif(split_part(email, '@', 1), ''), 'Участник') INTO v_name FROM auth.users WHERE id = auth.uid();
    INSERT INTO public.monotask_shared_lists(title, owner_id) VALUES (trim(p_title), auth.uid()) RETURNING id INTO v_id;
    INSERT INTO public.monotask_shared_members(list_id, user_id, display_name) VALUES (v_id, auth.uid(), coalesce(v_name, 'Участник'));
    RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.monotask_shared_snapshot()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'SHARED_AUTH_REQUIRED'; END IF;
    RETURN jsonb_build_object(
        'lists', coalesce((SELECT jsonb_agg(to_jsonb(l) ORDER BY l.created_at) FROM public.monotask_shared_lists l WHERE monotask_private.shared_member(l.id)), '[]'::jsonb),
        'members', coalesce((SELECT jsonb_agg(to_jsonb(m)) FROM public.monotask_shared_members m WHERE monotask_private.shared_member(m.list_id)), '[]'::jsonb),
        'tasks', coalesce((SELECT jsonb_agg(to_jsonb(t)) FROM public.monotask_shared_tasks t WHERE monotask_private.shared_member(t.list_id)), '[]'::jsonb)
    );
END; $$;

CREATE OR REPLACE FUNCTION public.monotask_shared_create_invite(p_list_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_list public.monotask_shared_lists; v_code text; v_expiry timestamptz;
BEGIN
    SELECT * INTO v_list FROM public.monotask_shared_lists WHERE id = p_list_id AND deleted_at IS NULL FOR UPDATE;
    IF auth.uid() IS NULL OR v_list.owner_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'SHARED_OWNER_REQUIRED'; END IF;
    v_code := replace(gen_random_uuid()::text, '-', '');
    v_expiry := now() + interval '72 hours';
    UPDATE public.monotask_shared_invites SET revoked_at = now() WHERE list_id = p_list_id AND used_at IS NULL AND revoked_at IS NULL;
    INSERT INTO public.monotask_shared_invites(list_id, token_hash, expires_at)
        VALUES (p_list_id, encode(sha256(convert_to(v_code, 'UTF8')), 'hex'), v_expiry);
    RETURN jsonb_build_object('code', v_code, 'expires_at', v_expiry);
END; $$;

CREATE OR REPLACE FUNCTION public.monotask_shared_join(p_code text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_invite public.monotask_shared_invites; v_list public.monotask_shared_lists; v_name text;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'SHARED_AUTH_REQUIRED'; END IF;
    IF p_code IS NULL OR lower(trim(p_code)) !~ '^[0-9a-f]{32}$' THEN RAISE EXCEPTION 'SHARED_INVALID_INVITE'; END IF;
    SELECT * INTO v_invite FROM public.monotask_shared_invites WHERE token_hash = encode(sha256(convert_to(lower(trim(p_code)), 'UTF8')), 'hex');
    IF NOT FOUND THEN RAISE EXCEPTION 'SHARED_INVALID_INVITE'; END IF;
    -- Always lock list first: concurrent saves, removals, invites and joins serialize on this row.
    SELECT * INTO v_list FROM public.monotask_shared_lists WHERE id = v_invite.list_id AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'SHARED_INVALID_INVITE'; END IF;
    SELECT * INTO v_invite FROM public.monotask_shared_invites WHERE id = v_invite.id FOR UPDATE;
    IF v_invite.revoked_at IS NOT NULL OR v_invite.expires_at <= now() THEN RAISE EXCEPTION 'SHARED_INVALID_INVITE'; END IF;
    IF v_invite.used_at IS NOT NULL AND v_invite.used_by IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'SHARED_INVALID_INVITE'; END IF;
    IF EXISTS (SELECT 1 FROM public.monotask_shared_members WHERE list_id = v_list.id AND user_id = auth.uid()) THEN RETURN v_list.id; END IF;
    SELECT coalesce(nullif(split_part(email, '@', 1), ''), 'Участник') INTO v_name FROM auth.users WHERE id = auth.uid();
    INSERT INTO public.monotask_shared_members(list_id, user_id, display_name) VALUES (v_list.id, auth.uid(), coalesce(v_name, 'Участник'));
    UPDATE public.monotask_shared_invites SET used_at = now(), used_by = auth.uid() WHERE id = v_invite.id;
    RETURN v_list.id;
END; $$;

CREATE OR REPLACE FUNCTION public.monotask_shared_save_task(
    p_list_id uuid, p_task_id uuid, p_expected_revision bigint, p_title text, p_notes text,
    p_is_done boolean, p_is_high_priority boolean, p_assignee_id uuid, p_subtasks jsonb, p_deleted boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_task public.monotask_shared_tasks; v_exists boolean;
BEGIN
    PERFORM 1 FROM public.monotask_shared_lists WHERE id = p_list_id AND deleted_at IS NULL FOR UPDATE;
    IF NOT monotask_private.shared_member(p_list_id) THEN RAISE EXCEPTION 'SHARED_FORBIDDEN'; END IF;
    IF p_title IS NULL OR length(trim(p_title)) NOT BETWEEN 1 AND 500 OR p_notes IS NULL OR length(p_notes) > 20000 THEN RAISE EXCEPTION 'SHARED_INVALID_TASK'; END IF;
    IF p_assignee_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.monotask_shared_members WHERE list_id = p_list_id AND user_id = p_assignee_id) THEN RAISE EXCEPTION 'SHARED_INVALID_ASSIGNEE'; END IF;
    IF p_subtasks IS NULL OR jsonb_typeof(p_subtasks) <> 'array' THEN RAISE EXCEPTION 'SHARED_INVALID_SUBTASKS'; END IF;
    IF jsonb_array_length(p_subtasks) > 100 OR EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_subtasks) s WHERE jsonb_typeof(s) <> 'object'
        OR coalesce(jsonb_typeof(s->'id'), '') <> 'string' OR coalesce(s->>'id', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        OR coalesce(jsonb_typeof(s->'title'), '') <> 'string' OR length(trim(coalesce(s->>'title', ''))) NOT BETWEEN 1 AND 500
        OR coalesce(jsonb_typeof(s->'is_done'), '') <> 'boolean'
    ) OR (SELECT count(*) FROM jsonb_array_elements(p_subtasks)) <> (SELECT count(DISTINCT s->>'id') FROM jsonb_array_elements(p_subtasks) s)
    THEN RAISE EXCEPTION 'SHARED_INVALID_SUBTASKS'; END IF;
    SELECT * INTO v_task FROM public.monotask_shared_tasks WHERE id = p_task_id FOR UPDATE;
    v_exists := FOUND;
    IF v_exists AND v_task.list_id <> p_list_id THEN RAISE EXCEPTION 'SHARED_FORBIDDEN'; END IF;
    IF v_exists AND v_task.deleted_at IS NOT NULL THEN
        IF p_deleted THEN RETURN to_jsonb(v_task); END IF;
        RAISE EXCEPTION 'SHARED_DELETED';
    END IF;
    IF (v_exists AND v_task.revision IS DISTINCT FROM p_expected_revision) OR (NOT v_exists AND p_expected_revision IS DISTINCT FROM 0) THEN RAISE EXCEPTION 'SHARED_CONFLICT'; END IF;
    IF v_exists THEN
        UPDATE public.monotask_shared_tasks SET title = trim(p_title), notes = p_notes, is_done = p_is_done,
            is_high_priority = p_is_high_priority, assignee_id = p_assignee_id, subtasks = p_subtasks,
            revision = revision + 1, updated_at = clock_timestamp(), deleted_at = CASE WHEN p_deleted THEN now() END
        WHERE id = p_task_id RETURNING * INTO v_task;
    ELSE
        INSERT INTO public.monotask_shared_tasks(id, list_id, title, notes, is_done, is_high_priority, assignee_id, subtasks, deleted_at)
        VALUES (p_task_id, p_list_id, trim(p_title), p_notes, p_is_done, p_is_high_priority, p_assignee_id, p_subtasks, CASE WHEN p_deleted THEN now() END) RETURNING * INTO v_task;
    END IF;
    RETURN to_jsonb(v_task);
END; $$;

CREATE OR REPLACE FUNCTION public.monotask_shared_remove_member(p_list_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_list public.monotask_shared_lists;
BEGIN
    SELECT * INTO v_list FROM public.monotask_shared_lists WHERE id = p_list_id AND deleted_at IS NULL FOR UPDATE;
    IF auth.uid() IS NULL OR NOT monotask_private.shared_member(p_list_id) THEN RAISE EXCEPTION 'SHARED_FORBIDDEN'; END IF;
    IF v_list.owner_id = p_user_id THEN RAISE EXCEPTION 'SHARED_OWNER_CANNOT_LEAVE'; END IF;
    IF v_list.owner_id <> auth.uid() AND p_user_id <> auth.uid() THEN RAISE EXCEPTION 'SHARED_OWNER_REQUIRED'; END IF;
    DELETE FROM public.monotask_shared_members WHERE list_id = p_list_id AND user_id = p_user_id;
END; $$;

CREATE OR REPLACE FUNCTION public.monotask_shared_update_list(p_list_id uuid, p_title text, p_deleted boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    PERFORM 1 FROM public.monotask_shared_lists WHERE id = p_list_id AND owner_id = auth.uid() AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND OR auth.uid() IS NULL THEN RAISE EXCEPTION 'SHARED_OWNER_REQUIRED'; END IF;
    IF p_title IS NULL OR length(trim(p_title)) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'SHARED_INVALID_TITLE'; END IF;
    UPDATE public.monotask_shared_lists SET title = trim(p_title), updated_at = clock_timestamp(), deleted_at = CASE WHEN p_deleted THEN now() END WHERE id = p_list_id;
    IF p_deleted THEN UPDATE public.monotask_shared_invites SET revoked_at = now() WHERE list_id = p_list_id; END IF;
END; $$;

-- Also clear assignments if an auth account is deleted outside the membership RPC.
CREATE OR REPLACE FUNCTION monotask_private.shared_member_removed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    UPDATE public.monotask_shared_tasks SET assignee_id = NULL, revision = revision + 1, updated_at = clock_timestamp()
        WHERE list_id = OLD.list_id AND assignee_id = OLD.user_id;
    -- Removing access also invalidates outstanding links the removed member might hold.
    UPDATE public.monotask_shared_invites SET revoked_at = now()
        WHERE list_id = OLD.list_id AND (used_by = OLD.user_id OR used_at IS NULL);
    RETURN OLD;
END; $$;
REVOKE ALL ON FUNCTION monotask_private.shared_member_removed() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS monotask_shared_member_removed ON public.monotask_shared_members;
CREATE TRIGGER monotask_shared_member_removed AFTER DELETE ON public.monotask_shared_members
    FOR EACH ROW EXECUTE FUNCTION monotask_private.shared_member_removed();

-- Function execution is opt-in; anonymous users cannot discover or consume invitations.
DO $$ DECLARE f record; BEGIN
    FOR f IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname LIKE 'monotask_shared_%'
    LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', f.signature);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f.signature);
    END LOOP;
END $$;
NOTIFY pgrst, 'reload schema';
COMMIT;

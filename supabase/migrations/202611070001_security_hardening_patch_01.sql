-- Smart Class v26.11.7
-- Security hardening patch 01
-- Draft for review only. DO NOT apply to production until separately approved.
-- Scope:
--   1) Make admin_delete_growth_reward reject NULL/unauthenticated callers.
--   2) Remove anon EXECUTE from that administrative RPC.
--   3) Make activity_member_stats respect underlying table RLS and remove anon access.
-- This migration does not delete rows, drop objects, or truncate tables.

begin;

-- 1) Harden the administrative reward deletion RPC.
-- Explicitly reject unauthenticated callers and NULL/non-admin roles.
create or replace function public.admin_delete_growth_reward(p_reward_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  n integer := 0;
  caller_role text;
begin
  if auth.uid() is null then
    raise exception '需要登入後才能執行此操作'
      using errcode = '42501';
  end if;

  select role
    into caller_role
    from public.profiles
   where id = auth.uid()
   limit 1;

  if caller_role is distinct from 'admin' then
    raise exception '只有管理員可以刪除獎勵'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
      from public.growth_rewards
     where id = p_reward_id
  ) then
    raise exception '找不到這個獎勵';
  end if;

  select count(*)
    into n
    from public.growth_reward_redemptions
   where reward_id = p_reward_id;

  if n > 0 then
    update public.growth_rewards
       set enabled = false,
           updated_at = now()
     where id = p_reward_id;

    return jsonb_build_object(
      'success', true,
      'action', 'disabled',
      'redemptions', n
    );
  end if;

  -- Preserve the existing behavior: delete only an unused reward.
  delete from public.growth_rewards
   where id = p_reward_id;

  if not found then
    raise exception '獎勵刪除失敗';
  end if;

  return jsonb_build_object(
    'success', true,
    'action', 'deleted',
    'redemptions', 0
  );
end;
$function$;

-- This is an admin-only RPC. Keep authenticated and trusted server execution.
revoke execute on function public.admin_delete_growth_reward(uuid) from public;
revoke execute on function public.admin_delete_growth_reward(uuid) from anon;
grant execute on function public.admin_delete_growth_reward(uuid) to authenticated;
grant execute on function public.admin_delete_growth_reward(uuid) to service_role;

-- 2) Prevent this aggregate view from bypassing the underlying RLS policies.
-- PostgreSQL 15+ supports security_invoker views.
alter view public.activity_member_stats
  set (security_invoker = true);

-- The view is not intended for anonymous access.
revoke all on table public.activity_member_stats from public;
revoke all on table public.activity_member_stats from anon;
grant select on table public.activity_member_stats to authenticated;
grant select on table public.activity_member_stats to service_role;

commit;

-- Post-apply verification (run separately; read-only):
-- SELECT has_function_privilege('anon',
--   'public.admin_delete_growth_reward(uuid)', 'EXECUTE') AS anon_can_execute,
--   has_function_privilege('authenticated',
--   'public.admin_delete_growth_reward(uuid)', 'EXECUTE') AS authenticated_can_execute;
--
-- SELECT reloptions, has_table_privilege('anon',
--   'public.activity_member_stats', 'SELECT') AS anon_can_select,
--   has_table_privilege('authenticated',
--   'public.activity_member_stats', 'SELECT') AS authenticated_can_select
-- FROM pg_class
-- WHERE oid = 'public.activity_member_stats'::regclass;

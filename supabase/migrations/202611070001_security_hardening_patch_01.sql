-- Smart Class v26.11.7
-- Security hardening patch 01
-- REVIEW DRAFT ONLY. Do not apply to production until separately approved.
--
-- Confirmed issue:
-- admin_delete_growth_reward() used "caller_role <> 'admin'".
-- In PostgreSQL, NULL <> 'admin' evaluates to NULL, not TRUE. An unauthenticated
-- caller with a missing profile could therefore pass the IF guard.
--
-- This patch changes only the authorization guard and the RPC EXECUTE ACL.
-- It deliberately does not change activity_member_stats in this patch:
-- app.js uses that view for the public activity leaderboard. A security_invoker
-- conversion or anon revoke would change public leaderboard behavior and needs
-- a separate, compatibility-preserving design.

begin;

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

  -- Existing admin-only behavior retained for unused rewards.
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

-- The function itself enforces the admin role; anonymous invocation is not needed.
revoke execute on function public.admin_delete_growth_reward(uuid) from public;
revoke execute on function public.admin_delete_growth_reward(uuid) from anon;
grant execute on function public.admin_delete_growth_reward(uuid) to authenticated;
grant execute on function public.admin_delete_growth_reward(uuid) to service_role;

commit;

-- Read-only verification after separately approved application:
-- SELECT has_function_privilege('anon',
--   'public.admin_delete_growth_reward(uuid)', 'EXECUTE') AS anon_can_execute,
--   has_function_privilege('authenticated',
--   'public.admin_delete_growth_reward(uuid)', 'EXECUTE') AS authenticated_can_execute;

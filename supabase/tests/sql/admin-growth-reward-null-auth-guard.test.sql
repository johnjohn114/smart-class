-- Regression assertions for anonymous and non-admin calls to reward admin RPCs.
DO $acl$
BEGIN
 IF has_function_privilege('anon','public.admin_delete_growth_reward(uuid)','EXECUTE')
    OR has_function_privilege('anon',
      'public.admin_upsert_growth_reward(uuid,text,text,text,text,text,integer,text,uuid,integer,integer,text,text,text,integer,timestamp with time zone,timestamp with time zone,integer,boolean)','EXECUTE') THEN
   RAISE EXCEPTION 'FAIL: anon still has direct EXECUTE on admin reward RPCs';
 END IF;
 IF NOT has_function_privilege('authenticated','public.admin_delete_growth_reward(uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated',
      'public.admin_upsert_growth_reward(uuid,text,text,text,text,text,integer,text,uuid,integer,integer,text,text,text,integer,timestamp with time zone,timestamp with time zone,integer,boolean)','EXECUTE') THEN
   RAISE EXCEPTION 'FAIL: authenticated admin RPC access was removed';
 END IF;
END
$acl$;

-- Even if a future ACL mistake re-grants EXECUTE, the function-body guard must
-- reject missing identity. Grant only inside this disposable database.
GRANT EXECUTE ON FUNCTION public.admin_delete_growth_reward(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.admin_upsert_growth_reward(
 uuid,text,text,text,text,text,integer,text,uuid,integer,integer,
 text,text,text,integer,timestamptz,timestamptz,integer,boolean
) TO anon;

SET ROLE anon;
DO $anon_guard$
DECLARE denied boolean;
BEGIN
 denied:=false;
 BEGIN PERFORM public.admin_delete_growth_reward('00000000-0000-4000-8000-000000000010');
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM='只有管理員可以刪除獎勵' THEN denied:=true; ELSE RAISE; END IF;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: anonymous delete passed NULL auth guard'; END IF;

 denied:=false;
 BEGIN
  PERFORM public.admin_upsert_growth_reward(
   NULL,'anon-created','Anonymous created',NULL,NULL,NULL,1,NULL,NULL,
   NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,0,true
  );
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM='只有管理員可以管理獎勵' THEN denied:=true; ELSE RAISE; END IF;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: anonymous upsert passed NULL auth guard'; END IF;
END
$anon_guard$;
RESET ROLE;

DO $anon_unchanged$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.growth_rewards WHERE id='00000000-0000-4000-8000-000000000010' AND enabled)
 THEN RAISE EXCEPTION 'FAIL: anonymous delete changed the fixture reward'; END IF;
 IF EXISTS(SELECT 1 FROM public.growth_rewards WHERE code='anon-created')
 THEN RAISE EXCEPTION 'FAIL: anonymous upsert created a reward'; END IF;
END
$anon_unchanged$;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
DO $member_guard$
DECLARE denied boolean;
BEGIN
 denied:=false;
 BEGIN PERFORM public.admin_delete_growth_reward('00000000-0000-4000-8000-000000000010');
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM='只有管理員可以刪除獎勵' THEN denied:=true; ELSE RAISE; END IF;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: ordinary member deleted a reward'; END IF;

 denied:=false;
 BEGIN
  PERFORM public.admin_upsert_growth_reward(
   NULL,'member-created','Member created',NULL,NULL,NULL,1,NULL,NULL,
   NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,0,true
  );
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM='只有管理員可以管理獎勵' THEN denied:=true; ELSE RAISE; END IF;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'FAIL: ordinary member created a reward'; END IF;
END
$member_guard$;
RESET ROLE;

DO $member_unchanged$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.growth_rewards WHERE id='00000000-0000-4000-8000-000000000010' AND enabled)
 THEN RAISE EXCEPTION 'FAIL: member delete changed the fixture reward'; END IF;
 IF EXISTS(SELECT 1 FROM public.growth_rewards WHERE code='member-created')
 THEN RAISE EXCEPTION 'FAIL: member upsert created a reward'; END IF;
END
$member_unchanged$;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
DO $admin_success$
DECLARE result jsonb; new_id uuid;
BEGIN
 result:=public.admin_upsert_growth_reward(
  NULL,'admin-created','Admin created',NULL,NULL,NULL,5,NULL,NULL,
  NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,1,true
 );
 new_id:=(result->>'id')::uuid;
 IF result->>'action'<>'created' THEN RAISE EXCEPTION 'FAIL: admin could not create reward'; END IF;
 result:=public.admin_upsert_growth_reward(
  new_id,'admin-updated','Admin updated',NULL,NULL,NULL,8,NULL,NULL,
  NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,2,true
 );
 IF result->>'action'<>'updated' THEN RAISE EXCEPTION 'FAIL: admin could not update reward'; END IF;
 result:=public.admin_delete_growth_reward(new_id);
 IF result->>'action'<>'deleted' THEN RAISE EXCEPTION 'FAIL: admin could not delete reward'; END IF;
END
$admin_success$;
RESET ROLE;

SELECT 'PASS: anonymous/member reward-admin RPC calls denied; administrator operations preserved' AS result;

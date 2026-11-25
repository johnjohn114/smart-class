-- Disposable PostgreSQL fixture: reproduces the two production RPCs.
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END
$roles$;

CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
GRANT USAGE ON SCHEMA auth TO anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO PUBLIC;

CREATE TABLE public.profiles(id uuid PRIMARY KEY, role text);
CREATE TABLE public.growth_rewards(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL,
  title text NOT NULL,
  description text,
  icon text,
  category text,
  reward_type text NOT NULL DEFAULT 'coupon',
  point_cost integer NOT NULL,
  min_level text,
  required_achievement_id uuid,
  user_limit integer,
  total_limit integer,
  coupon_title text,
  coupon_description text,
  coupon_discount text,
  coupon_expires_days integer,
  available_from timestamptz,
  available_until timestamptz,
  sort_order integer,
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.growth_reward_redemptions(reward_id uuid NOT NULL);

INSERT INTO public.profiles(id,role) VALUES
 ('00000000-0000-4000-8000-000000000001','admin'),
 ('00000000-0000-4000-8000-000000000002','visitor');
INSERT INTO public.growth_rewards(id,code,title,point_cost,enabled) VALUES
 ('00000000-0000-4000-8000-000000000010','fixture','Fixture reward',10,true);

-- Reproduce the production NULL-comparison bug before applying the candidate.
CREATE FUNCTION public.admin_delete_growth_reward(p_reward_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE n integer:=0; caller_role text;
BEGIN
 SELECT role INTO caller_role FROM public.profiles WHERE id=auth.uid() LIMIT 1;
 IF caller_role <> 'admin' THEN RAISE EXCEPTION '只有管理員可以刪除獎勵'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.growth_rewards WHERE id=p_reward_id) THEN RAISE EXCEPTION '找不到這個獎勵'; END IF;
 SELECT count(*) INTO n FROM public.growth_reward_redemptions WHERE reward_id=p_reward_id;
 IF n>0 THEN
   UPDATE public.growth_rewards SET enabled=false,updated_at=now() WHERE id=p_reward_id;
   RETURN jsonb_build_object('success',true,'action','disabled','redemptions',n);
 END IF;
 DELETE FROM public.growth_rewards WHERE id=p_reward_id;
 IF NOT FOUND THEN RAISE EXCEPTION '獎勵刪除失敗'; END IF;
 RETURN jsonb_build_object('success',true,'action','deleted','redemptions',0);
END;
$function$;

CREATE FUNCTION public.admin_upsert_growth_reward(
 p_reward_id uuid,p_code text,p_title text,p_description text,p_icon text,p_category text,
 p_point_cost integer,p_min_level text,p_required_achievement_id uuid,p_user_limit integer,
 p_total_limit integer,p_coupon_title text,p_coupon_description text,p_coupon_discount text,
 p_coupon_expires_days integer,p_available_from timestamptz,p_available_until timestamptz,
 p_sort_order integer,p_enabled boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE caller_role text; row_data public.growth_rewards%rowtype;
BEGIN
 SELECT role INTO caller_role FROM public.profiles WHERE id=auth.uid() LIMIT 1;
 IF caller_role <> 'admin' THEN RAISE EXCEPTION '只有管理員可以管理獎勵'; END IF;
 IF coalesce(trim(p_code),'')='' THEN RAISE EXCEPTION '獎勵代碼不可空白'; END IF;
 IF coalesce(trim(p_title),'')='' THEN RAISE EXCEPTION '獎勵名稱不可空白'; END IF;
 IF p_point_cost IS NULL OR p_point_cost<1 THEN RAISE EXCEPTION '所需積分必須大於 0'; END IF;
 IF p_user_limit IS NOT NULL AND p_user_limit<1 THEN RAISE EXCEPTION '每人兌換上限必須大於 0'; END IF;
 IF p_total_limit IS NOT NULL AND p_total_limit<1 THEN RAISE EXCEPTION '總兌換上限必須大於 0'; END IF;
 IF p_coupon_expires_days IS NOT NULL AND p_coupon_expires_days<1 THEN RAISE EXCEPTION '優惠券有效天數必須大於 0'; END IF;
 IF p_available_from IS NOT NULL AND p_available_until IS NOT NULL AND p_available_from>=p_available_until THEN RAISE EXCEPTION '開始時間必須早於結束時間'; END IF;
 IF p_reward_id IS NULL THEN
  INSERT INTO public.growth_rewards(code,title,description,icon,category,reward_type,point_cost,min_level,required_achievement_id,user_limit,total_limit,coupon_title,coupon_description,coupon_discount,coupon_expires_days,available_from,available_until,sort_order,enabled)
  VALUES(p_code,p_title,p_description,p_icon,p_category,'coupon',p_point_cost,p_min_level,p_required_achievement_id,p_user_limit,p_total_limit,p_coupon_title,p_coupon_description,p_coupon_discount,p_coupon_expires_days,p_available_from,p_available_until,p_sort_order,p_enabled)
  RETURNING * INTO row_data;
 ELSE
  UPDATE public.growth_rewards SET code=p_code,title=p_title,description=p_description,icon=p_icon,category=p_category,reward_type='coupon',point_cost=p_point_cost,min_level=p_min_level,required_achievement_id=p_required_achievement_id,user_limit=p_user_limit,total_limit=p_total_limit,coupon_title=p_coupon_title,coupon_description=p_coupon_description,coupon_discount=p_coupon_discount,coupon_expires_days=p_coupon_expires_days,available_from=p_available_from,available_until=p_available_until,sort_order=p_sort_order,enabled=p_enabled,updated_at=now()
  WHERE id=p_reward_id RETURNING * INTO row_data;
  IF row_data.id IS NULL THEN RAISE EXCEPTION '找不到這個獎勵'; END IF;
 END IF;
 RETURN jsonb_build_object('success',true,'id',row_data.id,'action',CASE WHEN p_reward_id IS NULL THEN 'created' ELSE 'updated' END);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.admin_delete_growth_reward(uuid) TO anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admin_upsert_growth_reward(
 uuid,text,text,text,text,text,integer,text,uuid,integer,integer,
 text,text,text,integer,timestamptz,timestamptz,integer,boolean
) TO anon,authenticated,service_role;

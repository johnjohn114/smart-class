-- Trigger definitions are listed as event-trigger action statements; this is not a full CREATE TRIGGER reconstruction.
-- Sequence declarations are inventory only; ownership, parameters and current values are not captured.
-- Trigger inventory:
-- competition_registrations.trg_check_competition_registration_rules\nEXECUTE FUNCTION check_competition_registration_rules()

-- competition_registrations.trg_check_competition_registration_rules\nEXECUTE FUNCTION check_competition_registration_rules()

-- competition_registrations.trg_growth_registration_reward\nEXECUTE FUNCTION growth_registration_reward()

-- competition_results.trg_growth_result_reward\nEXECUTE FUNCTION growth_result_reward()

-- competitions.trg_competition_publish_time\nEXECUTE FUNCTION set_competition_publish_time()

-- competitions.trg_competition_publish_time\nEXECUTE FUNCTION set_competition_publish_time()

-- profiles.trg_profiles_member_no\nEXECUTE FUNCTION assign_member_no_and_nickname()

-- profiles.trg_protect_profile_fields\nEXECUTE FUNCTION protect_profile_fields()

-- visitor_accounts.trg_visitor_accounts_profile\nEXECUTE FUNCTION ensure_visitor_profile()

-- Sequence inventory:
CREATE SEQUENCE IF NOT EXISTS public.device_push_tokens_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.member_no_seq;

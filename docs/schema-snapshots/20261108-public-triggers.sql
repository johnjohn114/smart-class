-- pg_get_triggerdef catalog reconstruction; not pg_dump output.
CREATE TRIGGER trg_check_competition_registration_rules BEFORE INSERT OR UPDATE ON competition_registrations FOR EACH ROW EXECUTE FUNCTION check_competition_registration_rules();

CREATE TRIGGER trg_growth_registration_reward AFTER INSERT ON competition_registrations FOR EACH ROW EXECUTE FUNCTION growth_registration_reward();

CREATE TRIGGER trg_growth_result_reward AFTER INSERT ON competition_results FOR EACH ROW EXECUTE FUNCTION growth_result_reward();

CREATE TRIGGER trg_competition_publish_time BEFORE INSERT OR UPDATE OF published ON competitions FOR EACH ROW EXECUTE FUNCTION set_competition_publish_time();

CREATE TRIGGER trg_profiles_member_no BEFORE INSERT ON profiles FOR EACH ROW EXECUTE FUNCTION assign_member_no_and_nickname();

CREATE TRIGGER trg_protect_profile_fields BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION protect_profile_fields();

CREATE TRIGGER trg_visitor_accounts_profile AFTER INSERT ON visitor_accounts FOR EACH ROW EXECUTE FUNCTION ensure_visitor_profile();

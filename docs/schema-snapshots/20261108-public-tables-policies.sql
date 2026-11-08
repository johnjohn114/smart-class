-- READ-ONLY CATALOG-RECONSTRUCTED SNAPSHOT
-- Project ref: fsoowongtavlsrwvzbze
-- Captured: 2026-11-08
-- Scope: public ordinary/partitioned tables, constraints, indexes, RLS policies, table grants.
-- Not pg_dump output. Review before any restore use.
-- Views, functions, triggers, sequences, schema grants, extensions and managed schemas are separate.

BEGIN;

-- activity_badges
CREATE TABLE public.activity_badges (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  code text NOT NULL,
  title text NOT NULL,
  description text,
  icon text DEFAULT '🏅'::text NOT NULL,
  requirement_type text NOT NULL,
  requirement_value integer DEFAULT 1 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT activity_badges_code_key UNIQUE (code),
  CONSTRAINT activity_badges_pkey PRIMARY KEY (id),
  CONSTRAINT activity_badges_requirement_type_check CHECK (requirement_type = ANY (ARRAY['first_activity'::text, 'activity_count'::text, 'total_points'::text, 'perfect_attendance'::text]))
);
ALTER TABLE public.activity_badges ENABLE ROW LEVEL SECURITY;
-- ai_announcement_generations
CREATE TABLE public.ai_announcement_generations (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id uuid NOT NULL,
  topic text NOT NULL,
  event_info text,
  audience text,
  important_notes text,
  style text DEFAULT '活潑'::text NOT NULL,
  generated_title text,
  generated_summary text,
  generated_content text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT ai_announcement_generations_pkey PRIMARY KEY (id),
  CONSTRAINT ai_announcement_generations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.ai_announcement_generations ENABLE ROW LEVEL SECURITY;
-- announcement_reads
CREATE TABLE public.announcement_reads (
  announcement_id uuid NOT NULL,
  user_id uuid NOT NULL,
  read_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT announcement_reads_announcement_id_fkey FOREIGN KEY (announcement_id) REFERENCES announcements(id) ON DELETE CASCADE,
  CONSTRAINT announcement_reads_pkey PRIMARY KEY (announcement_id, user_id),
  CONSTRAINT announcement_reads_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.announcement_reads ENABLE ROW LEVEL SECURITY;
-- announcements
CREATE TABLE public.announcements (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  title text NOT NULL,
  content text NOT NULL,
  date date DEFAULT CURRENT_DATE,
  published boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  category text DEFAULT '最新消息'::text NOT NULL,
  pinned boolean DEFAULT false NOT NULL,
  published_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  link_url text,
  link_label text,
  popup_enabled boolean DEFAULT false NOT NULL,
  popup_mode text DEFAULT 'once'::text NOT NULL,
  popup_start_at timestamp with time zone,
  popup_end_at timestamp with time zone,
  push_enabled boolean DEFAULT false NOT NULL,
  push_sent_at timestamp with time zone,
  event_date date,
  event_end_date date,
  event_date_source text,
  event_date_confirmed boolean DEFAULT false NOT NULL,
  CONSTRAINT announcements_event_date_range_check CHECK (event_end_date IS NULL OR event_date IS NULL OR event_end_date >= event_date),
  CONSTRAINT announcements_event_date_source_check CHECK (event_date_source IS NULL OR (event_date_source = ANY (ARRAY['manual'::text, 'auto'::text]))),
  CONSTRAINT announcements_pkey PRIMARY KEY (id),
  CONSTRAINT announcements_popup_mode_check CHECK (popup_mode = ANY (ARRAY['once'::text, 'every_visit'::text]))
);
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;
-- app_releases
CREATE TABLE public.app_releases (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  version_code integer NOT NULL,
  version_name text NOT NULL,
  release_notes text DEFAULT ''::text NOT NULL,
  apk_url text NOT NULL,
  published boolean DEFAULT false NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  published_at timestamp with time zone,
  created_by uuid,
  CONSTRAINT app_releases_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id),
  CONSTRAINT app_releases_pkey PRIMARY KEY (id),
  CONSTRAINT app_releases_version_code_check CHECK (version_code > 0),
  CONSTRAINT app_releases_version_code_key UNIQUE (version_code)
);
ALTER TABLE public.app_releases ENABLE ROW LEVEL SECURITY;
-- competition_attendance
CREATE TABLE public.competition_attendance (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  competition_id uuid NOT NULL,
  registration_id uuid NOT NULL,
  user_id uuid NOT NULL,
  status text DEFAULT 'checked_in'::text NOT NULL,
  checked_in_at timestamp with time zone,
  checked_out_at timestamp with time zone,
  points_awarded integer DEFAULT 0 NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  completion_points_awarded integer DEFAULT 0 NOT NULL,
  CONSTRAINT competition_attendance_competition_id_fkey FOREIGN KEY (competition_id) REFERENCES competitions(id) ON DELETE CASCADE,
  CONSTRAINT competition_attendance_competition_id_user_id_key UNIQUE (competition_id, user_id),
  CONSTRAINT competition_attendance_pkey PRIMARY KEY (id),
  CONSTRAINT competition_attendance_registration_id_fkey FOREIGN KEY (registration_id) REFERENCES competition_registrations(id) ON DELETE CASCADE,
  CONSTRAINT competition_attendance_status_check CHECK (status = ANY (ARRAY['checked_in'::text, 'late'::text, 'no_show'::text, 'cancelled'::text])),
  CONSTRAINT competition_attendance_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.competition_attendance ENABLE ROW LEVEL SECURITY;
-- competition_categories
CREATE TABLE public.competition_categories (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  sort_order integer DEFAULT 100 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  parent_category text,
  CONSTRAINT competition_categories_name_key UNIQUE (name),
  CONSTRAINT competition_categories_pkey PRIMARY KEY (id)
);
ALTER TABLE public.competition_categories ENABLE ROW LEVEL SECURITY;
-- competition_registrations
CREATE TABLE public.competition_registrations (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  competition_id uuid NOT NULL,
  user_id uuid NOT NULL,
  member_no integer,
  nickname text NOT NULL,
  email text,
  note text,
  status text DEFAULT 'active'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  cancelled_at timestamp with time zone,
  custom_fields jsonb DEFAULT '{}'::jsonb NOT NULL,
  CONSTRAINT competition_registrations_competition_id_fkey FOREIGN KEY (competition_id) REFERENCES competitions(id) ON DELETE CASCADE,
  CONSTRAINT competition_registrations_competition_id_user_id_key UNIQUE (competition_id, user_id),
  CONSTRAINT competition_registrations_pkey PRIMARY KEY (id),
  CONSTRAINT competition_registrations_status_check CHECK (status = ANY (ARRAY['active'::text, 'pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text])),
  CONSTRAINT competition_registrations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.competition_registrations ENABLE ROW LEVEL SECURITY;
-- competition_results
CREATE TABLE public.competition_results (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  competition_id uuid NOT NULL,
  player_name text NOT NULL,
  place integer NOT NULL,
  score numeric(12,2),
  prize text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  user_id uuid,
  CONSTRAINT competition_results_competition_id_fkey FOREIGN KEY (competition_id) REFERENCES competitions(id) ON DELETE CASCADE,
  CONSTRAINT competition_results_pkey PRIMARY KEY (id),
  CONSTRAINT competition_results_place_check CHECK (place > 0),
  CONSTRAINT competition_results_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE public.competition_results ENABLE ROW LEVEL SECURITY;
-- competition_reward_grants
CREATE TABLE public.competition_reward_grants (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  competition_id uuid NOT NULL,
  reward_rule_id uuid NOT NULL,
  user_id uuid NOT NULL,
  granted_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT competition_reward_grants_competition_id_fkey FOREIGN KEY (competition_id) REFERENCES competitions(id) ON DELETE CASCADE,
  CONSTRAINT competition_reward_grants_pkey PRIMARY KEY (id),
  CONSTRAINT competition_reward_grants_reward_rule_id_fkey FOREIGN KEY (reward_rule_id) REFERENCES competition_reward_rules(id) ON DELETE CASCADE,
  CONSTRAINT competition_reward_grants_reward_rule_id_user_id_key UNIQUE (reward_rule_id, user_id),
  CONSTRAINT competition_reward_grants_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.competition_reward_grants ENABLE ROW LEVEL SECURITY;
-- competition_reward_rules
CREATE TABLE public.competition_reward_rules (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  competition_id uuid NOT NULL,
  reward_type text NOT NULL,
  reward_value integer,
  badge_id uuid,
  title text NOT NULL,
  description text,
  enabled boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT competition_reward_rules_badge_id_fkey FOREIGN KEY (badge_id) REFERENCES activity_badges(id) ON DELETE SET NULL,
  CONSTRAINT competition_reward_rules_competition_id_fkey FOREIGN KEY (competition_id) REFERENCES competitions(id) ON DELETE CASCADE,
  CONSTRAINT competition_reward_rules_pkey PRIMARY KEY (id),
  CONSTRAINT competition_reward_rules_reward_type_check CHECK (reward_type = ANY (ARRAY['points'::text, 'badge'::text]))
);
ALTER TABLE public.competition_reward_rules ENABLE ROW LEVEL SECURITY;
-- competition_waitlist
CREATE TABLE public.competition_waitlist (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  competition_id uuid NOT NULL,
  user_id uuid NOT NULL,
  member_no integer,
  nickname text,
  email text,
  note text,
  "position" integer NOT NULL,
  status text DEFAULT 'waiting'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  promoted_at timestamp with time zone,
  CONSTRAINT competition_waitlist_competition_id_fkey FOREIGN KEY (competition_id) REFERENCES competitions(id) ON DELETE CASCADE,
  CONSTRAINT competition_waitlist_competition_id_user_id_key UNIQUE (competition_id, user_id),
  CONSTRAINT competition_waitlist_pkey PRIMARY KEY (id),
  CONSTRAINT competition_waitlist_status_check CHECK (status = ANY (ARRAY['waiting'::text, 'promoted'::text, 'cancelled'::text])),
  CONSTRAINT competition_waitlist_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.competition_waitlist ENABLE ROW LEVEL SECURITY;
-- competitions
CREATE TABLE public.competitions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  category text DEFAULT 'Minecraft'::text NOT NULL,
  event_date date,
  description text,
  published boolean DEFAULT false NOT NULL,
  published_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  registration_deadline timestamp with time zone,
  registration_capacity integer,
  registration_approval boolean DEFAULT false NOT NULL,
  registration_fields jsonb DEFAULT '[]'::jsonb NOT NULL,
  checkin_enabled boolean DEFAULT false NOT NULL,
  checkin_code text,
  checkin_start_at timestamp with time zone,
  checkin_end_at timestamp with time zone,
  checkin_points integer DEFAULT 10 NOT NULL,
  waitlist_enabled boolean DEFAULT true NOT NULL,
  completion_points integer DEFAULT 20 NOT NULL,
  settled_at timestamp with time zone,
  CONSTRAINT competitions_pkey PRIMARY KEY (id)
);
ALTER TABLE public.competitions ENABLE ROW LEVEL SECURITY;
-- coupons
CREATE TABLE public.coupons (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id uuid NOT NULL,
  title text NOT NULL,
  description text,
  code text NOT NULL,
  discount text,
  expires_at timestamp with time zone,
  used boolean DEFAULT false NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  usage_condition text,
  used_at timestamp with time zone,
  CONSTRAINT coupons_pkey PRIMARY KEY (id),
  CONSTRAINT coupons_user_id_fkey FOREIGN KEY (user_id) REFERENCES visitor_accounts(id) ON DELETE CASCADE
);
ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;
-- device_push_tokens
CREATE TABLE public.device_push_tokens (
  id bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
  user_id uuid DEFAULT auth.uid() NOT NULL,
  token text NOT NULL,
  platform text DEFAULT 'android'::text NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT device_push_tokens_pkey PRIMARY KEY (id),
  CONSTRAINT device_push_tokens_platform_check CHECK (platform = 'android'::text),
  CONSTRAINT device_push_tokens_token_key UNIQUE (token),
  CONSTRAINT device_push_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.device_push_tokens ENABLE ROW LEVEL SECURITY;
-- download_files
CREATE TABLE public.download_files (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  title text NOT NULL,
  description text,
  file_name text,
  file_url text,
  published boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  storage_provider text DEFAULT 'supabase'::text NOT NULL,
  object_key text,
  file_size bigint,
  mime_type text,
  version text,
  download_count bigint DEFAULT 0 NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT download_files_pkey PRIMARY KEY (id),
  CONSTRAINT download_files_storage_provider_check CHECK (storage_provider = ANY (ARRAY['supabase'::text, 'r2'::text, 'github'::text]))
);
ALTER TABLE public.download_files ENABLE ROW LEVEL SECURITY;
-- form_answers
CREATE TABLE public.form_answers (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  response_id uuid NOT NULL,
  question_id uuid NOT NULL,
  answer_text text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT form_answers_pkey PRIMARY KEY (id),
  CONSTRAINT form_answers_question_id_fkey FOREIGN KEY (question_id) REFERENCES form_questions(id) ON DELETE CASCADE,
  CONSTRAINT form_answers_response_id_fkey FOREIGN KEY (response_id) REFERENCES form_responses(id) ON DELETE CASCADE
);
ALTER TABLE public.form_answers ENABLE ROW LEVEL SECURITY;
-- form_questions
CREATE TABLE public.form_questions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  form_id uuid NOT NULL,
  question text NOT NULL,
  question_type text DEFAULT 'text'::text NOT NULL,
  options jsonb,
  required boolean DEFAULT false NOT NULL,
  sort_order integer DEFAULT 1 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT form_questions_form_id_fkey FOREIGN KEY (form_id) REFERENCES forms(id) ON DELETE CASCADE,
  CONSTRAINT form_questions_pkey PRIMARY KEY (id),
  CONSTRAINT form_questions_question_type_check CHECK (question_type = ANY (ARRAY['text'::text, 'textarea'::text, 'email'::text, 'date'::text, 'radio'::text, 'checkbox'::text, 'select'::text]))
);
ALTER TABLE public.form_questions ENABLE ROW LEVEL SECURITY;
-- form_responses
CREATE TABLE public.form_responses (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  form_id uuid NOT NULL,
  user_id uuid,
  visitor_email text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT form_responses_form_id_fkey FOREIGN KEY (form_id) REFERENCES forms(id) ON DELETE CASCADE,
  CONSTRAINT form_responses_pkey PRIMARY KEY (id),
  CONSTRAINT form_responses_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE public.form_responses ENABLE ROW LEVEL SECURITY;
-- forms
CREATE TABLE public.forms (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  title text NOT NULL,
  description text,
  published boolean DEFAULT false NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT forms_pkey PRIMARY KEY (id)
);
ALTER TABLE public.forms ENABLE ROW LEVEL SECURITY;
-- growth_achievement_unlock_history
CREATE TABLE public.growth_achievement_unlock_history (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id uuid NOT NULL,
  achievement_id uuid NOT NULL,
  unlocked_at timestamp with time zone NOT NULL,
  archived_at timestamp with time zone DEFAULT now() NOT NULL,
  reset_history_id uuid,
  snapshot_title text,
  snapshot_reward_points integer DEFAULT 0 NOT NULL,
  CONSTRAINT growth_achievement_unlock_history_achievement_id_fkey FOREIGN KEY (achievement_id) REFERENCES growth_achievements(id) ON DELETE CASCADE,
  CONSTRAINT growth_achievement_unlock_history_pkey PRIMARY KEY (id),
  CONSTRAINT growth_achievement_unlock_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.growth_achievement_unlock_history ENABLE ROW LEVEL SECURITY;
-- growth_achievements
CREATE TABLE public.growth_achievements (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  code text NOT NULL,
  title text NOT NULL,
  description text,
  achievement_type text NOT NULL,
  requirement_count integer DEFAULT 1 NOT NULL,
  reward_points integer DEFAULT 0 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  icon text DEFAULT '🏆'::text NOT NULL,
  rarity text DEFAULT 'common'::text NOT NULL,
  hidden boolean DEFAULT false NOT NULL,
  CONSTRAINT growth_achievements_achievement_type_check CHECK (achievement_type = ANY (ARRAY['registration_count'::text, 'result_place'::text, 'points'::text, 'active_days'::text, 'login_streak'::text, 'registration_streak'::text, 'night_visit'::text, 'weekend_visit'::text])),
  CONSTRAINT growth_achievements_code_key UNIQUE (code),
  CONSTRAINT growth_achievements_pkey PRIMARY KEY (id),
  CONSTRAINT growth_achievements_rarity_check CHECK (rarity = ANY (ARRAY['common'::text, 'rare'::text, 'epic'::text, 'legendary'::text])),
  CONSTRAINT growth_achievements_requirement_count_check CHECK (requirement_count > 0),
  CONSTRAINT growth_achievements_reward_points_check CHECK (reward_points >= 0)
);
ALTER TABLE public.growth_achievements ENABLE ROW LEVEL SECURITY;
-- growth_activity_days
CREATE TABLE public.growth_activity_days (
  user_id uuid NOT NULL,
  activity_date date NOT NULL,
  source text DEFAULT 'visit'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT growth_activity_days_pkey PRIMARY KEY (user_id, activity_date),
  CONSTRAINT growth_activity_days_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.growth_activity_days ENABLE ROW LEVEL SECURITY;
-- growth_levels
CREATE TABLE public.growth_levels (
  code text NOT NULL,
  name text NOT NULL,
  min_points integer DEFAULT 0 NOT NULL,
  icon text DEFAULT '⭐'::text NOT NULL,
  sort_order integer DEFAULT 0 NOT NULL,
  CONSTRAINT growth_levels_min_points_check CHECK (min_points >= 0),
  CONSTRAINT growth_levels_pkey PRIMARY KEY (code)
);
ALTER TABLE public.growth_levels ENABLE ROW LEVEL SECURITY;
-- growth_point_transactions
CREATE TABLE public.growth_point_transactions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id uuid NOT NULL,
  amount integer NOT NULL,
  reason text NOT NULL,
  source_type text DEFAULT 'manual'::text NOT NULL,
  source_id text,
  source_key text,
  admin_user_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT growth_point_transactions_admin_user_id_fkey FOREIGN KEY (admin_user_id) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT growth_point_transactions_amount_check CHECK (amount <> 0),
  CONSTRAINT growth_point_transactions_pkey PRIMARY KEY (id),
  CONSTRAINT growth_point_transactions_source_key_key UNIQUE (source_key),
  CONSTRAINT growth_point_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.growth_point_transactions ENABLE ROW LEVEL SECURITY;
-- growth_reset_history
CREATE TABLE public.growth_reset_history (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id uuid NOT NULL,
  reset_by uuid,
  reset_no integer NOT NULL,
  reason text DEFAULT '管理員手動重置'::text NOT NULL,
  before_points integer DEFAULT 0 NOT NULL,
  after_points integer DEFAULT 0 NOT NULL,
  before_level text DEFAULT 'newbie'::text NOT NULL,
  after_level text DEFAULT 'newbie'::text NOT NULL,
  before_active_days integer DEFAULT 0 NOT NULL,
  before_login_streak integer DEFAULT 0 NOT NULL,
  before_completed_tasks integer DEFAULT 0 NOT NULL,
  before_achievements integer DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT growth_reset_history_pkey PRIMARY KEY (id),
  CONSTRAINT growth_reset_history_reset_by_fkey FOREIGN KEY (reset_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT growth_reset_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.growth_reset_history ENABLE ROW LEVEL SECURITY;
-- growth_reward_redemptions
CREATE TABLE public.growth_reward_redemptions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  reward_id uuid NOT NULL,
  user_id uuid NOT NULL,
  point_cost integer NOT NULL,
  status text DEFAULT 'redeemed'::text NOT NULL,
  coupon_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT growth_reward_redemptions_coupon_id_fkey FOREIGN KEY (coupon_id) REFERENCES coupons(id) ON DELETE SET NULL,
  CONSTRAINT growth_reward_redemptions_pkey PRIMARY KEY (id),
  CONSTRAINT growth_reward_redemptions_point_cost_check CHECK (point_cost > 0),
  CONSTRAINT growth_reward_redemptions_reward_id_fkey FOREIGN KEY (reward_id) REFERENCES growth_rewards(id) ON DELETE RESTRICT,
  CONSTRAINT growth_reward_redemptions_status_check CHECK (status = ANY (ARRAY['redeemed'::text, 'cancelled'::text])),
  CONSTRAINT growth_reward_redemptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.growth_reward_redemptions ENABLE ROW LEVEL SECURITY;
-- growth_rewards
CREATE TABLE public.growth_rewards (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  code text NOT NULL,
  title text NOT NULL,
  description text,
  icon text DEFAULT '🎁'::text NOT NULL,
  reward_type text DEFAULT 'coupon'::text NOT NULL,
  point_cost integer NOT NULL,
  min_level text DEFAULT 'newbie'::text NOT NULL,
  required_achievement_id uuid,
  user_limit integer,
  total_limit integer,
  redeemed_count integer DEFAULT 0 NOT NULL,
  coupon_title text,
  coupon_description text,
  coupon_discount text,
  coupon_expires_days integer,
  enabled boolean DEFAULT true NOT NULL,
  sort_order integer DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  category text DEFAULT 'other'::text NOT NULL,
  available_from timestamp with time zone,
  available_until timestamp with time zone,
  CONSTRAINT growth_rewards_category_check CHECK (category = ANY (ARRAY['cash'::text, 'discount'::text, 'gift'::text, 'other'::text])),
  CONSTRAINT growth_rewards_code_key UNIQUE (code),
  CONSTRAINT growth_rewards_pkey PRIMARY KEY (id),
  CONSTRAINT growth_rewards_point_cost_check CHECK (point_cost > 0),
  CONSTRAINT growth_rewards_redeemed_count_check CHECK (redeemed_count >= 0),
  CONSTRAINT growth_rewards_required_achievement_id_fkey FOREIGN KEY (required_achievement_id) REFERENCES growth_achievements(id) ON DELETE SET NULL,
  CONSTRAINT growth_rewards_reward_type_check CHECK (reward_type = 'coupon'::text)
);
ALTER TABLE public.growth_rewards ENABLE ROW LEVEL SECURITY;
-- growth_tasks
CREATE TABLE public.growth_tasks (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  code text NOT NULL,
  title text NOT NULL,
  description text,
  task_type text NOT NULL,
  requirement_count integer DEFAULT 1 NOT NULL,
  reward_points integer DEFAULT 0 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  cycle_type text DEFAULT 'one_time'::text NOT NULL,
  start_at timestamp with time zone,
  end_at timestamp with time zone,
  CONSTRAINT growth_tasks_code_key UNIQUE (code),
  CONSTRAINT growth_tasks_cycle_type_check CHECK (cycle_type = ANY (ARRAY['one_time'::text, 'daily'::text, 'weekly'::text])),
  CONSTRAINT growth_tasks_pkey PRIMARY KEY (id),
  CONSTRAINT growth_tasks_requirement_count_check CHECK (requirement_count > 0),
  CONSTRAINT growth_tasks_reward_points_check CHECK (reward_points >= 0),
  CONSTRAINT growth_tasks_task_type_check CHECK (task_type = ANY (ARRAY['profile_complete'::text, 'first_registration'::text, 'first_result'::text, 'registration_count'::text, 'result_count'::text]))
);
ALTER TABLE public.growth_tasks ENABLE ROW LEVEL SECURITY;
-- growth_user_achievements
CREATE TABLE public.growth_user_achievements (
  user_id uuid NOT NULL,
  achievement_id uuid NOT NULL,
  unlocked_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT growth_user_achievements_achievement_id_fkey FOREIGN KEY (achievement_id) REFERENCES growth_achievements(id) ON DELETE CASCADE,
  CONSTRAINT growth_user_achievements_pkey PRIMARY KEY (user_id, achievement_id),
  CONSTRAINT growth_user_achievements_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.growth_user_achievements ENABLE ROW LEVEL SECURITY;
-- growth_user_tasks
CREATE TABLE public.growth_user_tasks (
  user_id uuid NOT NULL,
  task_id uuid NOT NULL,
  progress integer DEFAULT 0 NOT NULL,
  completed_at timestamp with time zone,
  cycle_key text DEFAULT 'once'::text NOT NULL,
  CONSTRAINT growth_user_tasks_pkey PRIMARY KEY (user_id, task_id, cycle_key),
  CONSTRAINT growth_user_tasks_task_id_fkey FOREIGN KEY (task_id) REFERENCES growth_tasks(id) ON DELETE CASCADE,
  CONSTRAINT growth_user_tasks_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.growth_user_tasks ENABLE ROW LEVEL SECURITY;
-- member_no_counter
CREATE TABLE public.member_no_counter (
  id boolean DEFAULT true NOT NULL,
  next_no integer NOT NULL,
  compacted boolean DEFAULT false NOT NULL,
  repair_version integer DEFAULT 0 NOT NULL,
  CONSTRAINT member_no_counter_id_check CHECK (id = true),
  CONSTRAINT member_no_counter_pkey PRIMARY KEY (id)
);
ALTER TABLE public.member_no_counter ENABLE ROW LEVEL SECURITY;
-- notifications
CREATE TABLE public.notifications (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id uuid,
  title text NOT NULL,
  content text NOT NULL,
  type text DEFAULT '一般'::text NOT NULL,
  read_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  ticket_id uuid,
  CONSTRAINT notifications_pkey PRIMARY KEY (id),
  CONSTRAINT notifications_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES support_tickets(id) ON DELETE SET NULL,
  CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
-- order_items
CREATE TABLE public.order_items (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  order_id uuid NOT NULL,
  product_id uuid,
  product_name text NOT NULL,
  unit_price numeric(12,2) DEFAULT 0 NOT NULL,
  quantity integer DEFAULT 1 NOT NULL,
  subtotal numeric(12,2) DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
  CONSTRAINT order_items_pkey PRIMARY KEY (id),
  CONSTRAINT order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL,
  CONSTRAINT order_items_quantity_check CHECK (quantity > 0),
  CONSTRAINT order_items_subtotal_check CHECK (subtotal >= 0::numeric),
  CONSTRAINT order_items_unit_price_check CHECK (unit_price >= 0::numeric)
);
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
-- orders
CREATE TABLE public.orders (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  order_no text DEFAULT ((('ORD-'::text || to_char(now(), 'YYYYMMDDHH24MISS'::text)) || '-'::text) || upper(substr(replace((gen_random_uuid())::text, '-'::text, ''::text), 1, 6))) NOT NULL,
  user_id uuid NOT NULL,
  status text DEFAULT 'pending_payment'::text NOT NULL,
  payment_method text DEFAULT 'cash'::text NOT NULL,
  total_amount numeric(12,2) DEFAULT 0 NOT NULL,
  note text,
  paid_at timestamp with time zone,
  completed_at timestamp with time zone,
  cancelled_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT orders_order_no_key UNIQUE (order_no),
  CONSTRAINT orders_payment_method_check CHECK (payment_method = 'cash'::text),
  CONSTRAINT orders_pkey PRIMARY KEY (id),
  CONSTRAINT orders_status_check CHECK (status = ANY (ARRAY['pending_payment'::text, 'paid'::text, 'completed'::text, 'cancelled'::text])),
  CONSTRAINT orders_total_amount_check CHECK (total_amount >= 0::numeric),
  CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
-- products
CREATE TABLE public.products (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  category text,
  price numeric(12,2) DEFAULT 0 NOT NULL,
  image_url text,
  description text,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT products_pkey PRIMARY KEY (id),
  CONSTRAINT products_price_check CHECK (price >= 0::numeric)
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
-- profiles
CREATE TABLE public.profiles (
  id uuid NOT NULL,
  role text DEFAULT 'visitor'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  nickname text,
  member_no integer,
  growth_points integer DEFAULT 0 NOT NULL,
  growth_level text DEFAULT 'newbie'::text NOT NULL,
  CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT profiles_pkey PRIMARY KEY (id),
  CONSTRAINT profiles_role_check CHECK (role = ANY (ARRAY['admin'::text, 'visitor'::text]))
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
-- quick_links
CREATE TABLE public.quick_links (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  url text NOT NULL,
  icon text,
  sort_order integer DEFAULT 1 NOT NULL,
  visible boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT quick_links_pkey PRIMARY KEY (id)
);
ALTER TABLE public.quick_links ENABLE ROW LEVEL SECURITY;
-- site_settings
CREATE TABLE public.site_settings (
  id integer DEFAULT 1 NOT NULL,
  site_name text DEFAULT '商業簡介'::text,
  hero_title text DEFAULT '商業簡介'::text,
  hero_text text DEFAULT '繽紛、活潑、充滿特色的專屬網站'::text,
  hero_image text DEFAULT '1000116817.jpg'::text,
  about_title text DEFAULT '✨ 商業簡介'::text,
  about_subtitle text DEFAULT '讓訪客快速了解你、你的品牌與網站'::text,
  about1_title text DEFAULT '🌟 我們是誰？'::text,
  about1_text text DEFAULT '在這裡介紹你的品牌、社群或作品。'::text,
  about2_title text DEFAULT '💫 我們的特色'::text,
  about2_text text DEFAULT '活潑的視覺設計、清楚的資訊分類與簡單方便的網站導覽。'::text,
  features_title text DEFAULT '⭐ 網站特色 ⭐'::text,
  features_subtitle text DEFAULT '用可愛的卡片展示你的內容'::text,
  f1_title text DEFAULT '角色／品牌'::text,
  f1_text text DEFAULT '放入角色、LOGO 或品牌介紹。'::text,
  f2_title text DEFAULT '精彩內容'::text,
  f2_text text DEFAULT '展示作品、活動或特色內容。'::text,
  f3_title text DEFAULT '活動挑戰'::text,
  f3_text text DEFAULT '放入活動、比賽或挑戰資訊。'::text,
  f4_title text DEFAULT '精彩企劃'::text,
  f4_text text DEFAULT '放置你的特色企劃與最新內容。'::text,
  contact1 text DEFAULT '📧 Email：example@email.com'::text,
  contact2 text DEFAULT '💬 社群：加入我們的社群'::text,
  contact3 text DEFAULT '📱 聯絡方式：請填入你的資訊'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT site_settings_pkey PRIMARY KEY (id)
);
ALTER TABLE public.site_settings ENABLE ROW LEVEL SECURITY;
-- support_tickets
CREATE TABLE public.support_tickets (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id uuid DEFAULT auth.uid() NOT NULL,
  subject text NOT NULL,
  message text NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  admin_reply text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT support_tickets_pkey PRIMARY KEY (id),
  CONSTRAINT support_tickets_status_check CHECK (status = ANY (ARRAY['open'::text, 'answered'::text, 'closed'::text])),
  CONSTRAINT support_tickets_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;
-- user_activity_badges
CREATE TABLE public.user_activity_badges (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id uuid NOT NULL,
  badge_id uuid NOT NULL,
  unlocked_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT user_activity_badges_badge_id_fkey FOREIGN KEY (badge_id) REFERENCES activity_badges(id) ON DELETE CASCADE,
  CONSTRAINT user_activity_badges_pkey PRIMARY KEY (id),
  CONSTRAINT user_activity_badges_user_id_badge_id_key UNIQUE (user_id, badge_id),
  CONSTRAINT user_activity_badges_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.user_activity_badges ENABLE ROW LEVEL SECURITY;
-- videos
CREATE TABLE public.videos (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  title text NOT NULL,
  description text DEFAULT ''::text NOT NULL,
  youtube_url text NOT NULL,
  youtube_id text NOT NULL,
  thumbnail_url text NOT NULL,
  category text DEFAULT '其他'::text NOT NULL,
  featured boolean DEFAULT false NOT NULL,
  published boolean DEFAULT true NOT NULL,
  sort_order integer DEFAULT 0 NOT NULL,
  published_at timestamp with time zone DEFAULT now() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT videos_pkey PRIMARY KEY (id)
);
ALTER TABLE public.videos ENABLE ROW LEVEL SECURITY;
-- visitor_accounts
CREATE TABLE public.visitor_accounts (
  id uuid NOT NULL,
  email text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  is_active boolean DEFAULT true NOT NULL,
  name text,
  CONSTRAINT visitor_accounts_email_key UNIQUE (email),
  CONSTRAINT visitor_accounts_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT visitor_accounts_pkey PRIMARY KEY (id)
);
ALTER TABLE public.visitor_accounts ENABLE ROW LEVEL SECURITY;
-- visitor_profiles
CREATE TABLE public.visitor_profiles (
  id uuid NOT NULL,
  username text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT visitor_profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT visitor_profiles_pkey PRIMARY KEY (id),
  CONSTRAINT visitor_profiles_username_key UNIQUE (username)
);
ALTER TABLE public.visitor_profiles ENABLE ROW LEVEL SECURITY;

-- Non-constraint indexes
CREATE INDEX announcement_reads_user_idx ON public.announcement_reads USING btree (user_id);
CREATE INDEX announcements_calendar_event_date_idx ON public.announcements USING btree (event_date) WHERE ((published = true) AND (event_date_confirmed = true));
CREATE INDEX competition_attendance_competition_idx ON public.competition_attendance USING btree (competition_id, status);
CREATE INDEX competition_attendance_user_idx ON public.competition_attendance USING btree (user_id, created_at DESC);
CREATE INDEX competition_categories_name_idx ON public.competition_categories USING btree (name);
CREATE INDEX competition_registrations_competition_idx ON public.competition_registrations USING btree (competition_id, created_at DESC);
CREATE INDEX competition_registrations_status_idx ON public.competition_registrations USING btree (competition_id, status);
CREATE INDEX competition_registrations_user_idx ON public.competition_registrations USING btree (user_id, created_at DESC);
CREATE INDEX competition_results_competition_idx ON public.competition_results USING btree (competition_id);
CREATE INDEX competition_results_place_idx ON public.competition_results USING btree (competition_id, place);
CREATE INDEX competition_results_user_idx ON public.competition_results USING btree (user_id);
CREATE INDEX competition_reward_grants_user_idx ON public.competition_reward_grants USING btree (user_id, granted_at DESC);
CREATE INDEX competition_reward_rules_comp_idx ON public.competition_reward_rules USING btree (competition_id, enabled);
CREATE INDEX competition_waitlist_queue_idx ON public.competition_waitlist USING btree (competition_id, status, "position", created_at);
CREATE INDEX competitions_category_idx ON public.competitions USING btree (category);
CREATE UNIQUE INDEX competitions_checkin_code_uq ON public.competitions USING btree (checkin_code) WHERE ((checkin_code IS NOT NULL) AND (checkin_code <> ''::text));
CREATE INDEX competitions_published_idx ON public.competitions USING btree (published, published_at);
CREATE INDEX competitions_registration_deadline_idx ON public.competitions USING btree (registration_deadline);
CREATE INDEX coupons_expires_at_idx ON public.coupons USING btree (expires_at);
CREATE INDEX coupons_used_idx ON public.coupons USING btree (used);
CREATE INDEX coupons_user_id_idx ON public.coupons USING btree (user_id);
CREATE INDEX device_push_tokens_user_id_idx ON public.device_push_tokens USING btree (user_id);
CREATE INDEX download_files_provider_idx ON public.download_files USING btree (storage_provider);
CREATE INDEX download_files_published_idx ON public.download_files USING btree (published, created_at DESC);
CREATE INDEX form_answers_response_idx ON public.form_answers USING btree (response_id);
CREATE INDEX form_questions_form_idx ON public.form_questions USING btree (form_id, sort_order);
CREATE INDEX form_responses_form_idx ON public.form_responses USING btree (form_id, created_at);
CREATE INDEX forms_published_idx ON public.forms USING btree (published);
CREATE INDEX growth_achievement_unlock_history_user_idx ON public.growth_achievement_unlock_history USING btree (user_id, archived_at DESC);
CREATE INDEX growth_activity_days_user_date_idx ON public.growth_activity_days USING btree (user_id, activity_date DESC);
CREATE INDEX idx_growth_activity_days_user_date ON public.growth_activity_days USING btree (user_id, activity_date DESC);
CREATE INDEX growth_points_user_idx ON public.growth_point_transactions USING btree (user_id, created_at DESC);
CREATE INDEX growth_reset_history_user_idx ON public.growth_reset_history USING btree (user_id, created_at DESC);
CREATE INDEX growth_reward_redemptions_reward_idx ON public.growth_reward_redemptions USING btree (reward_id, created_at DESC);
CREATE INDEX growth_reward_redemptions_user_idx ON public.growth_reward_redemptions USING btree (user_id, created_at DESC);
CREATE INDEX growth_rewards_active_window_idx ON public.growth_rewards USING btree (enabled, available_from, available_until, sort_order);
CREATE INDEX growth_user_achievements_user_idx ON public.growth_user_achievements USING btree (user_id, unlocked_at DESC);
CREATE INDEX growth_user_tasks_cycle_idx ON public.growth_user_tasks USING btree (user_id, task_id, cycle_key);
CREATE INDEX growth_user_tasks_user_idx ON public.growth_user_tasks USING btree (user_id);
CREATE INDEX notifications_ticket_idx ON public.notifications USING btree (ticket_id);
CREATE INDEX notifications_user_idx ON public.notifications USING btree (user_id, created_at DESC);
CREATE INDEX idx_order_items_order ON public.order_items USING btree (order_id);
CREATE INDEX idx_orders_status_created ON public.orders USING btree (status, created_at DESC);
CREATE INDEX idx_orders_user_created ON public.orders USING btree (user_id, created_at DESC);
CREATE UNIQUE INDEX profiles_member_no_uidx ON public.profiles USING btree (member_no) WHERE (member_no IS NOT NULL);
CREATE INDEX support_tickets_status_idx ON public.support_tickets USING btree (status);
CREATE INDEX user_activity_badges_user_idx ON public.user_activity_badges USING btree (user_id, unlocked_at DESC);
CREATE INDEX videos_category_idx ON public.videos USING btree (category);
CREATE INDEX videos_public_idx ON public.videos USING btree (published, featured, sort_order, published_at DESC);

-- RLS policies
CREATE POLICY activity_badges_public_select ON public.activity_badges AS permissive FOR SELECT TO authenticated USING (((active = true) OR (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));
CREATE POLICY ai_announcement_generations_owner_insert ON public.ai_announcement_generations AS permissive FOR INSERT TO public WITH CHECK ((auth.uid() = user_id));
CREATE POLICY ai_announcement_generations_owner_select ON public.ai_announcement_generations AS permissive FOR SELECT TO public USING ((auth.uid() = user_id));
CREATE POLICY announcement_read_owner_insert ON public.announcement_reads AS permissive FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));
CREATE POLICY announcement_read_owner_select ON public.announcement_reads AS permissive FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR is_admin()));
CREATE POLICY announcement_admin_all ON public.announcements AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY announcement_authenticated_read ON public.announcements AS permissive FOR SELECT TO authenticated USING (true);
CREATE POLICY announcement_public_published_read ON public.announcements AS permissive FOR SELECT TO anon USING (((published = true) AND (published_at <= now())));
CREATE POLICY "Admins can delete app releases" ON public.app_releases AS permissive FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))));
CREATE POLICY "Admins can insert app releases" ON public.app_releases AS permissive FOR INSERT TO authenticated WITH CHECK (((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))) AND ((created_by IS NULL) OR (created_by = auth.uid()))));
CREATE POLICY "Admins can read all app releases" ON public.app_releases AS permissive FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))));
CREATE POLICY "Admins can update app releases" ON public.app_releases AS permissive FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))));
CREATE POLICY "Public can read published app releases" ON public.app_releases AS permissive FOR SELECT TO anon, authenticated USING ((published = true));
CREATE POLICY attendance_admin_all ON public.competition_attendance AS permissive FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))));
CREATE POLICY attendance_member_select ON public.competition_attendance AS permissive FOR SELECT TO authenticated USING ((user_id = auth.uid()));
CREATE POLICY competition_categories_admin_all ON public.competition_categories AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY competition_categories_admin_delete ON public.competition_categories AS permissive FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));
CREATE POLICY competition_categories_admin_insert ON public.competition_categories AS permissive FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));
CREATE POLICY competition_categories_admin_update ON public.competition_categories AS permissive FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));
CREATE POLICY competition_categories_public_select ON public.competition_categories AS permissive FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY competition_registrations_delete ON public.competition_registrations AS permissive FOR DELETE TO authenticated USING (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));
CREATE POLICY competition_registrations_insert ON public.competition_registrations AS permissive FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));
CREATE POLICY competition_registrations_owner_delete ON public.competition_registrations AS permissive FOR DELETE TO authenticated USING (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));
CREATE POLICY competition_registrations_owner_insert ON public.competition_registrations AS permissive FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));
CREATE POLICY competition_registrations_owner_select ON public.competition_registrations AS permissive FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));
CREATE POLICY competition_registrations_owner_update ON public.competition_registrations AS permissive FOR UPDATE TO authenticated USING (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))))) WITH CHECK (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));
CREATE POLICY competition_registrations_select ON public.competition_registrations AS permissive FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));
CREATE POLICY competition_registrations_update ON public.competition_registrations AS permissive FOR UPDATE TO authenticated USING (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))))) WITH CHECK (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));
CREATE POLICY competition_result_admin_all ON public.competition_results AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY competition_result_public_read ON public.competition_results AS permissive FOR SELECT TO public USING ((is_admin() OR (user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM competitions c
  WHERE ((c.id = competition_results.competition_id) AND (c.published = true) AND ((c.published_at IS NULL) OR (c.published_at <= now())))))));
CREATE POLICY reward_grants_admin_all ON public.competition_reward_grants AS permissive FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))));
CREATE POLICY reward_grants_member_select ON public.competition_reward_grants AS permissive FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));
CREATE POLICY reward_rules_admin_all ON public.competition_reward_rules AS permissive FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))));
CREATE POLICY reward_rules_member_select ON public.competition_reward_rules AS permissive FOR SELECT TO authenticated USING (true);
CREATE POLICY waitlist_admin_all ON public.competition_waitlist AS permissive FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))));
CREATE POLICY waitlist_member_select ON public.competition_waitlist AS permissive FOR SELECT TO authenticated USING ((user_id = auth.uid()));
CREATE POLICY competition_admin_all ON public.competitions AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY competition_public_read ON public.competitions AS permissive FOR SELECT TO public USING ((is_admin() OR ((published = true) AND ((published_at IS NULL) OR (published_at <= now())))));
CREATE POLICY coupon_admin_all ON public.coupons AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY coupon_owner_read ON public.coupons AS permissive FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR is_admin()));
CREATE POLICY "Users can refresh their own Android push tokens" ON public.device_push_tokens AS permissive FOR UPDATE TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));
CREATE POLICY "Users can register their own Android push tokens" ON public.device_push_tokens AS permissive FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));
CREATE POLICY "Users can view their own Android push tokens" ON public.device_push_tokens AS permissive FOR SELECT TO authenticated USING ((user_id = auth.uid()));
CREATE POLICY download_files_admin_all ON public.download_files AS permissive FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))));
CREATE POLICY download_files_public_select ON public.download_files AS permissive FOR SELECT TO authenticated USING (((published = true) OR (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));
CREATE POLICY form_answers_admin_all ON public.form_answers AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY form_answers_insert ON public.form_answers AS permissive FOR INSERT TO public WITH CHECK ((EXISTS ( SELECT 1
   FROM form_responses r
  WHERE ((r.id = form_answers.response_id) AND ((r.user_id = auth.uid()) OR (r.user_id IS NULL))))));
CREATE POLICY form_answers_owner_read ON public.form_answers AS permissive FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM form_responses r
  WHERE ((r.id = form_answers.response_id) AND ((r.user_id = auth.uid()) OR is_admin())))));
CREATE POLICY form_questions_admin_all ON public.form_questions AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY form_questions_public_read ON public.form_questions AS permissive FOR SELECT TO public USING ((EXISTS ( SELECT 1
   FROM forms f
  WHERE ((f.id = form_questions.form_id) AND ((f.published = true) OR is_admin())))));
CREATE POLICY form_responses_admin_all ON public.form_responses AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY form_responses_insert ON public.form_responses AS permissive FOR INSERT TO public WITH CHECK (((EXISTS ( SELECT 1
   FROM forms f
  WHERE ((f.id = form_responses.form_id) AND (f.published = true)))) AND ((user_id IS NULL) OR (user_id = auth.uid()))));
CREATE POLICY form_responses_owner_read ON public.form_responses AS permissive FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR is_admin()));
CREATE POLICY forms_admin_all ON public.forms AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY forms_public_read ON public.forms AS permissive FOR SELECT TO public USING (((published = true) OR is_admin()));
CREATE POLICY growth_achievement_unlock_history_admin_all ON public.growth_achievement_unlock_history AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY growth_achievements_admin_all ON public.growth_achievements AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY growth_achievements_read ON public.growth_achievements AS permissive FOR SELECT TO authenticated USING ((active OR is_admin()));
CREATE POLICY growth_activity_days_owner ON public.growth_activity_days AS permissive FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR is_admin()));
CREATE POLICY growth_activity_days_select_own ON public.growth_activity_days AS permissive FOR SELECT TO authenticated USING ((user_id = auth.uid()));
CREATE POLICY growth_levels_public_read ON public.growth_levels AS permissive FOR SELECT TO authenticated USING (true);
CREATE POLICY growth_points_admin_all ON public.growth_point_transactions AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY growth_points_owner_read ON public.growth_point_transactions AS permissive FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR is_admin()));
CREATE POLICY growth_reset_history_admin_all ON public.growth_reset_history AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY growth_reward_redemptions_admin_all ON public.growth_reward_redemptions AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY growth_reward_redemptions_owner_read ON public.growth_reward_redemptions AS permissive FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR is_admin()));
CREATE POLICY growth_rewards_admin_all ON public.growth_rewards AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY growth_rewards_read ON public.growth_rewards AS permissive FOR SELECT TO authenticated USING ((enabled OR is_admin()));
CREATE POLICY growth_tasks_admin_all ON public.growth_tasks AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY growth_tasks_read ON public.growth_tasks AS permissive FOR SELECT TO authenticated USING ((active OR is_admin()));
CREATE POLICY growth_user_achievements_owner ON public.growth_user_achievements AS permissive FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR is_admin()));
CREATE POLICY growth_user_tasks_owner ON public.growth_user_tasks AS permissive FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR is_admin()));
CREATE POLICY notification_admin_all ON public.notifications AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY notification_owner_delete ON public.notifications AS permissive FOR DELETE TO authenticated USING ((user_id = auth.uid()));
CREATE POLICY notification_owner_read ON public.notifications AS permissive FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR is_admin()));
CREATE POLICY notification_owner_update ON public.notifications AS permissive FOR UPDATE TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));
CREATE POLICY order_items_admin_all ON public.order_items AS permissive FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));
CREATE POLICY order_items_member_select ON public.order_items AS permissive FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM orders o
  WHERE ((o.id = order_items.order_id) AND ((o.user_id = auth.uid()) OR (EXISTS ( SELECT 1
           FROM profiles
          WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))))))));
CREATE POLICY orders_admin_all ON public.orders AS permissive FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));
CREATE POLICY orders_member_select ON public.orders AS permissive FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text))))));
CREATE POLICY product_admin_all ON public.products AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY product_public_read ON public.products AS permissive FOR SELECT TO public USING ((is_admin() OR (active = true)));
CREATE POLICY profile_admin_all ON public.profiles AS permissive FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY profile_self_read ON public.profiles AS permissive FOR SELECT TO authenticated USING (((id = auth.uid()) OR is_admin()));
CREATE POLICY profile_self_update ON public.profiles AS permissive FOR UPDATE TO authenticated USING ((id = auth.uid())) WITH CHECK (((id = auth.uid()) AND (role = 'visitor'::text)));
CREATE POLICY quick_links_admin_all ON public.quick_links AS permissive FOR ALL TO public USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY quick_links_public_read ON public.quick_links AS permissive FOR SELECT TO public USING ((visible = true));
CREATE POLICY site_admin_update ON public.site_settings AS permissive FOR UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY site_public_read ON public.site_settings AS permissive FOR SELECT TO public USING (true);
CREATE POLICY ticket_admin_all ON public.support_tickets AS permissive FOR UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY ticket_admin_delete ON public.support_tickets AS permissive FOR DELETE TO authenticated USING (is_admin());
CREATE POLICY ticket_owner_insert ON public.support_tickets AS permissive FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));
CREATE POLICY ticket_owner_read ON public.support_tickets AS permissive FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR is_admin()));
CREATE POLICY user_activity_badges_admin_all ON public.user_activity_badges AS permissive FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))));
CREATE POLICY user_activity_badges_member_select ON public.user_activity_badges AS permissive FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));
CREATE POLICY videos_admin_read ON public.videos AS permissive FOR SELECT TO authenticated USING (is_admin_user());
CREATE POLICY videos_public_read ON public.videos AS permissive FOR SELECT TO public USING ((published = true));
CREATE POLICY visitor_admin_read ON public.visitor_accounts AS permissive FOR SELECT TO authenticated USING (is_admin());

-- Table grants
GRANT DELETE ON TABLE public.activity_badges TO anon;
GRANT INSERT ON TABLE public.activity_badges TO anon;
GRANT REFERENCES ON TABLE public.activity_badges TO anon;
GRANT SELECT ON TABLE public.activity_badges TO anon;
GRANT TRIGGER ON TABLE public.activity_badges TO anon;
GRANT TRUNCATE ON TABLE public.activity_badges TO anon;
GRANT UPDATE ON TABLE public.activity_badges TO anon;
GRANT DELETE ON TABLE public.activity_badges TO authenticated;
GRANT INSERT ON TABLE public.activity_badges TO authenticated;
GRANT REFERENCES ON TABLE public.activity_badges TO authenticated;
GRANT SELECT ON TABLE public.activity_badges TO authenticated;
GRANT TRIGGER ON TABLE public.activity_badges TO authenticated;
GRANT TRUNCATE ON TABLE public.activity_badges TO authenticated;
GRANT UPDATE ON TABLE public.activity_badges TO authenticated;
GRANT DELETE ON TABLE public.activity_badges TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.activity_badges TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.activity_badges TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.activity_badges TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.activity_badges TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.activity_badges TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.activity_badges TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.activity_badges TO service_role;
GRANT INSERT ON TABLE public.activity_badges TO service_role;
GRANT REFERENCES ON TABLE public.activity_badges TO service_role;
GRANT SELECT ON TABLE public.activity_badges TO service_role;
GRANT TRIGGER ON TABLE public.activity_badges TO service_role;
GRANT TRUNCATE ON TABLE public.activity_badges TO service_role;
GRANT UPDATE ON TABLE public.activity_badges TO service_role;
GRANT DELETE ON TABLE public.activity_member_stats TO anon;
GRANT INSERT ON TABLE public.activity_member_stats TO anon;
GRANT REFERENCES ON TABLE public.activity_member_stats TO anon;
GRANT SELECT ON TABLE public.activity_member_stats TO anon;
GRANT TRIGGER ON TABLE public.activity_member_stats TO anon;
GRANT TRUNCATE ON TABLE public.activity_member_stats TO anon;
GRANT UPDATE ON TABLE public.activity_member_stats TO anon;
GRANT DELETE ON TABLE public.activity_member_stats TO authenticated;
GRANT INSERT ON TABLE public.activity_member_stats TO authenticated;
GRANT REFERENCES ON TABLE public.activity_member_stats TO authenticated;
GRANT SELECT ON TABLE public.activity_member_stats TO authenticated;
GRANT TRIGGER ON TABLE public.activity_member_stats TO authenticated;
GRANT TRUNCATE ON TABLE public.activity_member_stats TO authenticated;
GRANT UPDATE ON TABLE public.activity_member_stats TO authenticated;
GRANT DELETE ON TABLE public.activity_member_stats TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.activity_member_stats TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.activity_member_stats TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.activity_member_stats TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.activity_member_stats TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.activity_member_stats TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.activity_member_stats TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.activity_member_stats TO service_role;
GRANT INSERT ON TABLE public.activity_member_stats TO service_role;
GRANT REFERENCES ON TABLE public.activity_member_stats TO service_role;
GRANT SELECT ON TABLE public.activity_member_stats TO service_role;
GRANT TRIGGER ON TABLE public.activity_member_stats TO service_role;
GRANT TRUNCATE ON TABLE public.activity_member_stats TO service_role;
GRANT UPDATE ON TABLE public.activity_member_stats TO service_role;
GRANT DELETE ON TABLE public.ai_announcement_generations TO anon;
GRANT INSERT ON TABLE public.ai_announcement_generations TO anon;
GRANT REFERENCES ON TABLE public.ai_announcement_generations TO anon;
GRANT SELECT ON TABLE public.ai_announcement_generations TO anon;
GRANT TRIGGER ON TABLE public.ai_announcement_generations TO anon;
GRANT TRUNCATE ON TABLE public.ai_announcement_generations TO anon;
GRANT UPDATE ON TABLE public.ai_announcement_generations TO anon;
GRANT DELETE ON TABLE public.ai_announcement_generations TO authenticated;
GRANT INSERT ON TABLE public.ai_announcement_generations TO authenticated;
GRANT REFERENCES ON TABLE public.ai_announcement_generations TO authenticated;
GRANT SELECT ON TABLE public.ai_announcement_generations TO authenticated;
GRANT TRIGGER ON TABLE public.ai_announcement_generations TO authenticated;
GRANT TRUNCATE ON TABLE public.ai_announcement_generations TO authenticated;
GRANT UPDATE ON TABLE public.ai_announcement_generations TO authenticated;
GRANT DELETE ON TABLE public.ai_announcement_generations TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.ai_announcement_generations TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.ai_announcement_generations TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.ai_announcement_generations TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.ai_announcement_generations TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.ai_announcement_generations TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.ai_announcement_generations TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.ai_announcement_generations TO service_role;
GRANT INSERT ON TABLE public.ai_announcement_generations TO service_role;
GRANT REFERENCES ON TABLE public.ai_announcement_generations TO service_role;
GRANT SELECT ON TABLE public.ai_announcement_generations TO service_role;
GRANT TRIGGER ON TABLE public.ai_announcement_generations TO service_role;
GRANT TRUNCATE ON TABLE public.ai_announcement_generations TO service_role;
GRANT UPDATE ON TABLE public.ai_announcement_generations TO service_role;
GRANT DELETE ON TABLE public.announcement_reads TO anon;
GRANT INSERT ON TABLE public.announcement_reads TO anon;
GRANT REFERENCES ON TABLE public.announcement_reads TO anon;
GRANT SELECT ON TABLE public.announcement_reads TO anon;
GRANT TRIGGER ON TABLE public.announcement_reads TO anon;
GRANT TRUNCATE ON TABLE public.announcement_reads TO anon;
GRANT UPDATE ON TABLE public.announcement_reads TO anon;
GRANT DELETE ON TABLE public.announcement_reads TO authenticated;
GRANT INSERT ON TABLE public.announcement_reads TO authenticated;
GRANT REFERENCES ON TABLE public.announcement_reads TO authenticated;
GRANT SELECT ON TABLE public.announcement_reads TO authenticated;
GRANT TRIGGER ON TABLE public.announcement_reads TO authenticated;
GRANT TRUNCATE ON TABLE public.announcement_reads TO authenticated;
GRANT UPDATE ON TABLE public.announcement_reads TO authenticated;
GRANT DELETE ON TABLE public.announcement_reads TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.announcement_reads TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.announcement_reads TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.announcement_reads TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.announcement_reads TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.announcement_reads TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.announcement_reads TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.announcement_reads TO service_role;
GRANT INSERT ON TABLE public.announcement_reads TO service_role;
GRANT REFERENCES ON TABLE public.announcement_reads TO service_role;
GRANT SELECT ON TABLE public.announcement_reads TO service_role;
GRANT TRIGGER ON TABLE public.announcement_reads TO service_role;
GRANT TRUNCATE ON TABLE public.announcement_reads TO service_role;
GRANT UPDATE ON TABLE public.announcement_reads TO service_role;
GRANT SELECT ON TABLE public.announcements TO anon;
GRANT DELETE ON TABLE public.announcements TO authenticated;
GRANT INSERT ON TABLE public.announcements TO authenticated;
GRANT SELECT ON TABLE public.announcements TO authenticated;
GRANT UPDATE ON TABLE public.announcements TO authenticated;
GRANT DELETE ON TABLE public.announcements TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.announcements TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.announcements TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.announcements TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.announcements TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.announcements TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.announcements TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.announcements TO service_role;
GRANT INSERT ON TABLE public.announcements TO service_role;
GRANT REFERENCES ON TABLE public.announcements TO service_role;
GRANT SELECT ON TABLE public.announcements TO service_role;
GRANT TRIGGER ON TABLE public.announcements TO service_role;
GRANT TRUNCATE ON TABLE public.announcements TO service_role;
GRANT UPDATE ON TABLE public.announcements TO service_role;
GRANT DELETE ON TABLE public.app_releases TO anon;
GRANT INSERT ON TABLE public.app_releases TO anon;
GRANT REFERENCES ON TABLE public.app_releases TO anon;
GRANT SELECT ON TABLE public.app_releases TO anon;
GRANT TRIGGER ON TABLE public.app_releases TO anon;
GRANT TRUNCATE ON TABLE public.app_releases TO anon;
GRANT UPDATE ON TABLE public.app_releases TO anon;
GRANT DELETE ON TABLE public.app_releases TO authenticated;
GRANT INSERT ON TABLE public.app_releases TO authenticated;
GRANT REFERENCES ON TABLE public.app_releases TO authenticated;
GRANT SELECT ON TABLE public.app_releases TO authenticated;
GRANT TRIGGER ON TABLE public.app_releases TO authenticated;
GRANT TRUNCATE ON TABLE public.app_releases TO authenticated;
GRANT UPDATE ON TABLE public.app_releases TO authenticated;
GRANT DELETE ON TABLE public.app_releases TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.app_releases TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.app_releases TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.app_releases TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.app_releases TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.app_releases TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.app_releases TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.app_releases TO service_role;
GRANT INSERT ON TABLE public.app_releases TO service_role;
GRANT REFERENCES ON TABLE public.app_releases TO service_role;
GRANT SELECT ON TABLE public.app_releases TO service_role;
GRANT TRIGGER ON TABLE public.app_releases TO service_role;
GRANT TRUNCATE ON TABLE public.app_releases TO service_role;
GRANT UPDATE ON TABLE public.app_releases TO service_role;
GRANT DELETE ON TABLE public.competition_attendance TO anon;
GRANT INSERT ON TABLE public.competition_attendance TO anon;
GRANT REFERENCES ON TABLE public.competition_attendance TO anon;
GRANT SELECT ON TABLE public.competition_attendance TO anon;
GRANT TRIGGER ON TABLE public.competition_attendance TO anon;
GRANT TRUNCATE ON TABLE public.competition_attendance TO anon;
GRANT UPDATE ON TABLE public.competition_attendance TO anon;
GRANT DELETE ON TABLE public.competition_attendance TO authenticated;
GRANT INSERT ON TABLE public.competition_attendance TO authenticated;
GRANT REFERENCES ON TABLE public.competition_attendance TO authenticated;
GRANT SELECT ON TABLE public.competition_attendance TO authenticated;
GRANT TRIGGER ON TABLE public.competition_attendance TO authenticated;
GRANT TRUNCATE ON TABLE public.competition_attendance TO authenticated;
GRANT UPDATE ON TABLE public.competition_attendance TO authenticated;
GRANT DELETE ON TABLE public.competition_attendance TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.competition_attendance TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.competition_attendance TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.competition_attendance TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.competition_attendance TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.competition_attendance TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.competition_attendance TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.competition_attendance TO service_role;
GRANT INSERT ON TABLE public.competition_attendance TO service_role;
GRANT REFERENCES ON TABLE public.competition_attendance TO service_role;
GRANT SELECT ON TABLE public.competition_attendance TO service_role;
GRANT TRIGGER ON TABLE public.competition_attendance TO service_role;
GRANT TRUNCATE ON TABLE public.competition_attendance TO service_role;
GRANT UPDATE ON TABLE public.competition_attendance TO service_role;
GRANT DELETE ON TABLE public.competition_categories TO anon;
GRANT INSERT ON TABLE public.competition_categories TO anon;
GRANT REFERENCES ON TABLE public.competition_categories TO anon;
GRANT SELECT ON TABLE public.competition_categories TO anon;
GRANT TRIGGER ON TABLE public.competition_categories TO anon;
GRANT TRUNCATE ON TABLE public.competition_categories TO anon;
GRANT UPDATE ON TABLE public.competition_categories TO anon;
GRANT DELETE ON TABLE public.competition_categories TO authenticated;
GRANT INSERT ON TABLE public.competition_categories TO authenticated;
GRANT REFERENCES ON TABLE public.competition_categories TO authenticated;
GRANT SELECT ON TABLE public.competition_categories TO authenticated;
GRANT TRIGGER ON TABLE public.competition_categories TO authenticated;
GRANT TRUNCATE ON TABLE public.competition_categories TO authenticated;
GRANT UPDATE ON TABLE public.competition_categories TO authenticated;
GRANT DELETE ON TABLE public.competition_categories TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.competition_categories TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.competition_categories TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.competition_categories TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.competition_categories TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.competition_categories TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.competition_categories TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.competition_categories TO service_role;
GRANT INSERT ON TABLE public.competition_categories TO service_role;
GRANT REFERENCES ON TABLE public.competition_categories TO service_role;
GRANT SELECT ON TABLE public.competition_categories TO service_role;
GRANT TRIGGER ON TABLE public.competition_categories TO service_role;
GRANT TRUNCATE ON TABLE public.competition_categories TO service_role;
GRANT UPDATE ON TABLE public.competition_categories TO service_role;
GRANT DELETE ON TABLE public.competition_registrations TO anon;
GRANT INSERT ON TABLE public.competition_registrations TO anon;
GRANT REFERENCES ON TABLE public.competition_registrations TO anon;
GRANT SELECT ON TABLE public.competition_registrations TO anon;
GRANT TRIGGER ON TABLE public.competition_registrations TO anon;
GRANT TRUNCATE ON TABLE public.competition_registrations TO anon;
GRANT UPDATE ON TABLE public.competition_registrations TO anon;
GRANT DELETE ON TABLE public.competition_registrations TO authenticated;
GRANT INSERT ON TABLE public.competition_registrations TO authenticated;
GRANT REFERENCES ON TABLE public.competition_registrations TO authenticated;
GRANT SELECT ON TABLE public.competition_registrations TO authenticated;
GRANT TRIGGER ON TABLE public.competition_registrations TO authenticated;
GRANT TRUNCATE ON TABLE public.competition_registrations TO authenticated;
GRANT UPDATE ON TABLE public.competition_registrations TO authenticated;
GRANT DELETE ON TABLE public.competition_registrations TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.competition_registrations TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.competition_registrations TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.competition_registrations TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.competition_registrations TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.competition_registrations TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.competition_registrations TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.competition_registrations TO service_role;
GRANT INSERT ON TABLE public.competition_registrations TO service_role;
GRANT REFERENCES ON TABLE public.competition_registrations TO service_role;
GRANT SELECT ON TABLE public.competition_registrations TO service_role;
GRANT TRIGGER ON TABLE public.competition_registrations TO service_role;
GRANT TRUNCATE ON TABLE public.competition_registrations TO service_role;
GRANT UPDATE ON TABLE public.competition_registrations TO service_role;
GRANT DELETE ON TABLE public.competition_results TO anon;
GRANT INSERT ON TABLE public.competition_results TO anon;
GRANT REFERENCES ON TABLE public.competition_results TO anon;
GRANT SELECT ON TABLE public.competition_results TO anon;
GRANT TRIGGER ON TABLE public.competition_results TO anon;
GRANT TRUNCATE ON TABLE public.competition_results TO anon;
GRANT UPDATE ON TABLE public.competition_results TO anon;
GRANT DELETE ON TABLE public.competition_results TO authenticated;
GRANT INSERT ON TABLE public.competition_results TO authenticated;
GRANT REFERENCES ON TABLE public.competition_results TO authenticated;
GRANT SELECT ON TABLE public.competition_results TO authenticated;
GRANT TRIGGER ON TABLE public.competition_results TO authenticated;
GRANT TRUNCATE ON TABLE public.competition_results TO authenticated;
GRANT UPDATE ON TABLE public.competition_results TO authenticated;
GRANT DELETE ON TABLE public.competition_results TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.competition_results TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.competition_results TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.competition_results TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.competition_results TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.competition_results TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.competition_results TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.competition_results TO service_role;
GRANT INSERT ON TABLE public.competition_results TO service_role;
GRANT REFERENCES ON TABLE public.competition_results TO service_role;
GRANT SELECT ON TABLE public.competition_results TO service_role;
GRANT TRIGGER ON TABLE public.competition_results TO service_role;
GRANT TRUNCATE ON TABLE public.competition_results TO service_role;
GRANT UPDATE ON TABLE public.competition_results TO service_role;
GRANT DELETE ON TABLE public.competition_reward_grants TO anon;
GRANT INSERT ON TABLE public.competition_reward_grants TO anon;
GRANT REFERENCES ON TABLE public.competition_reward_grants TO anon;
GRANT SELECT ON TABLE public.competition_reward_grants TO anon;
GRANT TRIGGER ON TABLE public.competition_reward_grants TO anon;
GRANT TRUNCATE ON TABLE public.competition_reward_grants TO anon;
GRANT UPDATE ON TABLE public.competition_reward_grants TO anon;
GRANT DELETE ON TABLE public.competition_reward_grants TO authenticated;
GRANT INSERT ON TABLE public.competition_reward_grants TO authenticated;
GRANT REFERENCES ON TABLE public.competition_reward_grants TO authenticated;
GRANT SELECT ON TABLE public.competition_reward_grants TO authenticated;
GRANT TRIGGER ON TABLE public.competition_reward_grants TO authenticated;
GRANT TRUNCATE ON TABLE public.competition_reward_grants TO authenticated;
GRANT UPDATE ON TABLE public.competition_reward_grants TO authenticated;
GRANT DELETE ON TABLE public.competition_reward_grants TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.competition_reward_grants TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.competition_reward_grants TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.competition_reward_grants TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.competition_reward_grants TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.competition_reward_grants TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.competition_reward_grants TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.competition_reward_grants TO service_role;
GRANT INSERT ON TABLE public.competition_reward_grants TO service_role;
GRANT REFERENCES ON TABLE public.competition_reward_grants TO service_role;
GRANT SELECT ON TABLE public.competition_reward_grants TO service_role;
GRANT TRIGGER ON TABLE public.competition_reward_grants TO service_role;
GRANT TRUNCATE ON TABLE public.competition_reward_grants TO service_role;
GRANT UPDATE ON TABLE public.competition_reward_grants TO service_role;
GRANT DELETE ON TABLE public.competition_reward_rules TO anon;
GRANT INSERT ON TABLE public.competition_reward_rules TO anon;
GRANT REFERENCES ON TABLE public.competition_reward_rules TO anon;
GRANT SELECT ON TABLE public.competition_reward_rules TO anon;
GRANT TRIGGER ON TABLE public.competition_reward_rules TO anon;
GRANT TRUNCATE ON TABLE public.competition_reward_rules TO anon;
GRANT UPDATE ON TABLE public.competition_reward_rules TO anon;
GRANT DELETE ON TABLE public.competition_reward_rules TO authenticated;
GRANT INSERT ON TABLE public.competition_reward_rules TO authenticated;
GRANT REFERENCES ON TABLE public.competition_reward_rules TO authenticated;
GRANT SELECT ON TABLE public.competition_reward_rules TO authenticated;
GRANT TRIGGER ON TABLE public.competition_reward_rules TO authenticated;
GRANT TRUNCATE ON TABLE public.competition_reward_rules TO authenticated;
GRANT UPDATE ON TABLE public.competition_reward_rules TO authenticated;
GRANT DELETE ON TABLE public.competition_reward_rules TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.competition_reward_rules TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.competition_reward_rules TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.competition_reward_rules TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.competition_reward_rules TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.competition_reward_rules TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.competition_reward_rules TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.competition_reward_rules TO service_role;
GRANT INSERT ON TABLE public.competition_reward_rules TO service_role;
GRANT REFERENCES ON TABLE public.competition_reward_rules TO service_role;
GRANT SELECT ON TABLE public.competition_reward_rules TO service_role;
GRANT TRIGGER ON TABLE public.competition_reward_rules TO service_role;
GRANT TRUNCATE ON TABLE public.competition_reward_rules TO service_role;
GRANT UPDATE ON TABLE public.competition_reward_rules TO service_role;
GRANT DELETE ON TABLE public.competition_waitlist TO anon;
GRANT INSERT ON TABLE public.competition_waitlist TO anon;
GRANT REFERENCES ON TABLE public.competition_waitlist TO anon;
GRANT SELECT ON TABLE public.competition_waitlist TO anon;
GRANT TRIGGER ON TABLE public.competition_waitlist TO anon;
GRANT TRUNCATE ON TABLE public.competition_waitlist TO anon;
GRANT UPDATE ON TABLE public.competition_waitlist TO anon;
GRANT DELETE ON TABLE public.competition_waitlist TO authenticated;
GRANT INSERT ON TABLE public.competition_waitlist TO authenticated;
GRANT REFERENCES ON TABLE public.competition_waitlist TO authenticated;
GRANT SELECT ON TABLE public.competition_waitlist TO authenticated;
GRANT TRIGGER ON TABLE public.competition_waitlist TO authenticated;
GRANT TRUNCATE ON TABLE public.competition_waitlist TO authenticated;
GRANT UPDATE ON TABLE public.competition_waitlist TO authenticated;
GRANT DELETE ON TABLE public.competition_waitlist TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.competition_waitlist TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.competition_waitlist TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.competition_waitlist TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.competition_waitlist TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.competition_waitlist TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.competition_waitlist TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.competition_waitlist TO service_role;
GRANT INSERT ON TABLE public.competition_waitlist TO service_role;
GRANT REFERENCES ON TABLE public.competition_waitlist TO service_role;
GRANT SELECT ON TABLE public.competition_waitlist TO service_role;
GRANT TRIGGER ON TABLE public.competition_waitlist TO service_role;
GRANT TRUNCATE ON TABLE public.competition_waitlist TO service_role;
GRANT UPDATE ON TABLE public.competition_waitlist TO service_role;
GRANT DELETE ON TABLE public.competitions TO anon;
GRANT INSERT ON TABLE public.competitions TO anon;
GRANT REFERENCES ON TABLE public.competitions TO anon;
GRANT SELECT ON TABLE public.competitions TO anon;
GRANT TRIGGER ON TABLE public.competitions TO anon;
GRANT TRUNCATE ON TABLE public.competitions TO anon;
GRANT UPDATE ON TABLE public.competitions TO anon;
GRANT DELETE ON TABLE public.competitions TO authenticated;
GRANT INSERT ON TABLE public.competitions TO authenticated;
GRANT REFERENCES ON TABLE public.competitions TO authenticated;
GRANT SELECT ON TABLE public.competitions TO authenticated;
GRANT TRIGGER ON TABLE public.competitions TO authenticated;
GRANT TRUNCATE ON TABLE public.competitions TO authenticated;
GRANT UPDATE ON TABLE public.competitions TO authenticated;
GRANT DELETE ON TABLE public.competitions TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.competitions TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.competitions TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.competitions TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.competitions TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.competitions TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.competitions TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.competitions TO service_role;
GRANT INSERT ON TABLE public.competitions TO service_role;
GRANT REFERENCES ON TABLE public.competitions TO service_role;
GRANT SELECT ON TABLE public.competitions TO service_role;
GRANT TRIGGER ON TABLE public.competitions TO service_role;
GRANT TRUNCATE ON TABLE public.competitions TO service_role;
GRANT UPDATE ON TABLE public.competitions TO service_role;
GRANT DELETE ON TABLE public.coupons TO anon;
GRANT INSERT ON TABLE public.coupons TO anon;
GRANT REFERENCES ON TABLE public.coupons TO anon;
GRANT SELECT ON TABLE public.coupons TO anon;
GRANT TRIGGER ON TABLE public.coupons TO anon;
GRANT TRUNCATE ON TABLE public.coupons TO anon;
GRANT UPDATE ON TABLE public.coupons TO anon;
GRANT DELETE ON TABLE public.coupons TO authenticated;
GRANT INSERT ON TABLE public.coupons TO authenticated;
GRANT REFERENCES ON TABLE public.coupons TO authenticated;
GRANT SELECT ON TABLE public.coupons TO authenticated;
GRANT TRIGGER ON TABLE public.coupons TO authenticated;
GRANT TRUNCATE ON TABLE public.coupons TO authenticated;
GRANT UPDATE ON TABLE public.coupons TO authenticated;
GRANT DELETE ON TABLE public.coupons TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.coupons TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.coupons TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.coupons TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.coupons TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.coupons TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.coupons TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.coupons TO service_role;
GRANT INSERT ON TABLE public.coupons TO service_role;
GRANT REFERENCES ON TABLE public.coupons TO service_role;
GRANT SELECT ON TABLE public.coupons TO service_role;
GRANT TRIGGER ON TABLE public.coupons TO service_role;
GRANT TRUNCATE ON TABLE public.coupons TO service_role;
GRANT UPDATE ON TABLE public.coupons TO service_role;
GRANT DELETE ON TABLE public.device_push_tokens TO anon;
GRANT INSERT ON TABLE public.device_push_tokens TO anon;
GRANT REFERENCES ON TABLE public.device_push_tokens TO anon;
GRANT SELECT ON TABLE public.device_push_tokens TO anon;
GRANT TRIGGER ON TABLE public.device_push_tokens TO anon;
GRANT TRUNCATE ON TABLE public.device_push_tokens TO anon;
GRANT UPDATE ON TABLE public.device_push_tokens TO anon;
GRANT DELETE ON TABLE public.device_push_tokens TO authenticated;
GRANT INSERT ON TABLE public.device_push_tokens TO authenticated;
GRANT REFERENCES ON TABLE public.device_push_tokens TO authenticated;
GRANT SELECT ON TABLE public.device_push_tokens TO authenticated;
GRANT TRIGGER ON TABLE public.device_push_tokens TO authenticated;
GRANT TRUNCATE ON TABLE public.device_push_tokens TO authenticated;
GRANT UPDATE ON TABLE public.device_push_tokens TO authenticated;
GRANT DELETE ON TABLE public.device_push_tokens TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.device_push_tokens TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.device_push_tokens TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.device_push_tokens TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.device_push_tokens TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.device_push_tokens TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.device_push_tokens TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.device_push_tokens TO service_role;
GRANT INSERT ON TABLE public.device_push_tokens TO service_role;
GRANT REFERENCES ON TABLE public.device_push_tokens TO service_role;
GRANT SELECT ON TABLE public.device_push_tokens TO service_role;
GRANT TRIGGER ON TABLE public.device_push_tokens TO service_role;
GRANT TRUNCATE ON TABLE public.device_push_tokens TO service_role;
GRANT UPDATE ON TABLE public.device_push_tokens TO service_role;
GRANT DELETE ON TABLE public.download_files TO anon;
GRANT INSERT ON TABLE public.download_files TO anon;
GRANT REFERENCES ON TABLE public.download_files TO anon;
GRANT SELECT ON TABLE public.download_files TO anon;
GRANT TRIGGER ON TABLE public.download_files TO anon;
GRANT TRUNCATE ON TABLE public.download_files TO anon;
GRANT UPDATE ON TABLE public.download_files TO anon;
GRANT DELETE ON TABLE public.download_files TO authenticated;
GRANT INSERT ON TABLE public.download_files TO authenticated;
GRANT REFERENCES ON TABLE public.download_files TO authenticated;
GRANT SELECT ON TABLE public.download_files TO authenticated;
GRANT TRIGGER ON TABLE public.download_files TO authenticated;
GRANT TRUNCATE ON TABLE public.download_files TO authenticated;
GRANT UPDATE ON TABLE public.download_files TO authenticated;
GRANT DELETE ON TABLE public.download_files TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.download_files TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.download_files TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.download_files TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.download_files TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.download_files TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.download_files TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.download_files TO service_role;
GRANT INSERT ON TABLE public.download_files TO service_role;
GRANT REFERENCES ON TABLE public.download_files TO service_role;
GRANT SELECT ON TABLE public.download_files TO service_role;
GRANT TRIGGER ON TABLE public.download_files TO service_role;
GRANT TRUNCATE ON TABLE public.download_files TO service_role;
GRANT UPDATE ON TABLE public.download_files TO service_role;
GRANT DELETE ON TABLE public.form_answers TO anon;
GRANT INSERT ON TABLE public.form_answers TO anon;
GRANT REFERENCES ON TABLE public.form_answers TO anon;
GRANT SELECT ON TABLE public.form_answers TO anon;
GRANT TRIGGER ON TABLE public.form_answers TO anon;
GRANT TRUNCATE ON TABLE public.form_answers TO anon;
GRANT UPDATE ON TABLE public.form_answers TO anon;
GRANT DELETE ON TABLE public.form_answers TO authenticated;
GRANT INSERT ON TABLE public.form_answers TO authenticated;
GRANT REFERENCES ON TABLE public.form_answers TO authenticated;
GRANT SELECT ON TABLE public.form_answers TO authenticated;
GRANT TRIGGER ON TABLE public.form_answers TO authenticated;
GRANT TRUNCATE ON TABLE public.form_answers TO authenticated;
GRANT UPDATE ON TABLE public.form_answers TO authenticated;
GRANT DELETE ON TABLE public.form_answers TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.form_answers TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.form_answers TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.form_answers TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.form_answers TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.form_answers TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.form_answers TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.form_answers TO service_role;
GRANT INSERT ON TABLE public.form_answers TO service_role;
GRANT REFERENCES ON TABLE public.form_answers TO service_role;
GRANT SELECT ON TABLE public.form_answers TO service_role;
GRANT TRIGGER ON TABLE public.form_answers TO service_role;
GRANT TRUNCATE ON TABLE public.form_answers TO service_role;
GRANT UPDATE ON TABLE public.form_answers TO service_role;
GRANT DELETE ON TABLE public.form_questions TO anon;
GRANT INSERT ON TABLE public.form_questions TO anon;
GRANT REFERENCES ON TABLE public.form_questions TO anon;
GRANT SELECT ON TABLE public.form_questions TO anon;
GRANT TRIGGER ON TABLE public.form_questions TO anon;
GRANT TRUNCATE ON TABLE public.form_questions TO anon;
GRANT UPDATE ON TABLE public.form_questions TO anon;
GRANT DELETE ON TABLE public.form_questions TO authenticated;
GRANT INSERT ON TABLE public.form_questions TO authenticated;
GRANT REFERENCES ON TABLE public.form_questions TO authenticated;
GRANT SELECT ON TABLE public.form_questions TO authenticated;
GRANT TRIGGER ON TABLE public.form_questions TO authenticated;
GRANT TRUNCATE ON TABLE public.form_questions TO authenticated;
GRANT UPDATE ON TABLE public.form_questions TO authenticated;
GRANT DELETE ON TABLE public.form_questions TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.form_questions TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.form_questions TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.form_questions TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.form_questions TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.form_questions TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.form_questions TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.form_questions TO service_role;
GRANT INSERT ON TABLE public.form_questions TO service_role;
GRANT REFERENCES ON TABLE public.form_questions TO service_role;
GRANT SELECT ON TABLE public.form_questions TO service_role;
GRANT TRIGGER ON TABLE public.form_questions TO service_role;
GRANT TRUNCATE ON TABLE public.form_questions TO service_role;
GRANT UPDATE ON TABLE public.form_questions TO service_role;
GRANT DELETE ON TABLE public.form_responses TO anon;
GRANT INSERT ON TABLE public.form_responses TO anon;
GRANT REFERENCES ON TABLE public.form_responses TO anon;
GRANT SELECT ON TABLE public.form_responses TO anon;
GRANT TRIGGER ON TABLE public.form_responses TO anon;
GRANT TRUNCATE ON TABLE public.form_responses TO anon;
GRANT UPDATE ON TABLE public.form_responses TO anon;
GRANT DELETE ON TABLE public.form_responses TO authenticated;
GRANT INSERT ON TABLE public.form_responses TO authenticated;
GRANT REFERENCES ON TABLE public.form_responses TO authenticated;
GRANT SELECT ON TABLE public.form_responses TO authenticated;
GRANT TRIGGER ON TABLE public.form_responses TO authenticated;
GRANT TRUNCATE ON TABLE public.form_responses TO authenticated;
GRANT UPDATE ON TABLE public.form_responses TO authenticated;
GRANT DELETE ON TABLE public.form_responses TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.form_responses TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.form_responses TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.form_responses TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.form_responses TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.form_responses TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.form_responses TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.form_responses TO service_role;
GRANT INSERT ON TABLE public.form_responses TO service_role;
GRANT REFERENCES ON TABLE public.form_responses TO service_role;
GRANT SELECT ON TABLE public.form_responses TO service_role;
GRANT TRIGGER ON TABLE public.form_responses TO service_role;
GRANT TRUNCATE ON TABLE public.form_responses TO service_role;
GRANT UPDATE ON TABLE public.form_responses TO service_role;
GRANT DELETE ON TABLE public.forms TO anon;
GRANT INSERT ON TABLE public.forms TO anon;
GRANT REFERENCES ON TABLE public.forms TO anon;
GRANT SELECT ON TABLE public.forms TO anon;
GRANT TRIGGER ON TABLE public.forms TO anon;
GRANT TRUNCATE ON TABLE public.forms TO anon;
GRANT UPDATE ON TABLE public.forms TO anon;
GRANT DELETE ON TABLE public.forms TO authenticated;
GRANT INSERT ON TABLE public.forms TO authenticated;
GRANT REFERENCES ON TABLE public.forms TO authenticated;
GRANT SELECT ON TABLE public.forms TO authenticated;
GRANT TRIGGER ON TABLE public.forms TO authenticated;
GRANT TRUNCATE ON TABLE public.forms TO authenticated;
GRANT UPDATE ON TABLE public.forms TO authenticated;
GRANT DELETE ON TABLE public.forms TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.forms TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.forms TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.forms TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.forms TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.forms TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.forms TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.forms TO service_role;
GRANT INSERT ON TABLE public.forms TO service_role;
GRANT REFERENCES ON TABLE public.forms TO service_role;
GRANT SELECT ON TABLE public.forms TO service_role;
GRANT TRIGGER ON TABLE public.forms TO service_role;
GRANT TRUNCATE ON TABLE public.forms TO service_role;
GRANT UPDATE ON TABLE public.forms TO service_role;
GRANT DELETE ON TABLE public.growth_achievement_unlock_history TO anon;
GRANT INSERT ON TABLE public.growth_achievement_unlock_history TO anon;
GRANT REFERENCES ON TABLE public.growth_achievement_unlock_history TO anon;
GRANT SELECT ON TABLE public.growth_achievement_unlock_history TO anon;
GRANT TRIGGER ON TABLE public.growth_achievement_unlock_history TO anon;
GRANT TRUNCATE ON TABLE public.growth_achievement_unlock_history TO anon;
GRANT UPDATE ON TABLE public.growth_achievement_unlock_history TO anon;
GRANT DELETE ON TABLE public.growth_achievement_unlock_history TO authenticated;
GRANT INSERT ON TABLE public.growth_achievement_unlock_history TO authenticated;
GRANT REFERENCES ON TABLE public.growth_achievement_unlock_history TO authenticated;
GRANT SELECT ON TABLE public.growth_achievement_unlock_history TO authenticated;
GRANT TRIGGER ON TABLE public.growth_achievement_unlock_history TO authenticated;
GRANT TRUNCATE ON TABLE public.growth_achievement_unlock_history TO authenticated;
GRANT UPDATE ON TABLE public.growth_achievement_unlock_history TO authenticated;
GRANT DELETE ON TABLE public.growth_achievement_unlock_history TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.growth_achievement_unlock_history TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.growth_achievement_unlock_history TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.growth_achievement_unlock_history TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.growth_achievement_unlock_history TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.growth_achievement_unlock_history TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.growth_achievement_unlock_history TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.growth_achievement_unlock_history TO service_role;
GRANT INSERT ON TABLE public.growth_achievement_unlock_history TO service_role;
GRANT REFERENCES ON TABLE public.growth_achievement_unlock_history TO service_role;
GRANT SELECT ON TABLE public.growth_achievement_unlock_history TO service_role;
GRANT TRIGGER ON TABLE public.growth_achievement_unlock_history TO service_role;
GRANT TRUNCATE ON TABLE public.growth_achievement_unlock_history TO service_role;
GRANT UPDATE ON TABLE public.growth_achievement_unlock_history TO service_role;
GRANT DELETE ON TABLE public.growth_achievements TO anon;
GRANT INSERT ON TABLE public.growth_achievements TO anon;
GRANT REFERENCES ON TABLE public.growth_achievements TO anon;
GRANT SELECT ON TABLE public.growth_achievements TO anon;
GRANT TRIGGER ON TABLE public.growth_achievements TO anon;
GRANT TRUNCATE ON TABLE public.growth_achievements TO anon;
GRANT UPDATE ON TABLE public.growth_achievements TO anon;
GRANT DELETE ON TABLE public.growth_achievements TO authenticated;
GRANT INSERT ON TABLE public.growth_achievements TO authenticated;
GRANT REFERENCES ON TABLE public.growth_achievements TO authenticated;
GRANT SELECT ON TABLE public.growth_achievements TO authenticated;
GRANT TRIGGER ON TABLE public.growth_achievements TO authenticated;
GRANT TRUNCATE ON TABLE public.growth_achievements TO authenticated;
GRANT UPDATE ON TABLE public.growth_achievements TO authenticated;
GRANT DELETE ON TABLE public.growth_achievements TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.growth_achievements TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.growth_achievements TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.growth_achievements TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.growth_achievements TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.growth_achievements TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.growth_achievements TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.growth_achievements TO service_role;
GRANT INSERT ON TABLE public.growth_achievements TO service_role;
GRANT REFERENCES ON TABLE public.growth_achievements TO service_role;
GRANT SELECT ON TABLE public.growth_achievements TO service_role;
GRANT TRIGGER ON TABLE public.growth_achievements TO service_role;
GRANT TRUNCATE ON TABLE public.growth_achievements TO service_role;
GRANT UPDATE ON TABLE public.growth_achievements TO service_role;
GRANT DELETE ON TABLE public.growth_activity_days TO anon;
GRANT INSERT ON TABLE public.growth_activity_days TO anon;
GRANT REFERENCES ON TABLE public.growth_activity_days TO anon;
GRANT SELECT ON TABLE public.growth_activity_days TO anon;
GRANT TRIGGER ON TABLE public.growth_activity_days TO anon;
GRANT TRUNCATE ON TABLE public.growth_activity_days TO anon;
GRANT UPDATE ON TABLE public.growth_activity_days TO anon;
GRANT DELETE ON TABLE public.growth_activity_days TO authenticated;
GRANT INSERT ON TABLE public.growth_activity_days TO authenticated;
GRANT REFERENCES ON TABLE public.growth_activity_days TO authenticated;
GRANT SELECT ON TABLE public.growth_activity_days TO authenticated;
GRANT TRIGGER ON TABLE public.growth_activity_days TO authenticated;
GRANT TRUNCATE ON TABLE public.growth_activity_days TO authenticated;
GRANT UPDATE ON TABLE public.growth_activity_days TO authenticated;
GRANT DELETE ON TABLE public.growth_activity_days TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.growth_activity_days TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.growth_activity_days TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.growth_activity_days TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.growth_activity_days TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.growth_activity_days TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.growth_activity_days TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.growth_activity_days TO service_role;
GRANT INSERT ON TABLE public.growth_activity_days TO service_role;
GRANT REFERENCES ON TABLE public.growth_activity_days TO service_role;
GRANT SELECT ON TABLE public.growth_activity_days TO service_role;
GRANT TRIGGER ON TABLE public.growth_activity_days TO service_role;
GRANT TRUNCATE ON TABLE public.growth_activity_days TO service_role;
GRANT UPDATE ON TABLE public.growth_activity_days TO service_role;
GRANT DELETE ON TABLE public.growth_levels TO anon;
GRANT INSERT ON TABLE public.growth_levels TO anon;
GRANT REFERENCES ON TABLE public.growth_levels TO anon;
GRANT SELECT ON TABLE public.growth_levels TO anon;
GRANT TRIGGER ON TABLE public.growth_levels TO anon;
GRANT TRUNCATE ON TABLE public.growth_levels TO anon;
GRANT UPDATE ON TABLE public.growth_levels TO anon;
GRANT DELETE ON TABLE public.growth_levels TO authenticated;
GRANT INSERT ON TABLE public.growth_levels TO authenticated;
GRANT REFERENCES ON TABLE public.growth_levels TO authenticated;
GRANT SELECT ON TABLE public.growth_levels TO authenticated;
GRANT TRIGGER ON TABLE public.growth_levels TO authenticated;
GRANT TRUNCATE ON TABLE public.growth_levels TO authenticated;
GRANT UPDATE ON TABLE public.growth_levels TO authenticated;
GRANT DELETE ON TABLE public.growth_levels TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.growth_levels TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.growth_levels TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.growth_levels TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.growth_levels TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.growth_levels TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.growth_levels TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.growth_levels TO service_role;
GRANT INSERT ON TABLE public.growth_levels TO service_role;
GRANT REFERENCES ON TABLE public.growth_levels TO service_role;
GRANT SELECT ON TABLE public.growth_levels TO service_role;
GRANT TRIGGER ON TABLE public.growth_levels TO service_role;
GRANT TRUNCATE ON TABLE public.growth_levels TO service_role;
GRANT UPDATE ON TABLE public.growth_levels TO service_role;
GRANT DELETE ON TABLE public.growth_point_transactions TO anon;
GRANT INSERT ON TABLE public.growth_point_transactions TO anon;
GRANT REFERENCES ON TABLE public.growth_point_transactions TO anon;
GRANT SELECT ON TABLE public.growth_point_transactions TO anon;
GRANT TRIGGER ON TABLE public.growth_point_transactions TO anon;
GRANT TRUNCATE ON TABLE public.growth_point_transactions TO anon;
GRANT UPDATE ON TABLE public.growth_point_transactions TO anon;
GRANT DELETE ON TABLE public.growth_point_transactions TO authenticated;
GRANT INSERT ON TABLE public.growth_point_transactions TO authenticated;
GRANT REFERENCES ON TABLE public.growth_point_transactions TO authenticated;
GRANT SELECT ON TABLE public.growth_point_transactions TO authenticated;
GRANT TRIGGER ON TABLE public.growth_point_transactions TO authenticated;
GRANT TRUNCATE ON TABLE public.growth_point_transactions TO authenticated;
GRANT UPDATE ON TABLE public.growth_point_transactions TO authenticated;
GRANT DELETE ON TABLE public.growth_point_transactions TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.growth_point_transactions TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.growth_point_transactions TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.growth_point_transactions TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.growth_point_transactions TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.growth_point_transactions TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.growth_point_transactions TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.growth_point_transactions TO service_role;
GRANT INSERT ON TABLE public.growth_point_transactions TO service_role;
GRANT REFERENCES ON TABLE public.growth_point_transactions TO service_role;
GRANT SELECT ON TABLE public.growth_point_transactions TO service_role;
GRANT TRIGGER ON TABLE public.growth_point_transactions TO service_role;
GRANT TRUNCATE ON TABLE public.growth_point_transactions TO service_role;
GRANT UPDATE ON TABLE public.growth_point_transactions TO service_role;
GRANT DELETE ON TABLE public.growth_reset_history TO anon;
GRANT INSERT ON TABLE public.growth_reset_history TO anon;
GRANT REFERENCES ON TABLE public.growth_reset_history TO anon;
GRANT SELECT ON TABLE public.growth_reset_history TO anon;
GRANT TRIGGER ON TABLE public.growth_reset_history TO anon;
GRANT TRUNCATE ON TABLE public.growth_reset_history TO anon;
GRANT UPDATE ON TABLE public.growth_reset_history TO anon;
GRANT DELETE ON TABLE public.growth_reset_history TO authenticated;
GRANT INSERT ON TABLE public.growth_reset_history TO authenticated;
GRANT REFERENCES ON TABLE public.growth_reset_history TO authenticated;
GRANT SELECT ON TABLE public.growth_reset_history TO authenticated;
GRANT TRIGGER ON TABLE public.growth_reset_history TO authenticated;
GRANT TRUNCATE ON TABLE public.growth_reset_history TO authenticated;
GRANT UPDATE ON TABLE public.growth_reset_history TO authenticated;
GRANT DELETE ON TABLE public.growth_reset_history TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.growth_reset_history TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.growth_reset_history TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.growth_reset_history TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.growth_reset_history TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.growth_reset_history TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.growth_reset_history TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.growth_reset_history TO service_role;
GRANT INSERT ON TABLE public.growth_reset_history TO service_role;
GRANT REFERENCES ON TABLE public.growth_reset_history TO service_role;
GRANT SELECT ON TABLE public.growth_reset_history TO service_role;
GRANT TRIGGER ON TABLE public.growth_reset_history TO service_role;
GRANT TRUNCATE ON TABLE public.growth_reset_history TO service_role;
GRANT UPDATE ON TABLE public.growth_reset_history TO service_role;
GRANT DELETE ON TABLE public.growth_reward_redemptions TO anon;
GRANT INSERT ON TABLE public.growth_reward_redemptions TO anon;
GRANT REFERENCES ON TABLE public.growth_reward_redemptions TO anon;
GRANT SELECT ON TABLE public.growth_reward_redemptions TO anon;
GRANT TRIGGER ON TABLE public.growth_reward_redemptions TO anon;
GRANT TRUNCATE ON TABLE public.growth_reward_redemptions TO anon;
GRANT UPDATE ON TABLE public.growth_reward_redemptions TO anon;
GRANT DELETE ON TABLE public.growth_reward_redemptions TO authenticated;
GRANT INSERT ON TABLE public.growth_reward_redemptions TO authenticated;
GRANT REFERENCES ON TABLE public.growth_reward_redemptions TO authenticated;
GRANT SELECT ON TABLE public.growth_reward_redemptions TO authenticated;
GRANT TRIGGER ON TABLE public.growth_reward_redemptions TO authenticated;
GRANT TRUNCATE ON TABLE public.growth_reward_redemptions TO authenticated;
GRANT UPDATE ON TABLE public.growth_reward_redemptions TO authenticated;
GRANT DELETE ON TABLE public.growth_reward_redemptions TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.growth_reward_redemptions TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.growth_reward_redemptions TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.growth_reward_redemptions TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.growth_reward_redemptions TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.growth_reward_redemptions TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.growth_reward_redemptions TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.growth_reward_redemptions TO service_role;
GRANT INSERT ON TABLE public.growth_reward_redemptions TO service_role;
GRANT REFERENCES ON TABLE public.growth_reward_redemptions TO service_role;
GRANT SELECT ON TABLE public.growth_reward_redemptions TO service_role;
GRANT TRIGGER ON TABLE public.growth_reward_redemptions TO service_role;
GRANT TRUNCATE ON TABLE public.growth_reward_redemptions TO service_role;
GRANT UPDATE ON TABLE public.growth_reward_redemptions TO service_role;
GRANT DELETE ON TABLE public.growth_rewards TO anon;
GRANT INSERT ON TABLE public.growth_rewards TO anon;
GRANT REFERENCES ON TABLE public.growth_rewards TO anon;
GRANT SELECT ON TABLE public.growth_rewards TO anon;
GRANT TRIGGER ON TABLE public.growth_rewards TO anon;
GRANT TRUNCATE ON TABLE public.growth_rewards TO anon;
GRANT UPDATE ON TABLE public.growth_rewards TO anon;
GRANT DELETE ON TABLE public.growth_rewards TO authenticated;
GRANT INSERT ON TABLE public.growth_rewards TO authenticated;
GRANT REFERENCES ON TABLE public.growth_rewards TO authenticated;
GRANT SELECT ON TABLE public.growth_rewards TO authenticated;
GRANT TRIGGER ON TABLE public.growth_rewards TO authenticated;
GRANT TRUNCATE ON TABLE public.growth_rewards TO authenticated;
GRANT UPDATE ON TABLE public.growth_rewards TO authenticated;
GRANT DELETE ON TABLE public.growth_rewards TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.growth_rewards TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.growth_rewards TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.growth_rewards TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.growth_rewards TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.growth_rewards TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.growth_rewards TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.growth_rewards TO service_role;
GRANT INSERT ON TABLE public.growth_rewards TO service_role;
GRANT REFERENCES ON TABLE public.growth_rewards TO service_role;
GRANT SELECT ON TABLE public.growth_rewards TO service_role;
GRANT TRIGGER ON TABLE public.growth_rewards TO service_role;
GRANT TRUNCATE ON TABLE public.growth_rewards TO service_role;
GRANT UPDATE ON TABLE public.growth_rewards TO service_role;
GRANT DELETE ON TABLE public.growth_tasks TO anon;
GRANT INSERT ON TABLE public.growth_tasks TO anon;
GRANT REFERENCES ON TABLE public.growth_tasks TO anon;
GRANT SELECT ON TABLE public.growth_tasks TO anon;
GRANT TRIGGER ON TABLE public.growth_tasks TO anon;
GRANT TRUNCATE ON TABLE public.growth_tasks TO anon;
GRANT UPDATE ON TABLE public.growth_tasks TO anon;
GRANT DELETE ON TABLE public.growth_tasks TO authenticated;
GRANT INSERT ON TABLE public.growth_tasks TO authenticated;
GRANT REFERENCES ON TABLE public.growth_tasks TO authenticated;
GRANT SELECT ON TABLE public.growth_tasks TO authenticated;
GRANT TRIGGER ON TABLE public.growth_tasks TO authenticated;
GRANT TRUNCATE ON TABLE public.growth_tasks TO authenticated;
GRANT UPDATE ON TABLE public.growth_tasks TO authenticated;
GRANT DELETE ON TABLE public.growth_tasks TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.growth_tasks TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.growth_tasks TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.growth_tasks TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.growth_tasks TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.growth_tasks TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.growth_tasks TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.growth_tasks TO service_role;
GRANT INSERT ON TABLE public.growth_tasks TO service_role;
GRANT REFERENCES ON TABLE public.growth_tasks TO service_role;
GRANT SELECT ON TABLE public.growth_tasks TO service_role;
GRANT TRIGGER ON TABLE public.growth_tasks TO service_role;
GRANT TRUNCATE ON TABLE public.growth_tasks TO service_role;
GRANT UPDATE ON TABLE public.growth_tasks TO service_role;
GRANT DELETE ON TABLE public.growth_user_achievements TO anon;
GRANT INSERT ON TABLE public.growth_user_achievements TO anon;
GRANT REFERENCES ON TABLE public.growth_user_achievements TO anon;
GRANT SELECT ON TABLE public.growth_user_achievements TO anon;
GRANT TRIGGER ON TABLE public.growth_user_achievements TO anon;
GRANT TRUNCATE ON TABLE public.growth_user_achievements TO anon;
GRANT UPDATE ON TABLE public.growth_user_achievements TO anon;
GRANT DELETE ON TABLE public.growth_user_achievements TO authenticated;
GRANT INSERT ON TABLE public.growth_user_achievements TO authenticated;
GRANT REFERENCES ON TABLE public.growth_user_achievements TO authenticated;
GRANT SELECT ON TABLE public.growth_user_achievements TO authenticated;
GRANT TRIGGER ON TABLE public.growth_user_achievements TO authenticated;
GRANT TRUNCATE ON TABLE public.growth_user_achievements TO authenticated;
GRANT UPDATE ON TABLE public.growth_user_achievements TO authenticated;
GRANT DELETE ON TABLE public.growth_user_achievements TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.growth_user_achievements TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.growth_user_achievements TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.growth_user_achievements TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.growth_user_achievements TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.growth_user_achievements TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.growth_user_achievements TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.growth_user_achievements TO service_role;
GRANT INSERT ON TABLE public.growth_user_achievements TO service_role;
GRANT REFERENCES ON TABLE public.growth_user_achievements TO service_role;
GRANT SELECT ON TABLE public.growth_user_achievements TO service_role;
GRANT TRIGGER ON TABLE public.growth_user_achievements TO service_role;
GRANT TRUNCATE ON TABLE public.growth_user_achievements TO service_role;
GRANT UPDATE ON TABLE public.growth_user_achievements TO service_role;
GRANT DELETE ON TABLE public.growth_user_tasks TO anon;
GRANT INSERT ON TABLE public.growth_user_tasks TO anon;
GRANT REFERENCES ON TABLE public.growth_user_tasks TO anon;
GRANT SELECT ON TABLE public.growth_user_tasks TO anon;
GRANT TRIGGER ON TABLE public.growth_user_tasks TO anon;
GRANT TRUNCATE ON TABLE public.growth_user_tasks TO anon;
GRANT UPDATE ON TABLE public.growth_user_tasks TO anon;
GRANT DELETE ON TABLE public.growth_user_tasks TO authenticated;
GRANT INSERT ON TABLE public.growth_user_tasks TO authenticated;
GRANT REFERENCES ON TABLE public.growth_user_tasks TO authenticated;
GRANT SELECT ON TABLE public.growth_user_tasks TO authenticated;
GRANT TRIGGER ON TABLE public.growth_user_tasks TO authenticated;
GRANT TRUNCATE ON TABLE public.growth_user_tasks TO authenticated;
GRANT UPDATE ON TABLE public.growth_user_tasks TO authenticated;
GRANT DELETE ON TABLE public.growth_user_tasks TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.growth_user_tasks TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.growth_user_tasks TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.growth_user_tasks TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.growth_user_tasks TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.growth_user_tasks TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.growth_user_tasks TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.growth_user_tasks TO service_role;
GRANT INSERT ON TABLE public.growth_user_tasks TO service_role;
GRANT REFERENCES ON TABLE public.growth_user_tasks TO service_role;
GRANT SELECT ON TABLE public.growth_user_tasks TO service_role;
GRANT TRIGGER ON TABLE public.growth_user_tasks TO service_role;
GRANT TRUNCATE ON TABLE public.growth_user_tasks TO service_role;
GRANT UPDATE ON TABLE public.growth_user_tasks TO service_role;
GRANT DELETE ON TABLE public.member_no_counter TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.member_no_counter TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.member_no_counter TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.member_no_counter TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.member_no_counter TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.member_no_counter TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.member_no_counter TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.member_no_counter TO service_role;
GRANT INSERT ON TABLE public.member_no_counter TO service_role;
GRANT REFERENCES ON TABLE public.member_no_counter TO service_role;
GRANT SELECT ON TABLE public.member_no_counter TO service_role;
GRANT TRIGGER ON TABLE public.member_no_counter TO service_role;
GRANT TRUNCATE ON TABLE public.member_no_counter TO service_role;
GRANT UPDATE ON TABLE public.member_no_counter TO service_role;
GRANT DELETE ON TABLE public.notifications TO anon;
GRANT INSERT ON TABLE public.notifications TO anon;
GRANT REFERENCES ON TABLE public.notifications TO anon;
GRANT SELECT ON TABLE public.notifications TO anon;
GRANT TRIGGER ON TABLE public.notifications TO anon;
GRANT TRUNCATE ON TABLE public.notifications TO anon;
GRANT UPDATE ON TABLE public.notifications TO anon;
GRANT DELETE ON TABLE public.notifications TO authenticated;
GRANT INSERT ON TABLE public.notifications TO authenticated;
GRANT REFERENCES ON TABLE public.notifications TO authenticated;
GRANT SELECT ON TABLE public.notifications TO authenticated;
GRANT TRIGGER ON TABLE public.notifications TO authenticated;
GRANT TRUNCATE ON TABLE public.notifications TO authenticated;
GRANT UPDATE ON TABLE public.notifications TO authenticated;
GRANT DELETE ON TABLE public.notifications TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.notifications TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.notifications TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.notifications TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.notifications TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.notifications TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.notifications TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.notifications TO service_role;
GRANT INSERT ON TABLE public.notifications TO service_role;
GRANT REFERENCES ON TABLE public.notifications TO service_role;
GRANT SELECT ON TABLE public.notifications TO service_role;
GRANT TRIGGER ON TABLE public.notifications TO service_role;
GRANT TRUNCATE ON TABLE public.notifications TO service_role;
GRANT UPDATE ON TABLE public.notifications TO service_role;
GRANT DELETE ON TABLE public.order_items TO anon;
GRANT INSERT ON TABLE public.order_items TO anon;
GRANT REFERENCES ON TABLE public.order_items TO anon;
GRANT SELECT ON TABLE public.order_items TO anon;
GRANT TRIGGER ON TABLE public.order_items TO anon;
GRANT TRUNCATE ON TABLE public.order_items TO anon;
GRANT UPDATE ON TABLE public.order_items TO anon;
GRANT REFERENCES ON TABLE public.order_items TO authenticated;
GRANT SELECT ON TABLE public.order_items TO authenticated;
GRANT TRIGGER ON TABLE public.order_items TO authenticated;
GRANT TRUNCATE ON TABLE public.order_items TO authenticated;
GRANT DELETE ON TABLE public.order_items TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.order_items TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.order_items TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.order_items TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.order_items TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.order_items TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.order_items TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.order_items TO service_role;
GRANT INSERT ON TABLE public.order_items TO service_role;
GRANT REFERENCES ON TABLE public.order_items TO service_role;
GRANT SELECT ON TABLE public.order_items TO service_role;
GRANT TRIGGER ON TABLE public.order_items TO service_role;
GRANT TRUNCATE ON TABLE public.order_items TO service_role;
GRANT UPDATE ON TABLE public.order_items TO service_role;
GRANT DELETE ON TABLE public.orders TO anon;
GRANT INSERT ON TABLE public.orders TO anon;
GRANT REFERENCES ON TABLE public.orders TO anon;
GRANT SELECT ON TABLE public.orders TO anon;
GRANT TRIGGER ON TABLE public.orders TO anon;
GRANT TRUNCATE ON TABLE public.orders TO anon;
GRANT UPDATE ON TABLE public.orders TO anon;
GRANT REFERENCES ON TABLE public.orders TO authenticated;
GRANT SELECT ON TABLE public.orders TO authenticated;
GRANT TRIGGER ON TABLE public.orders TO authenticated;
GRANT TRUNCATE ON TABLE public.orders TO authenticated;
GRANT DELETE ON TABLE public.orders TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.orders TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.orders TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.orders TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.orders TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.orders TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.orders TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.orders TO service_role;
GRANT INSERT ON TABLE public.orders TO service_role;
GRANT REFERENCES ON TABLE public.orders TO service_role;
GRANT SELECT ON TABLE public.orders TO service_role;
GRANT TRIGGER ON TABLE public.orders TO service_role;
GRANT TRUNCATE ON TABLE public.orders TO service_role;
GRANT UPDATE ON TABLE public.orders TO service_role;
GRANT DELETE ON TABLE public.products TO anon;
GRANT INSERT ON TABLE public.products TO anon;
GRANT REFERENCES ON TABLE public.products TO anon;
GRANT SELECT ON TABLE public.products TO anon;
GRANT TRIGGER ON TABLE public.products TO anon;
GRANT TRUNCATE ON TABLE public.products TO anon;
GRANT UPDATE ON TABLE public.products TO anon;
GRANT DELETE ON TABLE public.products TO authenticated;
GRANT INSERT ON TABLE public.products TO authenticated;
GRANT REFERENCES ON TABLE public.products TO authenticated;
GRANT SELECT ON TABLE public.products TO authenticated;
GRANT TRIGGER ON TABLE public.products TO authenticated;
GRANT TRUNCATE ON TABLE public.products TO authenticated;
GRANT UPDATE ON TABLE public.products TO authenticated;
GRANT DELETE ON TABLE public.products TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.products TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.products TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.products TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.products TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.products TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.products TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.products TO service_role;
GRANT INSERT ON TABLE public.products TO service_role;
GRANT REFERENCES ON TABLE public.products TO service_role;
GRANT SELECT ON TABLE public.products TO service_role;
GRANT TRIGGER ON TABLE public.products TO service_role;
GRANT TRUNCATE ON TABLE public.products TO service_role;
GRANT UPDATE ON TABLE public.products TO service_role;
GRANT SELECT ON TABLE public.profiles TO authenticated;
GRANT UPDATE ON TABLE public.profiles TO authenticated;
GRANT DELETE ON TABLE public.profiles TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.profiles TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.profiles TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.profiles TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.profiles TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.profiles TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.profiles TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.profiles TO service_role;
GRANT INSERT ON TABLE public.profiles TO service_role;
GRANT REFERENCES ON TABLE public.profiles TO service_role;
GRANT SELECT ON TABLE public.profiles TO service_role;
GRANT TRIGGER ON TABLE public.profiles TO service_role;
GRANT TRUNCATE ON TABLE public.profiles TO service_role;
GRANT UPDATE ON TABLE public.profiles TO service_role;
GRANT DELETE ON TABLE public.quick_links TO anon;
GRANT INSERT ON TABLE public.quick_links TO anon;
GRANT REFERENCES ON TABLE public.quick_links TO anon;
GRANT SELECT ON TABLE public.quick_links TO anon;
GRANT TRIGGER ON TABLE public.quick_links TO anon;
GRANT TRUNCATE ON TABLE public.quick_links TO anon;
GRANT UPDATE ON TABLE public.quick_links TO anon;
GRANT DELETE ON TABLE public.quick_links TO authenticated;
GRANT INSERT ON TABLE public.quick_links TO authenticated;
GRANT REFERENCES ON TABLE public.quick_links TO authenticated;
GRANT SELECT ON TABLE public.quick_links TO authenticated;
GRANT TRIGGER ON TABLE public.quick_links TO authenticated;
GRANT TRUNCATE ON TABLE public.quick_links TO authenticated;
GRANT UPDATE ON TABLE public.quick_links TO authenticated;
GRANT DELETE ON TABLE public.quick_links TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.quick_links TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.quick_links TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.quick_links TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.quick_links TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.quick_links TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.quick_links TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.quick_links TO service_role;
GRANT INSERT ON TABLE public.quick_links TO service_role;
GRANT REFERENCES ON TABLE public.quick_links TO service_role;
GRANT SELECT ON TABLE public.quick_links TO service_role;
GRANT TRIGGER ON TABLE public.quick_links TO service_role;
GRANT TRUNCATE ON TABLE public.quick_links TO service_role;
GRANT UPDATE ON TABLE public.quick_links TO service_role;
GRANT SELECT ON TABLE public.site_settings TO anon;
GRANT SELECT ON TABLE public.site_settings TO authenticated;
GRANT UPDATE ON TABLE public.site_settings TO authenticated;
GRANT DELETE ON TABLE public.site_settings TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.site_settings TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.site_settings TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.site_settings TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.site_settings TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.site_settings TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.site_settings TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.site_settings TO service_role;
GRANT INSERT ON TABLE public.site_settings TO service_role;
GRANT REFERENCES ON TABLE public.site_settings TO service_role;
GRANT SELECT ON TABLE public.site_settings TO service_role;
GRANT TRIGGER ON TABLE public.site_settings TO service_role;
GRANT TRUNCATE ON TABLE public.site_settings TO service_role;
GRANT UPDATE ON TABLE public.site_settings TO service_role;
GRANT DELETE ON TABLE public.support_tickets TO anon;
GRANT INSERT ON TABLE public.support_tickets TO anon;
GRANT REFERENCES ON TABLE public.support_tickets TO anon;
GRANT SELECT ON TABLE public.support_tickets TO anon;
GRANT TRIGGER ON TABLE public.support_tickets TO anon;
GRANT TRUNCATE ON TABLE public.support_tickets TO anon;
GRANT UPDATE ON TABLE public.support_tickets TO anon;
GRANT DELETE ON TABLE public.support_tickets TO authenticated;
GRANT INSERT ON TABLE public.support_tickets TO authenticated;
GRANT REFERENCES ON TABLE public.support_tickets TO authenticated;
GRANT SELECT ON TABLE public.support_tickets TO authenticated;
GRANT TRIGGER ON TABLE public.support_tickets TO authenticated;
GRANT TRUNCATE ON TABLE public.support_tickets TO authenticated;
GRANT UPDATE ON TABLE public.support_tickets TO authenticated;
GRANT DELETE ON TABLE public.support_tickets TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.support_tickets TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.support_tickets TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.support_tickets TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.support_tickets TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.support_tickets TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.support_tickets TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.support_tickets TO service_role;
GRANT INSERT ON TABLE public.support_tickets TO service_role;
GRANT REFERENCES ON TABLE public.support_tickets TO service_role;
GRANT SELECT ON TABLE public.support_tickets TO service_role;
GRANT TRIGGER ON TABLE public.support_tickets TO service_role;
GRANT TRUNCATE ON TABLE public.support_tickets TO service_role;
GRANT UPDATE ON TABLE public.support_tickets TO service_role;
GRANT DELETE ON TABLE public.user_activity_badges TO anon;
GRANT INSERT ON TABLE public.user_activity_badges TO anon;
GRANT REFERENCES ON TABLE public.user_activity_badges TO anon;
GRANT SELECT ON TABLE public.user_activity_badges TO anon;
GRANT TRIGGER ON TABLE public.user_activity_badges TO anon;
GRANT TRUNCATE ON TABLE public.user_activity_badges TO anon;
GRANT UPDATE ON TABLE public.user_activity_badges TO anon;
GRANT DELETE ON TABLE public.user_activity_badges TO authenticated;
GRANT INSERT ON TABLE public.user_activity_badges TO authenticated;
GRANT REFERENCES ON TABLE public.user_activity_badges TO authenticated;
GRANT SELECT ON TABLE public.user_activity_badges TO authenticated;
GRANT TRIGGER ON TABLE public.user_activity_badges TO authenticated;
GRANT TRUNCATE ON TABLE public.user_activity_badges TO authenticated;
GRANT UPDATE ON TABLE public.user_activity_badges TO authenticated;
GRANT DELETE ON TABLE public.user_activity_badges TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.user_activity_badges TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.user_activity_badges TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.user_activity_badges TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.user_activity_badges TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.user_activity_badges TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.user_activity_badges TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.user_activity_badges TO service_role;
GRANT INSERT ON TABLE public.user_activity_badges TO service_role;
GRANT REFERENCES ON TABLE public.user_activity_badges TO service_role;
GRANT SELECT ON TABLE public.user_activity_badges TO service_role;
GRANT TRIGGER ON TABLE public.user_activity_badges TO service_role;
GRANT TRUNCATE ON TABLE public.user_activity_badges TO service_role;
GRANT UPDATE ON TABLE public.user_activity_badges TO service_role;
GRANT DELETE ON TABLE public.videos TO anon;
GRANT INSERT ON TABLE public.videos TO anon;
GRANT REFERENCES ON TABLE public.videos TO anon;
GRANT SELECT ON TABLE public.videos TO anon;
GRANT TRIGGER ON TABLE public.videos TO anon;
GRANT TRUNCATE ON TABLE public.videos TO anon;
GRANT UPDATE ON TABLE public.videos TO anon;
GRANT DELETE ON TABLE public.videos TO authenticated;
GRANT INSERT ON TABLE public.videos TO authenticated;
GRANT REFERENCES ON TABLE public.videos TO authenticated;
GRANT SELECT ON TABLE public.videos TO authenticated;
GRANT TRIGGER ON TABLE public.videos TO authenticated;
GRANT TRUNCATE ON TABLE public.videos TO authenticated;
GRANT UPDATE ON TABLE public.videos TO authenticated;
GRANT DELETE ON TABLE public.videos TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.videos TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.videos TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.videos TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.videos TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.videos TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.videos TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.videos TO service_role;
GRANT INSERT ON TABLE public.videos TO service_role;
GRANT REFERENCES ON TABLE public.videos TO service_role;
GRANT SELECT ON TABLE public.videos TO service_role;
GRANT TRIGGER ON TABLE public.videos TO service_role;
GRANT TRUNCATE ON TABLE public.videos TO service_role;
GRANT UPDATE ON TABLE public.videos TO service_role;
GRANT DELETE ON TABLE public.visitor_accounts TO anon;
GRANT INSERT ON TABLE public.visitor_accounts TO anon;
GRANT REFERENCES ON TABLE public.visitor_accounts TO anon;
GRANT SELECT ON TABLE public.visitor_accounts TO anon;
GRANT TRIGGER ON TABLE public.visitor_accounts TO anon;
GRANT TRUNCATE ON TABLE public.visitor_accounts TO anon;
GRANT UPDATE ON TABLE public.visitor_accounts TO anon;
GRANT DELETE ON TABLE public.visitor_accounts TO authenticated;
GRANT INSERT ON TABLE public.visitor_accounts TO authenticated;
GRANT REFERENCES ON TABLE public.visitor_accounts TO authenticated;
GRANT SELECT ON TABLE public.visitor_accounts TO authenticated;
GRANT TRIGGER ON TABLE public.visitor_accounts TO authenticated;
GRANT TRUNCATE ON TABLE public.visitor_accounts TO authenticated;
GRANT UPDATE ON TABLE public.visitor_accounts TO authenticated;
GRANT DELETE ON TABLE public.visitor_accounts TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.visitor_accounts TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.visitor_accounts TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.visitor_accounts TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.visitor_accounts TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.visitor_accounts TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.visitor_accounts TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.visitor_accounts TO service_role;
GRANT INSERT ON TABLE public.visitor_accounts TO service_role;
GRANT REFERENCES ON TABLE public.visitor_accounts TO service_role;
GRANT SELECT ON TABLE public.visitor_accounts TO service_role;
GRANT TRIGGER ON TABLE public.visitor_accounts TO service_role;
GRANT TRUNCATE ON TABLE public.visitor_accounts TO service_role;
GRANT UPDATE ON TABLE public.visitor_accounts TO service_role;
GRANT DELETE ON TABLE public.visitor_profiles TO anon;
GRANT INSERT ON TABLE public.visitor_profiles TO anon;
GRANT REFERENCES ON TABLE public.visitor_profiles TO anon;
GRANT SELECT ON TABLE public.visitor_profiles TO anon;
GRANT TRIGGER ON TABLE public.visitor_profiles TO anon;
GRANT TRUNCATE ON TABLE public.visitor_profiles TO anon;
GRANT UPDATE ON TABLE public.visitor_profiles TO anon;
GRANT DELETE ON TABLE public.visitor_profiles TO authenticated;
GRANT INSERT ON TABLE public.visitor_profiles TO authenticated;
GRANT REFERENCES ON TABLE public.visitor_profiles TO authenticated;
GRANT SELECT ON TABLE public.visitor_profiles TO authenticated;
GRANT TRIGGER ON TABLE public.visitor_profiles TO authenticated;
GRANT TRUNCATE ON TABLE public.visitor_profiles TO authenticated;
GRANT UPDATE ON TABLE public.visitor_profiles TO authenticated;
GRANT DELETE ON TABLE public.visitor_profiles TO postgres WITH GRANT OPTION;
GRANT INSERT ON TABLE public.visitor_profiles TO postgres WITH GRANT OPTION;
GRANT REFERENCES ON TABLE public.visitor_profiles TO postgres WITH GRANT OPTION;
GRANT SELECT ON TABLE public.visitor_profiles TO postgres WITH GRANT OPTION;
GRANT TRIGGER ON TABLE public.visitor_profiles TO postgres WITH GRANT OPTION;
GRANT TRUNCATE ON TABLE public.visitor_profiles TO postgres WITH GRANT OPTION;
GRANT UPDATE ON TABLE public.visitor_profiles TO postgres WITH GRANT OPTION;
GRANT DELETE ON TABLE public.visitor_profiles TO service_role;
GRANT INSERT ON TABLE public.visitor_profiles TO service_role;
GRANT REFERENCES ON TABLE public.visitor_profiles TO service_role;
GRANT SELECT ON TABLE public.visitor_profiles TO service_role;
GRANT TRIGGER ON TABLE public.visitor_profiles TO service_role;
GRANT TRUNCATE ON TABLE public.visitor_profiles TO service_role;
GRANT UPDATE ON TABLE public.visitor_profiles TO service_role;

COMMIT;

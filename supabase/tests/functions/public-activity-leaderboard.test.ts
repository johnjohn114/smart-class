import { buildPublicLeaderboard } from "../../functions/public-activity-leaderboard/shared.ts";

Deno.test("public leaderboard exposes only the approved fields", () => {
  const result = buildPublicLeaderboard([
    {
      user_id: "private-user-id",
      nickname: "  星星會員  ",
      attended_count: "4",
      activity_points: 35,
      late_count: 2,
      no_show_count: 1,
      email: "private@example.invalid",
    },
    {
      user_id: "another-private-id",
      nickname: "   ",
      attended_count: 1,
      activity_points: 8,
      late_count: 0,
      no_show_count: 9,
    },
  ]);

  if (result.rows.length !== 2) throw new Error("expected two leaderboard rows");
  if (result.rows[0].nickname !== "星星會員") throw new Error("nickname should be trimmed");
  if (result.rows[1].nickname !== "會員") throw new Error("blank nickname must not expose a user ID");
  if (Object.keys(result.rows[0]).sort().join(",") !== "activity_points,attended_count,late_count,nickname,no_show_count") {
    throw new Error("unexpected public leaderboard fields");
  }
  if (result.rows[0].late_count !== 2 || result.rows[0].no_show_count !== 1) {
    throw new Error("first member's public attendance counters must be preserved");
  }
  if (result.rows[1].late_count !== 0 || result.rows[1].no_show_count !== 9) {
    throw new Error("second member's public attendance counters must be preserved");
  }
  if (JSON.stringify(result).includes("private-user-id") ||
      JSON.stringify(result).includes("another-private-id") ||
      JSON.stringify(result).includes("private@example.invalid")) {
    throw new Error("private identifiers and profile data must not be included in public output");
  }
  if (
    result.summary.total_members !== 2 ||
    result.summary.total_attended !== 5 ||
    result.summary.total_activity_points !== 43
  ) {
    throw new Error("summary totals are incorrect");
  }
});
